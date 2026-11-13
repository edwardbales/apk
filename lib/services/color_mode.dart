import 'dart:typed_data';

/// Colour mode of a print file, detected from its header bytes only
/// (the whole file is never decoded just to check this).
///
/// Why it matters: the shop prints from RIP in CMYK, and since
/// v1.15 RGB files are REJECTED at pick time (only CMYK is sent).
/// Detection still happens from the header bytes only — the whole
/// file is never decoded just to check this.
enum FileColorMode {
  rgb,
  cmyk,
  grayscale,
  unknown;

  String get label {
    switch (this) {
      case FileColorMode.rgb:
        return 'RGB';
      case FileColorMode.cmyk:
        return 'CMYK';
      case FileColorMode.grayscale:
        return 'Grayscale';
      case FileColorMode.unknown:
        return 'Unknown';
    }
  }
}

FileColorMode detectColorMode(Uint8List bytes, String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  switch (ext) {
    case 'png':
      return _png(bytes);
    case 'jpg':
    case 'jpeg':
      return _jpeg(bytes);
    case 'tif':
    case 'tiff':
      return _tiff(bytes);
    case 'pdf':
      return _pdf(bytes);
    case 'eps':
      // EPS is PostScript text — its colour space cannot be read
      // reliably from a header, so it is always Unknown.
      return FileColorMode.unknown;
    default:
      return FileColorMode.unknown;
  }
}

FileColorMode _png(Uint8List bytes) {
  // PNG signature (8) + IHDR chunk: length(4) type(4) width(4)
  // height(4) bitDepth(1) colourType(1) — colour type at offset 25.
  if (bytes.length < 26) return FileColorMode.unknown;
  if (bytes[0] != 0x89 || bytes[1] != 0x50) return FileColorMode.unknown;
  switch (bytes[25]) {
    case 2:
    case 6:
    case 3:
      return FileColorMode.rgb;
    case 0:
    case 4:
      return FileColorMode.grayscale;
    default:
      return FileColorMode.unknown;
  }
}

FileColorMode _jpeg(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return FileColorMode.unknown;
  }
  var i = 2;
  var components = 0;
  var adobeTransform = -1;
  while (i + 4 <= bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = bytes[i + 1];
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (i + 4 > bytes.length) break;
    final length = (bytes[i + 2] << 8) | bytes[i + 3];
    if (length < 2 || i + 2 + length > bytes.length) break;
    if (marker == 0xEE && length >= 14) {
      // APP14 "Adobe": transform byte is at segment offset 12.
      final seg = i + 4;
      if (bytes[seg] == 0x41 && // 'A'
          bytes[seg + 1] == 0x64 && // 'd'
          bytes[seg + 2] == 0x6F && // 'o'
          bytes[seg + 3] == 0x62 && // 'b'
          bytes[seg + 4] == 0x65) {
        adobeTransform = bytes[seg + 12];
      }
    }
    if ((marker == 0xC0 || marker == 0xC1 || marker == 0xC2) && length >= 7) {
      components = bytes[i + 4 + 5];
    }
    if (marker == 0xDA) break; // Start of scan — image data follows.
    i += 2 + length;
  }
  if (adobeTransform == 2) return FileColorMode.cmyk;
  if (components == 4) return FileColorMode.cmyk;
  if (components == 3) return FileColorMode.rgb;
  if (components == 1) return FileColorMode.grayscale;
  // Plain JFIF JPEG with no SOF seen: it is YCbCr — RGB-equivalent.
  return FileColorMode.rgb;
}

FileColorMode _tiff(Uint8List bytes) {
  if (bytes.length < 8) return FileColorMode.unknown;
  final littleEndian = bytes[0] == 0x49 && bytes[1] == 0x49;
  if (!littleEndian && !(bytes[0] == 0x4D && bytes[1] == 0x4D)) {
    return FileColorMode.unknown;
  }
  int u16(int offset) {
    if (littleEndian) {
      return bytes[offset] | (bytes[offset + 1] << 8);
    }
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  int u32(int offset) {
    if (littleEndian) {
      return bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
    }
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  if (u16(2) != 42) return FileColorMode.unknown;
  final ifdOffset = u32(4);
  if (ifdOffset + 2 > bytes.length) return FileColorMode.unknown;
  final entries = u16(ifdOffset);
  for (var e = 0; e < entries; e++) {
    final entry = ifdOffset + 2 + e * 12;
    if (entry + 12 > bytes.length) break;
    if (u16(entry) == 262) {
      // PhotometricInterpretation (SHORT): 2 = RGB, 5 = CMYK,
      // 0/1 = bilevel/grayscale, 3 = palette.
      final value = u16(entry + 8);
      switch (value) {
        case 2:
          return FileColorMode.rgb;
        case 5:
          return FileColorMode.cmyk;
        case 0:
        case 1:
          return FileColorMode.grayscale;
        case 3:
          return FileColorMode.rgb;
      }
    }
  }
  return FileColorMode.unknown;
}

FileColorMode _pdf(Uint8List bytes) {
  // Crude but honest: scan the (usually plain-text) header area for
  // a Device colour space. Most RIP-ready PDFs name it explicitly.
  final head = bytes.length > 200000 ? bytes.sublist(0, 200000) : bytes;
  final text = String.fromCharCodes(head);
  final hasCmyk = text.contains('/DeviceCMYK') || text.contains('/DeviceN');
  final hasRgb =
      text.contains('/DeviceRGB') || text.contains('/CalRGB');
  if (hasCmyk && !hasRgb) return FileColorMode.cmyk;
  if (hasRgb) return FileColorMode.rgb;
  return FileColorMode.unknown;
}
