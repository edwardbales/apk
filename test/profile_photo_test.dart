import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/services/profile_photo.dart';

void main() {
  test('profile photo: save, load, replace, remove', () async {
    final temp = await Directory.systemTemp.createTemp('signtech-photo-');
    try {
      expect(await loadDesignerPhotoFile(documentsDir: temp), isNull);

      final picked = File('${temp.path}/me.png');
      await picked.writeAsBytes([1, 2, 3, 4]);
      final saved = await saveDesignerPhoto(picked, documentsDir: temp);
      expect(await saved.exists(), isTrue);
      expect(saved.path.endsWith('photo.png'), isTrue);

      final loaded = await loadDesignerPhotoFile(documentsDir: temp);
      expect(loaded?.path, saved.path);

      // Saving a new photo replaces the old one.
      final picked2 = File('${temp.path}/me2.jpg');
      await picked2.writeAsBytes([5, 6, 7]);
      await saveDesignerPhoto(picked2, documentsDir: temp);
      expect(await loadDesignerPhotoFile(documentsDir: temp),
          isNotNull);
      expect(
          (await loadDesignerPhotoFile(documentsDir: temp))!
              .path
              .endsWith('photo.jpg'),
          isTrue);

      await removeDesignerPhoto(documentsDir: temp);
      expect(await loadDesignerPhotoFile(documentsDir: temp), isNull);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
