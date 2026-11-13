import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/services/rip_app.dart';
import 'package:signtech_file_sharing/services/sound_alert.dart';

PrintJob job(String id) {
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
    status: JobStatus.pending,
    receivedAt: DateTime(2026, 11, 13, 8, 30),
    filePath: '',
    fileSizeBytes: 100,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('newJobIds reports only ids never seen before', () {
    expect(
      newJobIds(knownIds: {'a', 'b'}, jobs: [job('a'), job('b'), job('c')]),
      {'c'},
    );
    expect(
      newJobIds(knownIds: {}, jobs: [job('a'), job('b')]),
      {'a', 'b'},
    );
    expect(
      newJobIds(knownIds: {'a'}, jobs: [job('a')]),
      isEmpty,
    );
    expect(newJobIds(knownIds: {'a'}, jobs: []), isEmpty);
  });

  test('the arrival beep is a silent no-op off Windows', () async {
    // Must complete without throwing on the Linux test build.
    await playNewFileSound();
  });

  test('sound toggle persists per printer', () async {
    expect(await loadSoundOn('yJet'), isTrue);
    await saveSoundOn('yJet', false);
    expect(await loadSoundOn('yJet'), isFalse);
    expect(await loadSoundOn('challenger'), isTrue);
    await saveSoundOn('yJet', true);
    expect(await loadSoundOn('yJet'), isTrue);
  });

  test('RIP program path persists per printer', () async {
    expect(await loadRipApp('yJet'), isNull);
    await saveRipApp('yJet', r'C:\Program Files\RIP\rip.exe');
    expect(await loadRipApp('yJet'), r'C:\Program Files\RIP\rip.exe');
    expect(await loadRipApp('challenger'), isNull);
    await saveRipApp('yJet', null);
    expect(await loadRipApp('yJet'), isNull);
  });
}
