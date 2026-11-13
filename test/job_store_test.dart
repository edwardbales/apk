import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/services/job_store.dart';

PrintJob job(String id, JobStatus status) {
  return PrintJob(
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
    receivedAt: DateTime(2026, 11, 13, 8, 30),
    filePath: '',
    fileSizeBytes: 100,
  );
}

void main() {
  late Directory tmp;
  late JobStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('signtech_store');
    store = JobStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('clearCompleted removes only finished jobs', () async {
    await store.save([
      job('a', JobStatus.pending),
      job('b', JobStatus.printing),
      job('c', JobStatus.done),
      job('d', JobStatus.forwarded),
      job('e', JobStatus.done),
    ]);
    final removed = await store.clearCompleted();
    expect(removed, 3); // 2 Done + 1 Forwarded
    final kept = await store.load();
    expect(kept.map((j) => j.id).toList(), ['a', 'b']);
    // A second clear finds nothing left to remove.
    expect(await store.clearCompleted(), 0);
  });

  test('clearCompleted on an empty store removes nothing', () async {
    expect(await store.clearCompleted(), 0);
    expect(await store.load(), isEmpty);
  });

  test('a damaged jobs.json falls back to the previous good copy',
      () async {
    // Two saves: the second one leaves the first list as .bak.
    await store.save([job('a', JobStatus.pending)]);
    await store.save([
      job('a', JobStatus.pending),
      job('b', JobStatus.done),
    ]);
    expect(await File('${tmp.path}/jobs.json.bak').exists(), isTrue);
    // Damage the live file — as a power cut mid-write would.
    await File('${tmp.path}/jobs.json')
        .writeAsString('{"half-written');
    final loaded = await store.load();
    expect(loaded.map((j) => j.id).toList(), ['a']);
  });

  test('damaged live file and no backup loads empty', () async {
    await File('${tmp.path}/jobs.json').writeAsString('garbage');
    expect(await store.load(), isEmpty);
  });

  test('save leaves a valid jobs.json behind', () async {
    await store.save([job('a', JobStatus.pending)]);
    final raw = await File('${tmp.path}/jobs.json').readAsString();
    expect(raw, contains('"id":"a"'));
    expect(await File('${tmp.path}/jobs.json.tmp').exists(), isFalse);
  });
}
