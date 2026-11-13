import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/services/job_store.dart';
import 'package:signtech_file_sharing/services/printer_server.dart';
import 'package:signtech_file_sharing/services/transfer_service.dart';

void main() {
  test('ping + upload over LAN protocol (loopback)', () async {
    final temp = await Directory.systemTemp.createTemp('signtech-test-');
    try {
      final incoming = Directory('${temp.path}/Incoming');
      final received = <PrintJob>[];
      // Port 0 = let the OS pick a free port, like a real LAN bind.
      final server = PrinterServer(
        saveDirectory: incoming,
        printer: PrinterTarget.yJet,
        onJobReceived: received.add,
        port: 0,
      );
      await server.start();
      final port = server.boundPort;
      expect(port, isNot(0));

      expect(await TransferService.ping(host: '127.0.0.1', port: port),
          isTrue);
      expect(await TransferService.ping(host: '127.0.0.1', port: port + 1),
          isFalse);

      final source = File('${temp.path}/banner.jpg');
      await source.writeAsBytes(List<int>.generate(5000, (i) => i % 256));
      final job = PrintJob(
        id: 'test-1',
        fileName: 'banner.jpg',
        customerName: 'Shimul',
        orderNo: 'SD-1001',
        size: '10 x 4 ft',
        material: 'PVC Banner',
        quantity: 1,
        note: '',
        designerName: 'Designer 1',
        printer: PrinterTarget.yJet,
        status: JobStatus.pending,
        receivedAt: DateTime.now(),
        filePath: source.path,
        fileSizeBytes: 5000,
      );
      var lastProgress = 0.0;
      await TransferService.uploadFile(
        host: '127.0.0.1',
        port: port,
        file: source,
        job: job,
        onProgress: (p) => lastProgress = p,
      );
      expect(lastProgress, 1.0);
      expect(received, hasLength(1));
      expect(received.first.fileName, 'banner.jpg');
      expect(received.first.customerName, 'Shimul');
      expect(received.first.printer, PrinterTarget.yJet);

      final saved = File(received.first.filePath);
      expect(await saved.exists(), isTrue);
      expect(await saved.length(), 5000);

      // A second job with the SAME file name keeps that exact name
      // but must not overwrite the first — each job gets its own
      // folder, so the file name stays identical in both.
      final job2 = PrintJob(
        id: 'test-2',
        fileName: 'banner.jpg',
        customerName: 'Shimul',
        orderNo: 'SD-1002',
        size: '10 x 4 ft',
        material: 'PVC Banner',
        quantity: 1,
        note: '',
        designerName: 'Designer 1',
        printer: PrinterTarget.yJet,
        status: JobStatus.pending,
        receivedAt: DateTime.now(),
        filePath: source.path,
        fileSizeBytes: 5000,
      );
      await TransferService.uploadFile(
        host: '127.0.0.1',
        port: port,
        file: source,
        job: job2,
      );
      expect(received, hasLength(2));
      expect(received[1].fileName, 'banner.jpg');
      expect(received[1].filePath, isNot(received[0].filePath));
      expect(await File(received[0].filePath).exists(), isTrue);
      expect(await File(received[1].filePath).exists(), isTrue);

      // JobStore round trip in the same folder.
      final store = JobStore(incoming);
      await store.add(received.first);
      final loaded = await store.load();
      expect(loaded.first.fileName, 'banner.jpg');

      await server.stop();
      expect(server.isRunning, isFalse);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('GET /status reports job statuses for the designer poll', () async {
    final temp = await Directory.systemTemp.createTemp('signtech-status-');
    try {
      final incoming = Directory('${temp.path}/Incoming');
      final jobs = <PrintJob>[
        PrintJob(
          id: 'done-1',
          fileName: 'banner.tif',
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
        ),
        PrintJob(
          id: 'pending-1',
          fileName: 'sticker.jpg',
          customerName: '',
          orderNo: '',
          size: '',
          material: 'Sticker',
          quantity: 1,
          note: '',
          designerName: 'Designer 2',
          printer: PrinterTarget.yJet,
          status: JobStatus.pending,
          receivedAt: DateTime.now(),
          filePath: '',
          fileSizeBytes: 100,
        ),
      ];
      final server = PrinterServer(
        saveDirectory: incoming,
        printer: PrinterTarget.yJet,
        onJobReceived: (_) {},
        listJobs: () => jobs,
        port: 0,
      );
      await server.start();
      final statuses = await TransferService.fetchStatuses(
          host: '127.0.0.1', port: server.boundPort);
      expect(statuses['done-1'], JobStatus.done);
      expect(statuses['pending-1'], JobStatus.pending);
      await server.stop();
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('fetchStatuses returns an empty map when the printer is offline',
      () async {
    final statuses =
        await TransferService.fetchStatuses(host: '127.0.0.1', port: 1);
    expect(statuses, isEmpty);
  });
}
