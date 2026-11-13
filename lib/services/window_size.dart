import 'dart:ui';

import 'package:window_manager/window_manager.dart';

// Per-role window size (v1.20).
//
// The printer dashboard only shows the approved design (sidebar +
// one-row stats, banner, chips and job actions) at 800x650. At the
// 430px SHAREit size it falls back to the compact stacked layout,
// so the printer window opens wide and the designer window stays
// portrait:
//
//   Designer PC  -> 430 x 740  (SHAREit-style portrait)
//   Printer PC   -> 800 x 650  (dashboard always the wide layout)
//
// The workflow still patches windows/runner/main.cpp to open at
// 430x740; main() resizes the window for the saved role before it
// is shown, and _setRole resizes it again when the role is picked.
// If the native plugin is unavailable (headless run, test) the
// resize is skipped and the app keeps the size it opened at.

/// Window size for a saved role value ('designer' | 'yjet' |
/// 'challenger' | null = role not picked yet).
Size windowSizeForRole(String? role) {
  if (role == 'yjet' || role == 'challenger') {
    return const Size(800, 650);
  }
  return const Size(430, 740);
}

/// Resize the window for [role] and centre it on screen.
/// Never throws: a missing plugin must not stop the app starting.
Future<void> applyWindowSizeForRole(String? role) async {
  try {
    await windowManager.setSize(windowSizeForRole(role));
    await windowManager.center();
  } catch (_) {
    // No window plugin — keep the size the window opened at.
  }
}
