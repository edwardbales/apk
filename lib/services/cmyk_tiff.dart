import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'black_converter.dart';

/// CMYK TIFF support — the shop rule since v1.15 is CMYK ONLY
/// (RGB files are rejected at pick time), and on the Human Y-Jet
/// (no K head) any K black in a CMYK file is rebuilt from the
/// three colour heads: C95 M95 Y95, K0.
///
/// Why a hand-written reader: the `image` package decodes CMYK
/// TIFFs to RGB — the K channel is lost, so a faithful K -> CMY
/// conversion is impossible through it. This reader returns the
/// raw CMYK bytes (chunky, 8-bit, 4 samples/pixel).
///
/// Supported: Photometric 5 (CMYK), chunky or planar storage,
/// 8 or 16 bits/sample (16-bit samples are scaled to 8-bit by
/// taking the high byte, so a Photoshop 16-bit export converts
/// exactly: K 65535 -> 255, K 32768 -> 128), compression none (1),
/// LZW (5), PackBits (32773). Big- and little-endian files both
/// work. JPEG-compressed TIFFs are still refused — re-export
/// uncompressed or LZW. Everything else throws a [FormatException]
/// with a plain message the designer can act on.
///
/// Since v1.16 there is NO file-size limit: the conversion
/// ([convertCmykTiffBlackFile]) streams the file through in
/// small chunks — input and output are never held whole in
/// memory — so even a 100+ MP banner file converts fine.
/// ([decodeCmykTiff] is the in-memory decoder used by tests;
/// it does hold the whole image, so it is not used on user
/// files.)

class CmykImage {
  const CmykImage({
    required this.width,
    required this.height,
    required this.cmyk,
  });

  final int width;
  final int height;

  /// width * height * 4 bytes, chunky C, M, Y, K per pixel.
  final Uint8List cmyk;
}

/// Chunk sizes for the streaming conversion: at most ~4 MB of
/// decoded pixels and ~1 MB of compressed data in memory at once,
/// whatever the file size.
const int _chunkPixels = 1024 * 1024; // 1M pixels = 4 MB CMYK
const int _readSliceBytes = 1024 * 1024; // 1 MB compressed reads
const int _headerBytes = 1024 * 1024; // 1 MB is plenty for a TIFF header

class _CmykTiffInfo {
  const _CmykTiffInfo({
    required this.width,
    required this.height,
    required this.bits,
    required this.planar,
    required this.littleEndian,
    required this.compression,
    required this.rowsPerStrip,
    required this.stripOffsets,
    required this.stripByteCounts,
  });

  final int width;
  final int height;
  final int bits; // 8 or 16, same for all 4 channels
  final int planar; // 1 = chunky, 2 = planar
  final bool littleEndian;
  final int compression; // 1 = none, 5 = LZW, 32773 = PackBits
  final int rowsPerStrip;
  final List<int> stripOffsets;
  final List<int> stripByteCounts;
}

