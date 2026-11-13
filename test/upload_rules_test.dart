import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/services/color_mode.dart';
import 'package:signtech_file_sharing/services/upload_rules.dart';

void main() {
  test('only CMYK TIFF (and EPS) is accepted', () {
    expect(
        decidePickedFile(
            fileName: 'banner.tif', mode: FileColorMode.cmyk),
        PickDecision.accept);
    expect(
        decidePickedFile(
            fileName: 'logo.eps', mode: FileColorMode.unknown),
        PickDecision.accept);
    // A CMYK TIFF whose mode could not be read is still accepted —
    // it cannot be proven RGB.
    expect(
        decidePickedFile(
            fileName: 'banner.tif', mode: FileColorMode.unknown),
        PickDecision.accept);
  });

  test('RGB and grayscale files are rejected', () {
    expect(
        decidePickedFile(fileName: 'photo.jpg', mode: FileColorMode.rgb),
        PickDecision.rejectRgb);
    expect(
        decidePickedFile(fileName: 'scan.tif', mode: FileColorMode.rgb),
        PickDecision.rejectRgb);
    expect(
        decidePickedFile(
            fileName: 'logo.tif', mode: FileColorMode.grayscale),
        PickDecision.rejectGrayscale);
  });

  test('a CMYK JPG is rejected — its K cannot be fixed', () {
    expect(
        decidePickedFile(fileName: 'art.jpg', mode: FileColorMode.cmyk),
        PickDecision.rejectCmykJpg);
    expect(
        decidePickedFile(fileName: 'art.jpeg', mode: FileColorMode.cmyk),
        PickDecision.rejectCmykJpg);
  });
}
