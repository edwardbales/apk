import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:signtech_file_sharing/services/color_mode.dart';

Uint8List pngWithColorType(int colorType) {
  // PNG signature + IHDR (colour type is byte 25).
  final bytes = Uint8List(30);
  bytes[0] = 0x89;
  bytes[1] = 0x50;
  bytes[2] = 0x4E;
  bytes[3] = 0x47;
  bytes[25] = colorType;
  return bytes;
}

void main() {
  test('PNG RGB / RGBA / grayscale from IHDR colour type', () {
    expect(detectColorMode(pngWithColorType(2), 'a.png'),
        FileColorMode.rgb);
    expect(detectColorMode(pngWithColorType(6), 'a.png'),
        FileColorMode.rgb);
    expect(detectColorMode(pngWithColorType(0), 'a.png'),
        FileColorMode.grayscale);
  });

  test('a real encoded JPG is RGB', () {
    final image = img.Image(width: 4, height: 4);
    final jpg = Uint8List.fromList(img.encodeJpg(image));
    expect(detectColorMode(jpg, 'a.jpg'), FileColorMode.rgb);
  });

  test('TIFF Photometric 5 is CMYK, 2 is RGB', () {
    Uint8List tiff(int photometric) {
      final bytes = Uint8List(30);
      bytes[0] = 0x49;
      bytes[1] = 0x49;
      bytes[2] = 42;
      bytes[4] = 8; // IFD offset
      // IFD at offset 8, 1 entry: tag 262, type SHORT, count 1.
      bytes[8] = 1;
      bytes[10] = 0x06;
      bytes[11] = 0x01;
      bytes[12] = 3;
      bytes[14] = 1;
      bytes[18] = photometric;
      return bytes;
    }

    expect(detectColorMode(tiff(5), 'a.tif'), FileColorMode.cmyk);
    expect(detectColorMode(tiff(2), 'a.tif'), FileColorMode.rgb);
  });

  test('PDF DeviceRGB / DeviceCMYK', () {
    final rgb = Uint8List.fromList(
        '%PDF-1.4 /DeviceRGB'.codeUnits);
    final cmyk = Uint8List.fromList(
        '%PDF-1.4 /DeviceCMYK'.codeUnits);
    expect(detectColorMode(rgb, 'a.pdf'), FileColorMode.rgb);
    expect(detectColorMode(cmyk, 'a.pdf'), FileColorMode.cmyk);
    expect(detectColorMode(Uint8List.fromList('hello'.codeUnits), 'a.xyz'),
        FileColorMode.unknown);
  });
}
