import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/services/ok_folder.dart';

PrintJob _job(String id, String fileName, JobStatus status,
        {DateTime? at}) =>
    PrintJob(
      id: id,
      fileName: fileName,
      customerName: '',
      orderNo: '',
      size: '',
      material: 'PVC Banner',
      quantity: 1,
      note: '',
      designerName: 'Designer 1',
      printer: PrinterTarget.yJet,
      status: status,
      receivedAt: at ?? DateTime(2026, 11, 13, 8, 0),
      filePath: '',
      fileSizeBytes: 100,
    );

void main() {
  test('an OK file marks the oldest matching job that is not done', () {
    final jobs = [
      _job('old', 'banner.tif', JobStatus.pending,
          at: DateTime(2026, 11, 13, 8, 0)),
      _job('new', 'banner.tif', JobStatus.printing,
          at: DateTime(2026, 11, 13, 9, 0)),
      _job('other', 'sticker.jpg', JobStatus.pending),
    ];
    expect(
        findJobForOkFile(jobs: jobs, fileName: 'banner.tif')?.id, 'old');
    expect(findJobForOkFile(jobs: jobs, fileName: 'sticker.jpg')?.id,
        'other');
  });

  test('already-done and forwarded jobs are never matched', () {
    final jobs = [
      _job('done', 'banner.tif', JobStatus.done),
      _job('fwd', 'sticker.jpg', JobStatus.forwarded),
    ];
    expect(findJobForOkFile(jobs: jobs, fileName: 'banner.tif'), isNull);
    expect(findJobForOkFile(jobs: jobs, fileName: 'sticker.jpg'), isNull);
  });

  test('an unknown file name matches nothing', () {
    final jobs = [_job('1', 'banner.tif', JobStatus.pending)];
    expect(findJobForOkFile(jobs: jobs, fileName: 'random.tif'), isNull);
  });
}