/// Reads a TIFF header + IFD from [bytes] (the first bytes of the
/// file — the header region only, never the pixel data).
/// Only the tags this reader needs are read at all. Real files
/// carry many others (resolution RATIONALs, Software ASCII, the
/// Photoshop resources blob, a multi-MB ImageSourceData tag) —
/// reading those is both pointless and, for the huge ones,
/// a memory hazard. Unknown / unreadable types are skipped.
_CmykTiffInfo _readInfo(Uint8List bytes) {
  if (bytes.length < 8) {
    throw const FormatException('Not a TIFF file (too short).');
  }
  final littleEndian = bytes[0] == 0x49 && bytes[1] == 0x49;
  if (!littleEndian && !(bytes[0] == 0x4D && bytes[1] == 0x4D)) {
    throw const FormatException('Not a TIFF file (bad header).');
  }
  final data = ByteData.view(bytes.buffer, bytes.offsetInBytes);

  int u16(int offset) => littleEndian
      ? data.getUint16(offset, Endian.little)
      : data.getUint16(offset, Endian.big);
  int u32(int offset) => littleEndian
      ? data.getUint32(offset, Endian.little)
      : data.getUint32(offset, Endian.big);

  if (u16(2) != 42) {
    throw const FormatException('Not a TIFF file (bad magic).');
  }
  final ifdOffset = u32(4);
  if (ifdOffset + 2 > bytes.length) {
    throw const FormatException('TIFF file is truncated (no IFD).');
  }

  // TIFF field types: size in bytes per value.
  const typeSize = <int, int>{
    1: 1, // BYTE
    2: 1, // ASCII
    3: 2, // SHORT
    4: 4, // LONG
    5: 8, // RATIONAL
    6: 1, // SBYTE
    7: 1, // UNDEFINED
    8: 2, // SSHORT
    9: 4, // SLONG
    10: 8, // SRATIONAL
    11: 4, // FLOAT
    12: 8, // DOUBLE
  };

  int readValue(int entry, int index) {
    final type = u16(entry + 2);
    final count = u32(entry + 4);
    final valueOffset = entry + 8;
    final size = typeSize[type] ?? 0;
    if (size == 0 || index >= count) {
      throw const FormatException('TIFF tag is unreadable.');
    }
    // Values that fit in 4 bytes live inline in the entry;
    // longer ones live at the offset the entry points to.
    var offset = valueOffset;
    if (count * size > 4) {
      offset = u32(valueOffset);
    }
    offset += index * size;
    if (offset + size > bytes.length) {
      throw const FormatException('TIFF file is truncated (tag data).');
    }
    switch (type) {
      case 1:
      case 7:
        return bytes[offset];
      case 3:
        return u16(offset);
      case 4:
        return u32(offset);
      case 6:
        return data.getInt8(offset);
      case 8:
        return littleEndian
            ? data.getInt16(offset, Endian.little)
            : data.getInt16(offset, Endian.big);
      case 9:
        return littleEndian
            ? data.getInt32(offset, Endian.little)
            : data.getInt32(offset, Endian.big);
      default:
        throw const FormatException('TIFF tag has an unsupported type.');
    }
  }

  const wanted = {256, 257, 258, 259, 262, 273, 277, 278, 279, 284};
  final tags = <int, int>{};
  final arrays = <int, List<int>>{};
  final entries = u16(ifdOffset);
  for (var e = 0; e < entries; e++) {
    final entry = ifdOffset + 2 + e * 12;
    if (entry + 12 > bytes.length) break;
    final tag = u16(entry);
    if (!wanted.contains(tag)) continue;
    final type = u16(entry + 2);
    if (type != 1 && type != 3 && type != 4 && type != 6 && type != 7 &&
        type != 8 && type != 9) {
      continue;
    }
    final count = u32(entry + 4);
    tags[tag] = readValue(entry, 0);
    if (count > 1) {
      arrays[tag] = [for (var i = 0; i < count; i++) readValue(entry, i)];
    }
  }

  List<int> tagList(int tag) =>
      arrays[tag] ?? (tags.containsKey(tag) ? [tags[tag]!] : const []);

  final width = tags[256] ?? 0;
  final height = tags[257] ?? 0;
  if (width <= 0 || height <= 0) {
    throw const FormatException('TIFF has no image size.');
  }
  if ((tags[262] ?? -1) != 5) {
    throw const FormatException(
        'This TIFF is not CMYK — only CMYK TIFF files can be sent.');
  }
  if ((tags[277] ?? 0) != 4) {
    throw const FormatException(
        'This TIFF does not have 4 colour channels (CMYK).');
  }
  final bits = tagList(258);
  if (bits.length != 4 ||
      bits.toSet().length != 1 ||
      (bits[0] != 8 && bits[0] != 16)) {
    throw const FormatException(
        'Only 8-bit or 16-bit CMYK TIFF files are supported.');
  }
  final planar = tags[284] ?? 1;
  if (planar != 1 && planar != 2) {
    throw const FormatException(
        'This TIFF uses an unknown colour storage layout.');
  }
  final compression = tags[259] ?? 1;
  if (compression != 1 && compression != 5 && compression != 32773) {
    throw const FormatException(
        'This TIFF uses a compression the app cannot open (JPEG-compressed TIFF?) — re-export it uncompressed or LZW and send again.');
  }

  final offsets = tagList(273);
  final byteCounts = tagList(279);
  if (offsets.isEmpty ||
      offsets.length != byteCounts.length ||
      byteCounts.any((c) => c <= 0)) {
    throw const FormatException('TIFF has no image strips.');
  }
  final rowsPerStrip = tags[278] ?? height;
  return _CmykTiffInfo(
    width: width,
    height: height,
    bits: bits[0],
    planar: planar,
    littleEndian: littleEndian,
    compression: compression,
    rowsPerStrip: rowsPerStrip > 0 ? rowsPerStrip : height,
    stripOffsets: offsets,
    stripByteCounts: byteCounts,
  );
}

