import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Which RIP program opens a job file, per printer PC (v1.26,
/// suggestion 6).
///
/// The shop never named its RIP software, so the app does not
/// assume one: the operator picks the RIP .exe once (sidebar →
/// RIP software) and the app remembers it. Any Windows program
/// that accepts a file path on its command line works — Maintop,
/// Flexi, Wasatch, Onyx, or anything else. The path is stored
/// per printer (each printer PC has its own RIP install).
Future<String?> loadRipApp(String printerName) async {
  final prefs = await SharedPreferences.getInstance();
  final path = prefs.getString('signtech_rip_app_$printerName');
  return (path == null || path.isEmpty) ? null : path;
}

Future<void> saveRipApp(String printerName, String? path) async {
  final prefs = await SharedPreferences.getInstance();
  if (path == null || path.isEmpty) {
    await prefs.remove('signtech_rip_app_$printerName');
  } else {
    await prefs.setString('signtech_rip_app_$printerName', path);
  }
}

/// Opens [filePath] in the RIP program at [appPath]. The RIP
/// program keeps running on its own — this only starts it, it
/// never waits for it to close. Throws a plain message when the
/// file is gone (e.g. already moved to the OK folder) or the
/// program cannot start.
Future<void> openInRip({
  required String appPath,
  required String filePath,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Open in RIP works on the Windows printer PCs.');
  }
  if (!await File(filePath).exists()) {
    throw FileSystemException(
        'File is no longer in its folder — it may have been moved to the OK folder.',
        filePath);
  }
  try {
    await Process.start(appPath, [filePath]);
  } catch (e) {
    throw Exception('Could not start the RIP program: $e');
  }
}
