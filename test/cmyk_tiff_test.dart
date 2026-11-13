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
    // 50% K grey -> half-strength CMY grey (exactly 50% now).
    expect(cmykBlackToCmy(0, 0, 0, 128), <int>[128, 128, 128, 0]);
    // Dark colour with K: K is folded in per channel, capped at 242.
    expect(cmykBlackToCmy(200, 100, 0, 100), <int>[222, 161, 100, 0]);
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
      128, 128, 128, 0, // 50% K -> half CMY
      222, 161, 100, 0, // dark colour, K folded into CMY
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
      128, 128, 128, 0, // 50% K -> half CMY
      222, 161, 100, 0, // dark colour, K folded into CMY
      0, 0, 0, 0, // white untouched
    ]);
  });

  test('photo pixels keep their brightness (v1.22)', () async {
    // What the eye sees is the light NOT absorbed by the ink:
    // per channel that is (255 - v) * (255 - k) / 255 before the
    // fix and (255 - out) after it. They must match within
    // rounding (1.5 steps) — the old formula failed this badly:
    // a dark red (200,100,0,100) lost its whole red channel
    // (255,194,94,0), so a person's photo came out darker.
    // Pixels whose exact result would pass the 242 cap (pure
    // black) are covered by the first test instead.
    const photo = <List<int>>[
      <int>[20, 60, 70, 40], // light skin
      <int>[60, 90, 100, 120], // dark skin / shadow
      <int>[200, 100, 0, 100], // dark red
      <int>[180, 150, 60, 180], // deep shadow blue
      <int>[10, 40, 90, 200], // dark warm brown
    ];
    for (final px in photo) {
      final out = cmykBlackToCmy(px[0], px[1], px[2], px[3]);
      expect(out[3], 0);
      for (var i = 0; i < 3; i++) {
        final before = (255 - px[i]) * (255 - px[3]) / 255;
        final after = (255 - out[i]).toDouble();
        expect((after - before).abs(), lessThanOrEqualTo(1.5),
            reason: 'pixel $px channel $i');
      }
    }
    // The single-pixel function and the streaming chunk fixer
    // must agree pixel for pixel.
    final chunk = Uint8List.fromList([
      20, 60, 70, 40,
      200, 100, 0, 100,
      0, 0, 0, 255,
      100, 150, 200, 0,
    ]);
    final converted = await _convertBytes(
        encodeCmykTiff(4, 1, Uint8List.fromList(chunk)));
    final decoded = decodeCmykTiff(converted);
    for (var p = 0; p < 4; p++) {
      final want = cmykBlackToCmy(
          chunk[p * 4], chunk[p * 4 + 1], chunk[p * 4 + 2], chunk[p * 4 + 3]);
      expect(decoded.cmyk.sublist(p * 4, p * 4 + 4), want,
          reason: 'pixel $p');
    }
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
