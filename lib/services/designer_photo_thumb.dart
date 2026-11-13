import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'profile_photo.dart';

/// The designer's profile photo, shrunk to a 96x96 JPEG thumbnail
/// and base64url-encoded so it can travel with the upload.
///
/// The printer PC never sees the designer's Profile folder (that
/// lives on the Designer PC only), so the photo has to ride along
/// with the file itself — as one small `x-signtech-designer-photo`
/// header. A 96x96 JPEG at quality 75 is normally 3-8 KB, so it
/// costs almost nothing on top of a banner file.
///
/// Returns null when there is no photo, the photo cannot be read
/// or decoded, or the thumbnail is unexpectedly large. Sending a
/// file must NEVER fail because of the photo — the printer falls
/// back to the designer's initials avatar.
const int kDesignerPhotoThumbSize = 96;
const int kDesignerPhotoMaxBase64 = 32768;

Future<String?> designerPhotoThumbnailBase64(
    {Directory? documentsDir}) async {
  try {
    final photo =
        await loadDesignerPhotoFile(documentsDir: documentsDir);
    if (photo == null) return null;
    final bytes = await photo.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final thumb = img.copyResizeCropSquare(
      decoded,
      size: kDesignerPhotoThumbSize,
    );
    final jpg = img.encodeJpg(thumb, quality: 75);
    final encoded = base64UrlEncode(jpg);
    if (encoded.length > kDesignerPhotoMaxBase64) return null;
    return encoded;
  } catch (_) {
    return null;
  }
}

/// Decodes a thumbnail from [base64] (as sent in the upload
/// header), or null when it is missing or unusable. The caller
/// shows the initials avatar instead.
List<int>? decodeDesignerPhotoThumb(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  try {
    if (base64.length > kDesignerPhotoMaxBase64) return null;
    return base64Url.decode(base64);
  } catch (_) {
    return null;
  }
}