/// In-memory CMYK TIFF decoder (tests and small files only).
CmykImage decodeCmykTiff(Uint8List bytes) {
  final info = _readInfo(bytes);
  final expected = info.width * info.height * 4 * (info.bits ~/ 8);
  final out = BytesBuilder();
  for (var s = 0; s < info.stripOffsets.length; s++) {
    final start = info.stripOffsets[s];
    final end = start + info.stripByteCounts[s];
    if (start < 0 || end > bytes.length) {
      throw const FormatException('TIFF file is truncated (strip data).');
    }
    final raw = bytes.sublist(start, end);
    final decoded = switch (info.compression) {
      1 => raw,
      5 => _lzwDecode(raw, expected - out.length),
      32773 => _packBitsDecode(raw, expected - out.length),
      _ => throw const FormatException('Unsupported TIFF compression.'),
    };
    out.add(decoded);
    if (out.length >= expected) break;
  }
  final raw = out.toBytes();
  if (raw.length < expected) {
    throw const FormatException('TIFF file is truncated (pixel data).');
  }
  return CmykImage(
    width: info.width,
    height: info.height,
    cmyk: _toChunky8(
        raw, info.bits, info.planar, info.littleEndian, info.width, info.height),
  );
}

/// Turns decoded strip bytes into chunky 8-bit CMYK, whatever the
/// file stored: 8- or 16-bit samples (16-bit takes the high byte),
/// chunky (C,M,Y,K per pixel) or planar (one whole plane per
/// channel, planes in C,M,Y,K order — strips arrive plane-major).
Uint8List _toChunky8(
  Uint8List raw,
  int bits,
  int planar,
  bool littleEndian,
  int width,
  int height,
) {
  final pixels = width * height;
  final out = Uint8List(pixels * 4);
  int sample(int index) {
    if (bits == 8) return raw[index];
    final o = index * 2;
    final value = littleEndian
        ? raw[o] | (raw[o + 1] << 8)
        : (raw[o] << 8) | raw[o + 1];
    return value >> 8;
  }

  if (planar == 1) {
    for (var p = 0; p < pixels; p++) {
      for (var ch = 0; ch < 4; ch++) {
        out[p * 4 + ch] = sample(p * 4 + ch);
      }
    }
  } else {
    for (var ch = 0; ch < 4; ch++) {
      for (var p = 0; p < pixels; p++) {
        out[p * 4 + ch] = sample(ch * pixels + p);
      }
    }
  }
  return out;
}

/// A decoder that takes compressed bytes in slices and hands back
/// decoded chunks. [add] returns whole chunks; [finish] returns
/// the tail. Chunks are always a multiple of [alignment] bytes
/// long, so a pixel is never split across two chunks.
abstract class _StreamingDecoder {
  List<Uint8List> add(Uint8List data);
  Uint8List finish();
}

/// TIFF LZW (variable-width codes, MSB-first, "early change":
/// the code width grows as soon as the next table entry would
/// no longer fit in the current width).
Uint8List _lzwDecode(Uint8List input, int expectedLength) {
  final decoder = _StreamingLzwDecoder(expectedLength);
  final out = BytesBuilder();
  for (final c in decoder.add(input)) {
    out.add(c);
  }
  out.add(decoder.finish());
  return out.toBytes();
}

class _StreamingLzwDecoder implements _StreamingDecoder {
  _StreamingLzwDecoder(this._expectedLength, [this._alignment = 1]);

  final int _expectedLength;
  final int _alignment;

  /// Compressed bytes not yet consumed, and the bit position
  /// within them.
  final List<int> _buffer = <int>[];
  var _bitPos = 0;

  late var _table = _freshTable();
  var _nextCode = 258;
  var _width = 9;
  List<int>? _prev;
  var _done = false;
  final _out = <int>[];

  static List<List<int>> _freshTable() => <List<int>>[
        for (var i = 0; i < 256; i++) [i],
        const <int>[], // 256 ClearCode
        const <int>[], // 257 EOI
      ];

