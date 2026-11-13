import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/print_job.dart';

/// Per-printer sound toggle (v1.26): the operator can silence
/// the arrival beep. Default ON.
Future<bool> loadSoundOn(String printerName) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('signtech_sound_on_$printerName') ?? true;
}

Future<void> saveSoundOn(String printerName, bool on) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('signtech_sound_on_$printerName', on);
}

/// A short two-tone beep when a new file lands on the printer PC
/// (v1.26, suggestion 4).
///
/// No new package: Windows already has PowerShell, and
/// `[console]::Beep` plays through the PC speaker path without
/// any audio file or native plugin — so there is nothing new for
/// the Windows CI build to compile. On any other platform this
/// is a silent no-op (the Linux test build never beeps). A
/// failure to beep never breaks the upload — it is best-effort.
Future<void> playNewFileSound() async {
  if (!Platform.isWindows) return;
  try {
    await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-WindowStyle',
        'Hidden',
        '-Command',
        '[console]::Beep(880, 180); [console]::Beep(1318, 260)',
      ],
    ).timeout(const Duration(seconds: 5));
  } catch (_) {
    // Sound is a nicety, never a failure.
  }
}

/// The ids in [jobs] that [knownIds] has not seen yet — the
/// newly arrived files. Pure, so it is unit-testable without a
/// screen: the printer screen keeps the ids it has already
/// announced and beeps only for the difference.
Set<String> newJobIds({
  required Set<String> knownIds,
  required List<PrintJob> jobs,
}) {
  return jobs.map((j) => j.id).toSet().difference(knownIds);
}
