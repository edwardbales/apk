import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/services/local_notify.dart';

void main() {
  test('notifications init + show never throw off Windows', () async {
    // On the Linux test build both calls early-return; the test
    // proves the wiring cannot crash the status poll. The real
    // toast is a Windows-only path, verified on a printer PC.
    await initLocalNotifications();
    await showDoneNotification(
      designerName: 'Designer 1',
      fileName: 'banner_shop_front.tif',
    );
  });
}
