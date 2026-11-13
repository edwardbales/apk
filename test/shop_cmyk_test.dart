import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/services/color_mode.dart';
import 'package:signtech_file_sharing/services/cmyk_tiff.dart';

/// Regression test from a REAL shop file: 01-01_0_d0ui.tif
/// (1241x1754 CMYK, uncompressed, 150 DPI — sent by the user
/// 2026-11-13). This 128x128 crop is cut from it (offset 448,128)
/// so the test keeps the real-world pixels without the 13 MB file.
/// Reference pixel values were read with PIL.
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
  test('real shop crop: detected, decoded exactly, black fixed',
      () async {
    final bytes =
        File('test/fixtures/cmyk_shop_crop.tif').readAsBytesSync();
    expect(detectColorMode(bytes, 'cmyk_shop_crop.tif'),
        FileColorMode.cmyk);
    final decoded = decodeCmykTiff(bytes);
    expect(decoded.width, 128);
    expect(decoded.height, 128);
    const samples = <List<int>>[
    <int>[0, 0, 239, 147, 2, 0],
    <int>[13, 0, 238, 132, 1, 0],
    <int>[26, 0, 236, 121, 0, 0],
    <int>[39, 0, 238, 114, 0, 0],
    <int>[52, 0, 239, 112, 0, 0],
    <int>[65, 0, 241, 105, 0, 0],
    <int>[78, 0, 234, 81, 6, 1],
    <int>[91, 0, 232, 75, 5, 0],
    <int>[104, 0, 230, 71, 3, 0],
    <int>[117, 0, 229, 64, 2, 0],
    <int>[0, 17, 237, 134, 2, 0],
    <int>[13, 17, 236, 125, 0, 0],
    <int>[26, 17, 240, 113, 0, 0],
    <int>[39, 17, 238, 118, 0, 0],
    <int>[52, 17, 238, 118, 0, 0],
    <int>[65, 17, 243, 109, 0, 0],
    <int>[78, 17, 244, 103, 0, 0],
    <int>[91, 17, 246, 94, 0, 0],
    <int>[104, 17, 240, 89, 1, 0],
    <int>[117, 17, 234, 80, 3, 0],
    <int>[0, 34, 238, 143, 1, 0],
    <int>[13, 34, 238, 129, 0, 0],
    <int>[26, 34, 237, 131, 0, 0],
    <int>[39, 34, 237, 133, 1, 0],
    <int>[52, 34, 238, 140, 2, 0],
    <int>[65, 34, 238, 141, 1, 0],
    <int>[78, 34, 239, 141, 1, 0],
    <int>[91, 34, 238, 133, 1, 0],
    <int>[104, 34, 237, 117, 0, 0],
    <int>[117, 34, 241, 111, 0, 0],
    <int>[0, 51, 239, 141, 1, 0],
    <int>[13, 51, 240, 137, 0, 0],
    <int>[26, 51, 240, 143, 1, 0],
    <int>[39, 51, 240, 154, 1, 0],
    <int>[52, 51, 238, 151, 1, 0],
    <int>[65, 51, 239, 157, 1, 0],
    <int>[78, 51, 240, 157, 1, 0],
    <int>[91, 51, 242, 169, 2, 0],
    <int>[104, 51, 0, 0, 0, 255],
    <int>[117, 51, 0, 0, 0, 255],
    <int>[0, 68, 238, 120, 0, 0],
    <int>[13, 68, 233, 115, 0, 0],
    <int>[26, 68, 238, 143, 1, 0],
    <int>[39, 68, 238, 155, 1, 0],
    <int>[52, 68, 243, 175, 2, 0],
    <int>[65, 68, 249, 182, 2, 0],
    <int>[78, 68, 0, 0, 0, 255],
    <int>[91, 68, 0, 0, 0, 255],
    <int>[104, 68, 0, 0, 0, 255],
    <int>[117, 68, 0, 0, 0, 255],
    <int>[0, 85, 238, 151, 1, 0],
    <int>[13, 85, 243, 175, 2, 0],
    <int>[26, 85, 241, 170, 5, 0],
    <int>[39, 85, 247, 183, 6, 1],
    <int>[52, 85, 247, 183, 5, 0],
    <int>[65, 85, 0, 0, 0, 255],
    <int>[78, 85, 0, 0, 0, 255],
    <int>[91, 85, 10, 8, 7, 158],
    <int>[104, 85, 0, 0, 0, 0],
    <int>[117, 85, 13, 10, 10, 201],
    <int>[0, 102, 237, 161, 2, 0],
    <int>[13, 102, 243, 176, 3, 0],
    <int>[26, 102, 249, 190, 4, 1],
    <int>[39, 102, 250, 198, 3, 1],
    <int>[52, 102, 0, 0, 0, 255],
    <int>[65, 102, 0, 0, 0, 255],
    <int>[78, 102, 0, 0, 0, 0],
    <int>[91, 102, 0, 0, 0, 255],
    <int>[104, 102, 0, 0, 0, 255],
    <int>[117, 102, 0, 0, 0, 0],
    <int>[0, 119, 235, 159, 1, 0],
    <int>[13, 119, 239, 169, 2, 0],
    <int>[26, 119, 237, 171, 4, 0],
    <int>[39, 119, 167, 132, 10, 79],
    <int>[52, 119, 0, 0, 0, 255],
    <int>[65, 119, 11, 9, 8, 58],
    <int>[78, 119, 0, 0, 0, 0],
    <int>[91, 119, 0, 0, 0, 255],
    <int>[104, 119, 0, 0, 0, 255],
    <int>[117, 119, 0, 0, 0, 255],
    ];
    for (final s in samples) {
      final o = (s[1] * decoded.width + s[0]) * 4;
      expect(decoded.cmyk.sublist(o, o + 4), s.sublist(2),
          reason: 'pixel (${s[0]},${s[1]})');
    }
    final converted = await _convertBytes(bytes);
    final fixed = decodeCmykTiff(converted);
    var changed = 0;
    var pureBlackFixed = 0;
    for (var o = 0; o < decoded.cmyk.length; o += 4) {
      final k = decoded.cmyk[o + 3];
      if (k == 0) {
        expect(fixed.cmyk.sublist(o, o + 4),
            decoded.cmyk.sublist(o, o + 4));
        continue;
      }
      changed++;
      expect(fixed.cmyk[o + 3], 0);
      if (decoded.cmyk[o] == 0 &&
          decoded.cmyk[o + 1] == 0 &&
          decoded.cmyk[o + 2] == 0 &&
          k == 255) {
        pureBlackFixed++;
        expect(fixed.cmyk.sublist(o, o + 4), <int>[242, 242, 242, 0]);
      }
    }
    expect(changed, greaterThan(0));
    expect(pureBlackFixed, greaterThan(0));
  });
}
