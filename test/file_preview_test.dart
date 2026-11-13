import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:signtech_file_sharing/services/file_preview.dart';

/// Builds a minimal uncompressed TIFF header claiming the given
/// dimensions (no pixel data) — the dimension guard must reject
/// it before any decode is attempted.
Uint8List fakeTiffHeader({required int width, required int height}) {
  final bytes = Uint8List(8 + 2 + 24);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 0x49; // 'II' — little-endian
  bytes[1] = 0x49;
  data.setUint16(2, 42, Endian.little);
  data.setUint32(4, 8, Endian.little);
  data.setUint16(8, 2, Endian.little);
  // Entry 1: tag 256 (width), type LONG, count 1, value.
  data.setUint16(10, 256, Endian.little);
  data.setUint16(12, 4, Endian.little);
  data.setUint32(14, 1, Endian.little);
  data.setUint32(18, width, Endian.little);
  // Entry 2: tag 257 (height), type LONG, count 1, value.
  data.setUint16(22, 257, Endian.little);
  data.setUint16(24, 4, Endian.little);
  data.setUint32(26, 1, Endian.little);
  data.setUint32(30, height, Endian.little);
  return bytes;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('preview_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('real shop crop gets a small JPEG preview', () async {
    final src = File('test/fixtures/cmyk_shop_crop.tif');
    final file = File('${tmp.path}/crop.tif')
      ..writeAsBytesSync(src.readAsBytesSync());
    final preview =
        await designPreviewBase64(file: file, fileName: 'crop.tif');
    expect(preview, isNotNull);
    expect(preview!.length, lessThanOrEqualTo(kPreviewMaxBase64));
    final jpeg = img.decodeJpg(base64Url.decode(preview));
    expect(jpeg, isNotNull);
    expect(jpeg!.width, lessThanOrEqualTo(320));
  });

  test('EPS files get no preview', () async {
    final file = File('${tmp.path}/design.eps')
      ..writeAsStringSync('%!PS-Adobe-3.0 EPSF-3.0');
    expect(
        await designPreviewBase64(file: file, fileName: 'design.eps'),
        isNull);
  });

  test('a huge design is skipped before decoding', () async {
    final file = File('${tmp.path}/huge.tif')
      ..writeAsBytesSync(fakeTiffHeader(width: 20000, height: 20000));
    expect(
        await designPreviewBase64(file: file, fileName: 'huge.tif'),
        isNull);
  });

  test('a small fake header is skipped (no pixel data)', () async {
    // 100x100 claimed but no strips: the decode fails, so the
    // preview is null instead of crashing the pick flow.
    final file = File('${tmp.path}/empty.tif')
      ..writeAsBytesSync(fakeTiffHeader(width: 100, height: 100));
    expect(
        await designPreviewBase64(file: file, fileName: 'empty.tif'),
        isNull);
  });

  test('decodePreviewBase64 validates its input', () {
    expect(decodePreviewBase64(null), isNull);
    expect(decodePreviewBase64(''), isNull);
    expect(decodePreviewBase64('not-base64!'), isNull);
    expect(decodePreviewBase64(base64UrlEncode([1, 2, 3])), isNull);
  });
}