  int _readCode() {
    var code = 0;
    for (var i = 0; i < _width; i++) {
      final byteIndex = _bitPos >> 3;
      final bit = (_buffer[byteIndex] >> (7 - (_bitPos & 7))) & 1;
      code = (code << 1) | bit;
      _bitPos++;
    }
    return code;
  }

  @override
  List<Uint8List> add(Uint8List data) {
    _buffer.addAll(data);
    return _drain();
  }

  List<Uint8List> _drain() {
    final chunks = <Uint8List>[];
    while (!_done && _out.length < _expectedLength) {
      // Stop when the next code cannot be read whole yet —
      // more compressed data is coming.
      if (_bitPos + _width > _buffer.length * 8) break;
      final code = _readCode();
      if (code == 256) {
        _table = _freshTable();
        _nextCode = 258;
        _width = 9;
        _prev = null;
        continue;
      }
      if (code == 257) {
        _done = true;
        break;
      }
      List<int> entry;
      if (code < _table.length) {
        entry = _table[code];
      } else if (code == _nextCode && _prev != null) {
        entry = [..._prev!, _prev![0]];
      } else {
        throw const FormatException('TIFF LZW data is corrupt.');
      }
      _out.addAll(entry);
      if (_prev != null && _nextCode < 4096) {
        _table.add([..._prev!, entry[0]]);
        _nextCode++;
        if (_nextCode == (1 << _width) - 1 && _width < 12) _width++;
      }
      _prev = entry;
      if (_out.length >= _chunkPixels * 4) {
        final flushLen = (_out.length ~/ _alignment) * _alignment;
        if (flushLen > 0) {
          chunks.add(Uint8List.fromList(_out.sublist(0, flushLen)));
          _out.removeRange(0, flushLen);
        }
      }
    }
    // Drop compressed bytes whose bits are all consumed.
    final consumedBytes = _bitPos >> 3;
    if (consumedBytes > 0) {
      _buffer.removeRange(0, consumedBytes);
      _bitPos &= 7;
    }
    return chunks;
  }

  @override
  Uint8List finish() {
    _drain();
    final tail = Uint8List.fromList(_out);
    _out.clear();
    return tail;
  }
}

/// TIFF PackBits (byte run-length encoding).
Uint8List _packBitsDecode(Uint8List input, int expectedLength) {
  final decoder = _StreamingPackBitsDecoder(expectedLength);
  final out = BytesBuilder();
  for (final c in decoder.add(input)) {
    out.add(c);
  }
  out.add(decoder.finish());
  return out.toBytes();
}

class _StreamingPackBitsDecoder implements _StreamingDecoder {
  _StreamingPackBitsDecoder(this._expectedLength, [this._alignment = 1]);

  final int _expectedLength;
  final int _alignment;

  /// Input bytes not yet consumed (an incomplete run at the end
  /// of a slice stays here until the next slice arrives).
  final List<int> _pending = <int>[];
  final _out = <int>[];

  @override
  List<Uint8List> add(Uint8List data) {
    _pending.addAll(data);
    return _drain();
  }

  List<Uint8List> _drain() {
    final chunks = <Uint8List>[];
    var i = 0;
    while (i < _pending.length && _out.length < _expectedLength) {
      final n = _pending[i].toSigned(8);
      if (n >= 0) {
        final count = n + 1;
        if (i + 1 + count > _pending.length) break; // incomplete run
        _out.addAll(_pending.sublist(i + 1, i + 1 + count));
        i += 1 + count;
      } else if (n != -128) {
        if (i + 1 >= _pending.length) break; // repeat byte not here yet
        _out.addAll(List.filled(1 - n, _pending[i + 1]));
        i += 2;
      } else {
        i++; // n == -128: no-op
      }
      if (_out.length >= _chunkPixels * 4) {
        final flushLen = (_out.length ~/ _alignment) * _alignment;
        if (flushLen > 0) {
          chunks.add(Uint8List.fromList(_out.sublist(0, flushLen)));
          _out.removeRange(0, flushLen);
        }
      }
    }
    if (i > 0) _pending.removeRange(0, i);
    return chunks;
  }

  @override
  Uint8List finish() {
    _drain();
    final tail = Uint8List.fromList(_out);
    _out.clear();
    return tail;
  }
}

