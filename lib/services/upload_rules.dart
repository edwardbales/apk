import 'color_mode.dart';

/// What happens when the designer picks a file.
///
/// Shop rule since v1.15: CMYK ONLY. RGB files are rejected at
/// pick time, and so are grayscale files (not CMYK either) and
/// CMYK JPGs — a JPG's black (K) cannot be rebuilt as 3-colour
/// black, because JPEG decoding loses the K channel. CMYK TIFF
/// is the supported file; EPS passes through as before (its
/// colour space cannot be read, and it is vector, not pixels).
enum PickDecision {
  accept,
  rejectRgb,
  rejectGrayscale,
  rejectCmykJpg,
}

PickDecision decidePickedFile({
  required String fileName,
  required FileColorMode mode,
}) {
  if (mode == FileColorMode.rgb) return PickDecision.rejectRgb;
  if (mode == FileColorMode.grayscale) {
    return PickDecision.rejectGrayscale;
  }
  final ext = fileName.toLowerCase().split('.').last;
  if (mode == FileColorMode.cmyk && (ext == 'jpg' || ext == 'jpeg')) {
    return PickDecision.rejectCmykJpg;
  }
  return PickDecision.accept;
}
