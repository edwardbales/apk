import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/services/done_watcher.dart';

PrintJob _job(String id, JobStatus status) => PrintJob(
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
      status: status,
      receivedAt: DateTime.now(),
      filePath: '',
      fileSizeBytes: 100,
    );

void main() {
  test('a pending job the printer reports done is newly done', () {
    final found = newlyDoneJobs(
      sent: [_job('1', JobStatus.pending), _job('2', JobStatus.printing)],
      printerStatuses: {'1': JobStatus.done, '2': JobStatus.printing},
    );
    expect(found.map((j) => j.id), ['1']);
  });

  test('a job already marked done is never reported again', () {
    final found = newlyDoneJobs(
      sent: [_job('1', JobStatus.done)],
      printerStatuses: {'1': JobStatus.done},
    );
    expect(found, isEmpty);
  });

  test('unknown ids and missing statuses are ignored', () {
    final found = newlyDoneJobs(
      sent: [_job('1', JobStatus.pending)],
      printerStatuses: {'other': JobStatus.done},
    );
    expect(found, isEmpty);
  });
}
