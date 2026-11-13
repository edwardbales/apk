import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/services/rip_folder.dart';

void main() {
  group('resolveRipFolder', () {
    final defaultDir = Directory('/docs/Signtech File Sharing/Incoming/Human-Y-Jet');

    test('no saved path -> default folder', () {
      expect(
        resolveRipFolder(defaultDir: defaultDir).path,
        defaultDir.path,
      );
    });

    test('empty saved path -> default folder', () {
      expect(
        resolveRipFolder(defaultDir: defaultDir, savedPath: '').path,
        defaultDir.path,
      );
    });

    test('saved path -> that folder', () {
      expect(
        resolveRipFolder(
          defaultDir: defaultDir,
          savedPath: 'D:/RIP/Human Y-Jet',
        ).path,
        'D:/RIP/Human Y-Jet',
      );
    });
  });

  group('ripFolderKey', () {
    test('one key per printer', () {
      expect(ripFolderKey(PrinterTarget.yJet), 'signtech_rip_folder_yJet');
      expect(
        ripFolderKey(PrinterTarget.challenger),
        'signtech_rip_folder_challenger',
      );
      expect(
        ripFolderKey(PrinterTarget.yJet),
        isNot(ripFolderKey(PrinterTarget.challenger)),
      );
    });
  });
}
