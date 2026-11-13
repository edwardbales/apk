import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/services/black_converter.dart';
import 'package:signtech_file_sharing/services/cmyk_tiff.dart';

/// No size limit (v1.16): a 52 MP file — over the old 50 MP cap —
/// converts through the streaming file API. The input is generated
/// here by streaming too, so the test itself never holds the whole
/// image in memory either.
///
/// Pixel pattern (repeats every chunk = 4 MB = 1,048,576 pixels):
///   c = (i * 7) & 0xFF, m = (i * 13) & 0xFF,
///   y = (i * 29) & 0xFF, k = i % 5 == 0 ? 255 : (i * 3) & 0xFF.
List<int> _patternPixel(int i) => <int>[
      (i * 7) & 0xFF,
      (i * 13) & 0xFF,
      (i * 29) & 0xFF,
      i % 5 == 0 ? 255 : (i * 3) & 0xFF,
    ];

List<int> _fixedPixel(List<int> p) {
  final add = (p[3] * 242) ~/ 255;
  int plus(int v) => v + add > 255 ? 255 : v + add;
  return <int>[plus(p[0]), plus(p[1]), plus(p[2]), 0];
}

Future<Uint8List> _readAt(File file, int offset, int count) async {
  final out = <int>[];
  await for (final chunk in file.openRead(offset, offset + count)) {
    out.addAll(chunk);
  }
  return Uint8List.fromList(out);
}

void main() {
  test('52 MP CMYK TIFF converts with no size limit', () async {
    const width = 8000;
    const height = 6500; // 52,000,000 pixels — over the old 50 MP cap
    const pixels = width * height;
    const total = pixels * 4;
    final dir = await Directory.systemTemp.createTemp('large_cmyk_');
    try {
      final input = File('${dir.path}/large.tif');
      final sink = input.openWrite();
      sink.add(cmykTiffHeader(width, height));
      final chunk = Uint8List(4 * 1024 * 1024);
      for (var p = 0; p < chunk.length; p += 4) {
        final v = _patternPixel(p ~/ 4);
        chunk[p] = v[0];
        chunk[p + 1] = v[1];
        chunk[p + 2] = v[2];
        chunk[p + 3] = v[3];
      }
      var written = 0;
      while (written < total) {
        final take = math.min(chunk.length, total - written);
        sink.add(take == chunk.length ? chunk : chunk.sublist(0, take));
        written += take;
      }
      await sink.close();
      expect(await input.length(),
          cmykTiffHeader(width, height).length + total);

      final output = File('${dir.path}/large_fixed.tif');
      await convertCmykTiffBlackFile(input: input, output: output);
      expect(await output.length(),
          cmykTiffHeader(width, height).length + total);

      // Spot-check pixels straight from the output strip
      // (strip starts right after the 142-byte header).
      const stripOffset = 142;
      for (final p in [0, 1, 5, 256, 1000000, 1000001, pixels - 1]) {
        final i = p % 1048576; // pattern repeats every chunk
        final want = _fixedPixel(_patternPixel(i));
        // K-free pixels stay untouched: pixel 256 has k == 0.
        final got = await _readAt(output, stripOffset + p * 4, 4);
        expect(got, want, reason: 'pixel $p');
      }
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
