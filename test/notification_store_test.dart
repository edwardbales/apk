import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/services/notification_store.dart';

PrintJob _job(String id) => PrintJob(
      id: id,
      fileName: '$id.tif',
      customerName: '',
      orderNo: '',
      size: '',
      material: 'PVC Banner',
      quantity: 1,
      note: '',
      designerName: 'Designer 1',
      printer: PrinterTarget.yJet,
      status: JobStatus.done,
      receivedAt: DateTime.now(),
      filePath: '',
      fileSizeBytes: 100,
    );

void main() {
  test('bell badge: add, dedupe, mark read, dismiss, persist', () async {
    final temp = await Directory.systemTemp.createTemp('signtech-notif-');
    try {
      final store = NotificationStore();
      await store.load(documentsDir: temp);
      expect(store.unreadCount, 0);

      await store.add(_job('1'));
      await store.add(_job('1')); // same job twice = one notification
      await store.add(_job('2'));
      expect(store.items.length, 2);
      expect(store.unreadCount, 2);

      await store.markAllRead();
      expect(store.unreadCount, 0);
      expect(store.items.length, 2);

      await store.dismiss('1');
      expect(store.items.map((n) => n.job.id), ['2']);

      // Survives a restart: a fresh store loads the saved list.
      final reloaded = NotificationStore();
      await reloaded.load(documentsDir: temp);
      expect(reloaded.items.map((n) => n.job.id), ['2']);
      expect(reloaded.unreadCount, 0);

      await reloaded.clearAll();
      expect(reloaded.items, isEmpty);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
