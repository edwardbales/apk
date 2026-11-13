import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/print_job.dart';

/// The operator-chosen RIP folder (v1.21).
///
/// By default received files land in
///   Documents/Signtech File Sharing/Incoming/<Printer>/
/// The printer PC operator can pick any folder instead (sidebar,
/// "Select folder") — e.g. the RIP software's own hot folder.
/// The choice is saved per printer PC and survives restarts.
///
/// jobs.json always stays in the DEFAULT folder, so the job list
/// survives a RIP-folder change; only new files go to the new
/// folder. Old jobs keep pointing at the files where they landed.

String ripFolderKey(PrinterTarget printer) =>
    'signtech_rip_folder_${printer.name}';

/// The folder received files land in: the saved choice when one
/// exists, else the default Incoming folder.
Directory resolveRipFolder({
  required Directory defaultDir,
  String? savedPath,
}) {
  if (savedPath != null && savedPath.isNotEmpty) {
    return Directory(savedPath);
  }
  return defaultDir;
}

Future<String?> loadSavedRipFolder(PrinterTarget printer) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(ripFolderKey(printer));
}

Future<void> saveRipFolder(PrinterTarget printer, String? path) async {
  final prefs = await SharedPreferences.getInstance();
  if (path == null) {
    await prefs.remove(ripFolderKey(printer));
  } else {
    await prefs.setString(ripFolderKey(printer), path);
  }
}
