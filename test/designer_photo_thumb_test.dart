import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:signtech_file_sharing/services/designer_photo_thumb.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('signtech_thumb');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> savePhoto(int width, int height) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(79, 91, 213));
    final dir = Directory(
        '${tmp.path}/Signtech File Sharing/Profile');
    await dir.create(recursive: true);
    await File('${dir.path}/photo.png')
        .writeAsBytes(img.encodePng(image));
  }

  test('photo becomes a 96x96 JPEG thumbnail', () async {
    await savePhoto(400, 300);
    final thumb = await designerPhotoThumbnailBase64(documentsDir: tmp);
    expect(thumb, isNotNull);
    expect(thumb!.length, lessThan(kDesignerPhotoMaxBase64));
    final bytes = base64Url.decode(thumb);
    final decoded = img.decodeImage(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 96);
    expect(decoded.height, 96);
    // It decodes back through the reader the printer uses.
    expect(decodeDesignerPhotoThumb(thumb), isNotNull);
  });

  test('no photo -> null, corrupt photo -> null', () async {
    expect(
        await designerPhotoThumbnailBase64(documentsDir: tmp), isNull);
    final dir = Directory(
        '${tmp.path}/Signtech File Sharing/Profile');
    await dir.create(recursive: true);
    await File('${dir.path}/photo.jpg').writeAsBytes(<int>[1, 2, 3, 4]);
    expect(
        await designerPhotoThumbnailBase64(documentsDir: tmp), isNull);
    expect(decodeDesignerPhotoThumb(null), isNull);
    expect(decodeDesignerPhotoThumb(''), isNull);
    expect(decodeDesignerPhotoThumb('!!!not-base64!!!'), isNull);
  });
}
