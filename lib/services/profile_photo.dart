import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The designer's profile photo.
///
/// Saved on this PC only, at
/// Documents/Signtech File Sharing/Profile/photo.<ext> — one photo
/// per Designer PC. The printer PCs never receive it; they keep
/// showing the designer's initials avatar.
const List<String> _kPhotoExtensions = ['jpg', 'jpeg', 'png'];

Directory _profileDir(Directory documentsDir) => Directory(
    '${documentsDir.path}/Signtech File Sharing/Profile');

/// The saved photo file, or null when no photo is set.
/// [documentsDir] is only for tests — the app always passes null.
Future<File?> loadDesignerPhotoFile({Directory? documentsDir}) async {
  final docs =
      documentsDir ?? await getApplicationDocumentsDirectory();
  final dir = _profileDir(docs);
  for (final ext in _kPhotoExtensions) {
    final file = File('${dir.path}/photo.$ext');
    if (await file.exists()) return file;
  }
  return null;
}

/// Copies [picked] in as the profile photo, replacing any old one.
Future<File> saveDesignerPhoto(File picked,
    {Directory? documentsDir}) async {
  final docs =
      documentsDir ?? await getApplicationDocumentsDirectory();
  final dir = _profileDir(docs);
  await dir.create(recursive: true);
  for (final ext in _kPhotoExtensions) {
    final old = File('${dir.path}/photo.$ext');
    if (await old.exists()) await old.delete();
  }
  final ext = picked.path.split('.').last.toLowerCase();
  final safeExt = _kPhotoExtensions.contains(ext) ? ext : 'jpg';
  final target = File('${dir.path}/photo.$safeExt');
  return picked.copy(target.path);
}

/// Deletes the saved photo, if any.
Future<void> removeDesignerPhoto({Directory? documentsDir}) async {
  final docs =
      documentsDir ?? await getApplicationDocumentsDirectory();
  final dir = _profileDir(docs);
  for (final ext in _kPhotoExtensions) {
    final file = File('${dir.path}/photo.$ext');
    if (await file.exists()) await file.delete();
  }
}
