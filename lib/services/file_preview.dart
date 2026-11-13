import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'cmyk_tiff.dart';

/// Max size of a preview in a header — same cap as the designer
/// photo thumbnail, so the two together stay well under any
/// header limit.
const int kPreviewMaxBase64 = 32768;

/// Largest design decoded for a preview. A 40 MP file decodes
/// to ~160 MB of CMYK bytes, which a designer PC handles; above
/// that the preview is skipped instead of risking the memory.
/// (The file itself still sends fine — only its preview is lost.)
const int kPreviewMaxPixels = 40 * 1000 * 1000;

/// A small JPEG preview of a CMYK TIFF design (v1.26,
/// suggestion 3), as base64url for the upload header.
///
/// Only TIFFs get a preview: EPS files cannot be rasterised
/// without Ghostscript, and every JPG is rejected by the shop
/// rule anyway. Returns null when there is no preview to make —
/// not a TIFF, too big to decode safely, JPEG-compressed TIFF,
/// or undecodable. The preview is a visual aid only; the sent
/// file itself is never touched, and a missing preview never
/// blocks a send.
Future<String?> designPreviewBase64({
  required File file,
  required String fileName,
}) async {
  final lower = fileName.toLowerCase();
  if (!lower.endsWith('.tif') && !lower.endsWith('.tiff')) {
    return null;
  }
  try {
    // Read only the header first: the dimensions decide whether
    // a full decode is safe, and a huge file must not be
    // decoded whole just to learn it is huge.
    final head = await file
        .openRead(0, 65536)
        .fold<Uint8List>(Uint8List(0),
            (prev, chunk) => Uint8List.fromList([...prev, ...chunk]));
    final dims = _tiffDimensions(head);
    if (dims == null) return null;
    final (width, height) = dims;
    if (width <= 0 || height <= 0) return null;
    if (width * height > kPreviewMaxPixels) return null;

    final bytes = await file.readAsBytes();
    final decoded = decodeCmykTiff(bytes);
    return _encodePreview(decoded);
  } catch (_) {
    return null;
  }
}

/// Encodes a decoded CMYK image as a small JPEG preview. The
/// full-size RGB image is never built: pixels are sampled
/// straight into the small image, so even a 40 MP design costs
/// only ~72K converted pixels.
String? _encodePreview(CmykImage decoded) {
  final w = decoded.width;
  final h = decoded.height;
  for (final targetWidth in [320, 240, 160]) {
    final step = math.max(1, (w / targetWidth).ceil());
    final sw = math.max(1, (w / step).ceil());
    final sh = math.max(1, (h / step).ceil());
    final small = img.Image(width: sw, height: sh);
    final cmyk = decoded.cmyk;
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final srcX = math.min(x * step, w - 1);
        final srcY = math.min(y * step, h - 1);
        final i = (srcY * w + srcX) * 4;
        final c = cmyk[i];
        final m = cmyk[i + 1];
        final yv = cmyk[i + 2];
        final k = cmyk[i + 3];
        // Plain CMYK -> RGB, no ICC: good enough for a preview.
        small.setPixelRgb(
          x,
          y,
          (255 - c) * (255 - k) ~/ 255,
          (255 - m) * (255 - k) ~/ 255,
          (255 - yv) * (255 - k) ~/ 255,
        );
      }
    }
    final jpg = img.encodeJpg(small, quality: 65);
    final encoded = base64UrlEncode(jpg);
    if (encoded.length <= kPreviewMaxBase64) return encoded;
  }
  return null;
}

/// Validates a preview that arrived in a header (printer
/// side): returns the decoded JPEG bytes, or null when the
/// header is missing, malformed, or not a JPEG. A bad preview
/// never breaks the upload — the card just shows no picture.
Uint8List? decodePreviewBase64(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final bytes = base64Url.decode(value);
    if (img.decodeJpg(bytes) == null) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

/// Width + height from a TIFF header, or null when the header
/// cannot be read (too short, bad magic, IFD out of reach).
/// Reads only the 10 bytes that matter — no full parse.
(int, int)? _tiffDimensions(Uint8List head) {
  if (head.length < 8) return null;
  final littleEndian = head[0] == 0x49 && head[1] == 0x49;
  final bigEndian = head[0] == 0x4D && head[1] == 0x4D;
  if (!littleEndian && !bigEndian) return null;
  final data = ByteData.sublistView(head);
  int u16(int offset) => littleEndian
      ? data.getUint16(offset, Endian.little)
      : data.getUint16(offset, Endian.big);
  int u32(int offset) => littleEndian
      ? data.getUint32(offset, Endian.little)
      : data.getUint32(offset, Endian.big);
  if (u16(2) != 42) return null;
  final ifdOffset = u32(4);
  if (ifdOffset + 2 > head.length) return null;
  final count = u16(ifdOffset);
  int? width;
  int? height;
  for (var i = 0; i < count; i++) {
    final entry = ifdOffset + 2 + i * 12;
    if (entry + 12 > head.length) break;
    final tag = u16(entry);
    if (tag != 256 && tag != 257) continue;
    final type = u16(entry + 2);
    final valueCount = u32(entry + 4);
    if (valueCount != 1) continue;
    int value;
    if (type == 3) {
      // SHORT: the value sits in the first 2 bytes of the field.
      value = u16(entry + 8);
    } else if (type == 4) {
      // LONG: the value fills the field.
      value = u32(entry + 8);
    } else {
      continue;
    }
    if (tag == 256) width = value;
    if (tag == 257) height = value;
  }
  if (width == null || height == null) return null;
  return (width, height);
}