/// Rebuilds K black from the three colour heads, the way the
/// Human Y-Jet needs it (no K head): the K amount is added to
/// C, M and Y, capped at 255, and K becomes 0.
///
/// Pure K black (0,0,0,255) -> (242,242,242,0) = C95 M95 Y95.
/// A 50% K grey (0,0,0,128) -> (121,121,121,0).
/// White and K-free colours are untouched.
List<int> cmykBlackToCmy(int c, int m, int y, int k) {
  if (k == 0) return <int>[c, m, y, 0];
  final add = (k * kCmyBlackValue) ~/ 255;
  int plus(int v) => v + add > 255 ? 255 : v + add;
  return <int>[plus(c), plus(m), plus(y), 0];
}

/// K -> CMY in place on a chunk of chunky 8-bit CMYK bytes.
/// The chunk length must be a multiple of 4 (whole pixels).
void _fixChunk(Uint8List cmyk) {
  for (var o = 0; o + 3 < cmyk.length; o += 4) {
    final k = cmyk[o + 3];
    if (k == 0) continue;
    final add = (k * kCmyBlackValue) ~/ 255;
    var c = cmyk[o] + add;
    if (c > 255) c = 255;
    var m = cmyk[o + 1] + add;
    if (m > 255) m = 255;
    var y = cmyk[o + 2] + add;
    if (y > 255) y = 255;
    cmyk[o] = c;
    cmyk[o + 1] = m;
    cmyk[o + 2] = y;
    cmyk[o + 3] = 0;
  }
}

/// 16-bit samples -> 8-bit by taking the high byte of each
/// sample. [raw] must have an even length.
Uint8List _to8BitChunk(Uint8List raw, bool littleEndian) {
  if (raw.length % 2 != 0) {
    throw const FormatException('TIFF 16-bit data is corrupt.');
  }
  final out = Uint8List(raw.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = littleEndian ? raw[i * 2 + 1] : raw[i * 2];
  }
  return out;
}

Future<Uint8List> _readRange(File file, int start, int end) async {
  final out = <int>[];
  await for (final chunk in file.openRead(start, end)) {
    out.addAll(chunk);
  }
  return Uint8List.fromList(out);
}

/// Streams strips [firstStrip, lastStrip) through the right
/// decoder, calling [onChunk] with raw decoded bytes. Every
/// chunk handed to [onChunk] is a multiple of [alignment]
/// bytes long, so a pixel/sample is never split across chunks.
/// [expectedBytes] is the total raw decoded size of those strips.
Future<void> _streamStrips({
  required File input,
  required _CmykTiffInfo info,
  required int firstStrip,
  required int lastStrip,
  required int alignment,
  required int expectedBytes,
  required void Function(Uint8List chunk) onChunk,
}) async {
  final length = await input.length();
  var produced = 0;
  for (var s = firstStrip; s < lastStrip; s++) {
    final stripStart = info.stripOffsets[s];
    final stripEnd = stripStart + info.stripByteCounts[s];
    if (stripStart < 0 || stripEnd > length) {
      throw const FormatException('TIFF file is truncated (strip data).');
    }
    if (info.compression == 1) {
      var pos = stripStart;
      while (pos < stripEnd) {
        final take = math.min(_readSliceBytes, stripEnd - pos);
        final slice = await _readRange(input, pos, pos + take);
        if (slice.length % alignment != 0) {
          throw const FormatException('TIFF data is corrupt.');
        }
        onChunk(slice);
        produced += slice.length;
        pos += take;
      }
    } else {
      final _StreamingDecoder decoder = info.compression == 5
          ? _StreamingLzwDecoder(expectedBytes - produced, alignment)
          : _StreamingPackBitsDecoder(expectedBytes - produced, alignment);
      var pos = stripStart;
      while (pos < stripEnd) {
        final take = math.min(_readSliceBytes, stripEnd - pos);
        final slice = await _readRange(input, pos, pos + take);
        for (final chunk in decoder.add(slice)) {
          if (chunk.length % alignment != 0) {
            throw const FormatException('TIFF LZW data is corrupt.');
          }
          onChunk(chunk);
          produced += chunk.length;
        }
        pos += take;
      }
      final tail = decoder.finish();
      if (tail.length % alignment != 0) {
        throw const FormatException('TIFF data is corrupt.');
      }
      onChunk(tail);
      produced += tail.length;
    }
    if (produced >= expectedBytes) break;
  }
  if (produced != expectedBytes) {
    throw const FormatException('TIFF file is truncated (pixel data).');
  }
}

