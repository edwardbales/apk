import 'dart:typed_data';

/// Human Y-Jet has NO black (K) head. Pure black printed as K-only
/// comes out weak / grey on that printer, so black must be built
/// from the three colour heads: C95 M95 Y95, K0.
///
/// 95% of 255 = 242 (rounded down — 242/255 = 94.9%).
const int kCmyBlackValue = 242;

/// The 142-byte header of an uncompressed chunky CMYK TIFF:
/// 8-byte header + IFD (10 entries) + 4x 8-bit BitsPerSample.
/// The pixel strip follows at offset 142.
Uint8List cmykTiffHeader(int width, int height) {
  const entryCount = 10;
  const ifdSize = 2 + entryCount * 12 + 4;
  const bitsOffset = 8 + ifdSize;
  const stripOffset = bitsOffset + 8;
  final out = Uint8List(stripOffset);
  final data = ByteData.view(out.buffer);
  // Header: "II", 42, IFD offset 8.
  out[0] = 0x49;
  out[1] = 0x49;
  data.setUint16(2, 42, Endian.little);
  data.setUint32(4, 8, Endian.little);
  data.setUint16(8, entryCount, Endian.little);

  void entry(int index, int tag, int type, int count, int value) {
    final offset = 10 + index * 12;
    data.setUint16(offset, tag, Endian.little);
    data.setUint16(offset + 2, type, Endian.little);
    data.setUint32(offset + 4, count, Endian.little);
    data.setUint32(offset + 8, value, Endian.little);
  }

  entry(0, 256, 4, 1, width); // ImageWidth, LONG
  entry(1, 257, 4, 1, height); // ImageLength, LONG
  entry(2, 258, 3, 4, bitsOffset); // BitsPerSample, SHORT x4 (offset)
  entry(3, 259, 3, 1, 1); // Compression = none
  entry(4, 262, 3, 1, 5); // Photometric = CMYK
  entry(5, 273, 4, 1, stripOffset); // StripOffsets
  entry(6, 277, 3, 1, 4); // SamplesPerPixel
  entry(7, 278, 4, 1, height); // RowsPerStrip
  entry(8, 279, 4, 1, width * height * 4); // StripByteCounts
  entry(9, 284, 3, 1, 1); // PlanarConfiguration = chunky
  data.setUint32(10 + entryCount * 12, 0, Endian.little); // next IFD = 0
  for (var i = 0; i < 4; i++) {
    data.setUint16(bitsOffset + i * 2, 8, Endian.little);
  }
  return out;
}

Uint8List encodeCmykTiff(int width, int height, Uint8List cmyk) {
  assert(cmyk.length == width * height * 4);
  final header = cmykTiffHeader(width, height);
  final out = Uint8List(header.length + cmyk.length);
  out.setRange(0, header.length, header);
  out.setRange(header.length, out.length, cmyk);
  return out;
}
