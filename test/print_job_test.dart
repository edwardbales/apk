import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';

void main() {
  test('only TIF / JPG / EPS are allowed', () {
    expect(kAllowedExtensions, <String>['tif', 'tiff', 'jpg', 'jpeg', 'eps']);
    expect(isAllowedFileName('banner.tif'), isTrue);
    expect(isAllowedFileName('banner.JPG'), isTrue);
    expect(isAllowedFileName('design.eps'), isTrue);
    expect(isAllowedFileName('photo.png'), isFalse);
    expect(isAllowedFileName('doc.pdf'), isFalse);
  });

  test('printer labels are the shop printers', () {
    expect(PrinterTarget.yJet.label, 'Human Y-Jet');
    expect(PrinterTarget.challenger.label, 'Challenger');
    expect(PrinterTarget.yJet.folderName, 'Human-Y-Jet');
    expect(PrinterTarget.challenger.folderName, 'Challenger');
  });

  test('job survives a JSON round trip', () {
    final job = PrintJob(
      id: '123',
      fileName: 'banner.jpg',
      customerName: 'Shimul',
      orderNo: 'SD-1001',
      size: '10 x 4 ft',
      material: 'PVC Banner',
      quantity: 2,
      note: 'Urgent',
      designerName: 'Designer 1',
      printer: PrinterTarget.challenger,
      status: JobStatus.pending,
      receivedAt: DateTime.utc(2026, 11, 13, 5, 0),
      filePath: '/tmp/banner.jpg',
      fileSizeBytes: 12 * 1024 * 1024 + 512 * 1024,
    );
    final restored = PrintJob.fromJson(job.toJson());
    expect(restored.id, '123');
    expect(restored.printer, PrinterTarget.challenger);
    expect(restored.status, JobStatus.pending);
    expect(restored.sizeLabel, '12.5 MB');
    expect(restored.quantity, 2);
  });

  test('size label for small files', () {
    final job = PrintJob(
      id: '1',
      fileName: 'a.png',
      customerName: '',
      orderNo: '',
      size: '',
      material: '',
      quantity: 1,
      note: '',
      designerName: '',
      printer: PrinterTarget.yJet,
      status: JobStatus.pending,
      receivedAt: DateTime.now(),
      filePath: '',
      fileSizeBytes: 850 * 1024,
    );
    expect(job.sizeLabel, '850 KB');
  });

  test('copyWith only changes status', () {
    final job = PrintJob(
      id: '1',
      fileName: 'a.png',
      customerName: '',
      orderNo: '',
      size: '',
      material: '',
      quantity: 1,
      note: '',
      designerName: '',
      printer: PrinterTarget.yJet,
      status: JobStatus.pending,
      receivedAt: DateTime.now(),
      filePath: '',
      fileSizeBytes: 100,
    );
    final done = job.copyWith(status: JobStatus.done);
    expect(done.status, JobStatus.done);
    expect(done.fileName, 'a.png');
  });
}