/// Reads a CMYK TIFF, rebuilds every K black as 3-colour black,
/// and writes the result as an uncompressed CMYK TIFF to [output].
///
/// Streaming: the input is read in ~1 MB slices and the output
/// is written as it is converted, so memory stays bounded
/// (~5 MB) no matter how large the file is. There is no size
/// limit — a 100+ MP banner converts the same way as a small one.
/// 8- and 16-bit, chunky and planar files all convert; planar
/// files go through temporary per-plane files on disk (still
/// bounded memory) before being merged.
Future<void> convertCmykTiffBlackFile({
  required File input,
  required File output,
}) async {
  final length = await input.length();
  final header = await _readRange(input, 0, math.min(length, _headerBytes));
  final info = _readInfo(header);
  final pixels = info.width * info.height;
  final headerBytes = cmykTiffHeader(info.width, info.height);

  final sink = output.openWrite();
  try {
    sink.add(headerBytes);
    if (info.planar == 1) {
      await _convertChunky(input: input, info: info, sink: sink);
    } else {
      await _convertPlanar(input: input, info: info, sink: sink);
    }
  } finally {
    await sink.close();
  }
  if (await output.length() != headerBytes.length + pixels * 4) {
    throw const FormatException('TIFF file is truncated (pixel data).');
  }
}

Future<void> _convertChunky({
  required File input,
  required _CmykTiffInfo info,
  required IOSink sink,
}) async {
  final pixels = info.width * info.height;
  final bytesPerSample = info.bits ~/ 8;
  var written = 0;
  await _streamStrips(
    input: input,
    info: info,
    firstStrip: 0,
    lastStrip: info.stripOffsets.length,
    alignment: 4 * bytesPerSample,
    expectedBytes: pixels * 4 * bytesPerSample,
    onChunk: (chunk) {
      final eight = bytesPerSample == 2
          ? _to8BitChunk(chunk, info.littleEndian)
          : chunk;
      _fixChunk(eight);
      sink.add(eight);
      written += eight.length;
    },
  );
  if (written != pixels * 4) {
    throw const FormatException('TIFF file is truncated (pixel data).');
  }
}

Future<void> _convertPlanar({
  required File input,
  required _CmykTiffInfo info,
  required IOSink sink,
}) async {
  final pixels = info.width * info.height;
  final bytesPerSample = info.bits ~/ 8;
  final stripsPerPlane =
      (info.height + info.rowsPerStrip - 1) ~/ info.rowsPerStrip;
  if (stripsPerPlane * 4 != info.stripOffsets.length) {
    throw const FormatException('TIFF planar strips are inconsistent.');
  }
  final tmpDir = await Directory.systemTemp.createTemp('signtech_planes_');
  try {
    final planeFiles = <File>[];
    for (var p = 0; p < 4; p++) {
      final planeFile = File('${tmpDir.path}/plane$p.bin');
      var produced = 0;
      final planeSink = planeFile.openWrite();
      try {
        await _streamStrips(
          input: input,
          info: info,
          firstStrip: p * stripsPerPlane,
          lastStrip: (p + 1) * stripsPerPlane,
          alignment: bytesPerSample,
          expectedBytes: pixels * bytesPerSample,
          onChunk: (chunk) {
            final eight = bytesPerSample == 2
                ? _to8BitChunk(chunk, info.littleEndian)
                : chunk;
            planeSink.add(eight);
            produced += eight.length;
          },
        );
      } finally {
        await planeSink.close();
      }
      if (produced != pixels) {
        throw const FormatException('TIFF file is truncated (pixel data).');
      }
      planeFiles.add(planeFile);
    }
    // Merge: interleave the 4 planes into chunky CMYK, fixing black.
    for (var start = 0; start < pixels; start += _chunkPixels) {
      final count = math.min(_chunkPixels, pixels - start);
      final planes = <Uint8List>[
        for (final f in planeFiles)
          await _readRange(f, start, start + count),
      ];
      final chunky = Uint8List(count * 4);
      for (var i = 0; i < count; i++) {
        chunky[i * 4] = planes[0][i];
        chunky[i * 4 + 1] = planes[1][i];
        chunky[i * 4 + 2] = planes[2][i];
        chunky[i * 4 + 3] = planes[3][i];
      }
      _fixChunk(chunky);
      sink.add(chunky);
    }
  } finally {
    await tmpDir.delete(recursive: true);
  }
}
