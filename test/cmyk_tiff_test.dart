import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/services/black_converter.dart';
import 'package:signtech_file_sharing/services/cmyk_tiff.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

/// Converts in-memory TIFF bytes through the streaming file API
/// (the production path) and returns the output bytes.
Future<Uint8List> _convertBytes(Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('cmyk_test_');
  try {
    final input = File('${dir.path}/in.tif')..writeAsBytesSync(bytes);
    final output = File('${dir.path}/out.tif');
    await convertCmykTiffBlackFile(input: input, output: output);
    return output.readAsBytesSync();
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  test('K black becomes C95 M95 Y95, other pixels untouched', () {
    // Pure K black -> the Y-Jet 3-colour black.
    expect(cmykBlackToCmy(0, 0, 0, 255), <int>[242, 242, 242, 0]);
    // 50% K grey -> half-strength CMY grey.
    expect(cmykBlackToCmy(0, 0, 0, 128), <int>[121, 121, 121, 0]);
    // Dark colour with K: K is added to C/M/Y, capped at 255.
    expect(cmykBlackToCmy(200, 100, 0, 100), <int>[255, 194, 94, 0]);
    // White and K-free colours are untouched.
    expect(cmykBlackToCmy(0, 0, 0, 0), <int>[0, 0, 0, 0]);
    expect(cmykBlackToCmy(100, 150, 200, 0), <int>[100, 150, 200, 0]);
  });

  test('round trip: our own encoder output decodes back exactly', () {
    final cmyk = Uint8List.fromList([
      0, 0, 0, 255, // pure K black
      0, 0, 0, 128, // 50% K
      200, 100, 0, 100, // dark colour with K
      0, 0, 0, 0, // white
    ]);
    final tiff = encodeCmykTiff(2, 2, cmyk);
    final decoded = decodeCmykTiff(tiff);
    expect(decoded.width, 2);
    expect(decoded.height, 2);
    expect(decoded.cmyk, cmyk);
  });

  test('decodes real CMYK TIFFs: none, LZW and PackBits', () {
    const expected = <int>[
      0, 0, 0, 255,
      0, 0, 0, 128,
      200, 100, 0, 100,
      0, 0, 0, 0,
    ];
    for (final name in [
      'cmyk_2x2_none.tif',
      'cmyk_2x2_lzw.tif',
      'cmyk_2x2_packbits.tif',
    ]) {
      final decoded = decodeCmykTiff(_fixture(name));
      expect(decoded.width, 2, reason: name);
      expect(decoded.height, 2, reason: name);
      expect(decoded.cmyk, expected, reason: name);
    }
  });

  test('LZW decoder survives a 64x64 random image (code growth)', () {
    final plain = decodeCmykTiff(_fixture('cmyk_64x64_none.tif'));
    final lzw = decodeCmykTiff(_fixture('cmyk_64x64_lzw.tif'));
    expect(lzw.width, 64);
    expect(lzw.height, 64);
    expect(lzw.cmyk, plain.cmyk);
  });

  test('full conversion: K black becomes 3-colour black in the TIFF',
      () async {
    final converted =
        await _convertBytes(_fixture('cmyk_2x2_lzw.tif'));
    final decoded = decodeCmykTiff(converted);
    expect(decoded.cmyk, <int>[
      242, 242, 242, 0, // pure K black -> C95 M95 Y95
      121, 121, 121, 0, // 50% K -> half CMY
      255, 194, 94, 0, // dark colour, K folded into CMY
      0, 0, 0, 0, // white untouched
    ]);
  });

  test('decodes 16-bit (big-endian) and planar CMYK TIFFs', () {
    const expected = <int>[
      0, 0, 0, 255,
      0, 0, 0, 128,
      200, 100, 0, 100,
      0, 0, 0, 0,
    ];
    for (final name in [
      'cmyk_2x2_16bit_be.tif',
      'cmyk_2x2_planar.tif',
      'cmyk_2x2_16bit_planar.tif',
    ]) {
      final decoded = decodeCmykTiff(_fixture(name));
      expect(decoded.width, 2, reason: name);
      expect(decoded.height, 2, reason: name);
      expect(decoded.cmyk, expected, reason: name);
    }
  });

  test('full conversion works on a 16-bit TIFF (output is 8-bit)',
      () async {
    final converted =
        await _convertBytes(_fixture('cmyk_2x2_16bit_be.tif'));
    final decoded = decodeCmykTiff(converted);
    expect(decoded.cmyk, <int>[
      242, 242, 242, 0, // pure K black -> C95 M95 Y95
      121, 121, 121, 0, // 50% K -> half CMY
      255, 194, 94, 0, // dark colour, K folded into CMY
      0, 0, 0, 0, // white untouched
    ]);
  });

  test('an RGB TIFF is refused, not converted', () {
    expect(() => decodeCmykTiff(_fixture('rgb_2x2.tif')),
        throwsA(isA<FormatException>()));
  });

  test('a truncated file is refused', () {
    final bytes = _fixture('cmyk_2x2_none.tif').sublist(0, 20);
    expect(() => decodeCmykTiff(bytes), throwsA(isA<FormatException>()));
  });
}
