import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Windows toast notifications (v1.26, suggestion 7): when a
/// sent file turns Done, the designer gets a real Windows
/// notification — visible even when the app is minimised —
/// not just the green SnackBar inside the app.
///
/// Windows only, by design: the designer PCs are Windows, and
/// the plugin has no use on the Linux test build (both calls
/// early-return there). Everything is best-effort and guarded:
/// a notification failure must never break the status poll.
///
/// One honest limit: the toast fires while the designer app is
/// running (even minimised). When the app is fully closed
/// nothing is polling the printers, so there is nothing to
/// notify about — that would need a background service, which
/// this version does not add.
final _plugin = FlutterLocalNotificationsPlugin();

/// A stable identity for this app's toasts. The GUID must never
/// change — Windows ties the toast activation callback to it.
const String _kGuid = '7f3a2c1e-5b4d-4a8e-9c6f-1a2b3c4d5e6f';

Future<void> initLocalNotifications() async {
  if (!Platform.isWindows) return;
  try {
    await _plugin.initialize(
      const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'Signtech File Sharing',
          appUserModelId: 'com.signtech.file_sharing',
          guid: _kGuid,
        ),
      ),
    );
  } catch (_) {
    // Notifications are a nicety — startup never fails on them.
  }
}

/// Shows the "Printing Ready" toast for one finished file.
Future<void> showDoneNotification({
  required String designerName,
  required String fileName,
}) async {
  if (!Platform.isWindows) return;
  try {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 2147483647,
      'Printing Ready',
      'Hey $designerName, your design file completely Printing Ready — $fileName',
      const NotificationDetails(
        windows: WindowsNotificationDetails(),
      ),
    );
  } catch (_) {
    // A missed toast is fine — the in-app notification stays.
  }
}
