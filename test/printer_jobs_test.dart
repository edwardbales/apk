import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/screens/printer_screen.dart';
import 'package:signtech_file_sharing/theme.dart';
import 'package:signtech_file_sharing/widgets/job_detail_card.dart';
import 'package:signtech_file_sharing/widgets/job_section_tabs.dart';

import 'test_fonts.dart';

PrintJob testJob({
  String designer = 'Designer 1',
  String? photo,
  String? preview,
  JobStatus status = JobStatus.pending,
  bool blackConverted = true,
}) {
  return PrintJob(
    id: 'job-$designer',
    fileName: 'banner_shop_front.tif',
    customerName: '',
    orderNo: '',
    size: '',
    material: 'PVC Banner',
    quantity: 1,
    note: 'Urgent — needed today',
    designerName: designer,
    printer: PrinterTarget.yJet,
    status: status,
    receivedAt: DateTime(2026, 11, 13, 17, 41),
    filePath: '/tmp/banner_shop_front.tif',
    fileSizeBytes: 13 * 1024 * 1024,
    colorMode: 'CMYK',
    blackConverted: blackConverted,
    designerPhotoBase64: photo,
    previewBase64: preview,
  );
}

/// A real 96x96 JPEG thumbnail, as the designer side would send.
String testPhotoBase64() {
  final image = img.Image(width: 96, height: 96);
  img.fill(image, color: img.ColorRgb8(124, 58, 237));
  return base64UrlEncode(img.encodeJpg(image, quality: 75));
}

void main() {
  test('full sent time reads like a clock, not a stamp', () {
    expect(formatJobTimeFull(DateTime(2026, 11, 13, 17, 41)),
        '13 Nov 2026, 5:41 PM');
    expect(formatJobTimeFull(DateTime(2026, 11, 13, 9, 5)),
        '13 Nov 2026, 9:05 AM');
    expect(formatJobTimeFull(DateTime(2026, 11, 13, 0, 30)),
        '13 Nov 2026, 12:30 AM');
  });

  testWidgets('job detail card shows photo, file, time and design '
      'details', (tester) async {
    await loadPoppins();
    var statusSet;
    var forwarded = false;
    final job = testJob(photo: testPhotoBase64());

    await tester.pumpWidget(
      MaterialApp(
        theme: SigntechTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: JobDetailCard(
              job: job,
              narrow: false,
              otherPrinterLabel: 'Challenger',
              onSetStatus: (j, s) => statusSet = s,
              onForward: (_) => forwarded = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Designer + photo.
    expect(find.text('Designer 1'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    // File + when.
    expect(find.text('banner_shop_front.tif'), findsOneWidget);
    expect(find.text('Sent: 13 Nov 2026, 5:41 PM'), findsOneWidget);
    // Design details.
    expect(find.text('PVC Banner'), findsOneWidget);
    expect(find.text('13.0 MB'), findsOneWidget);
    expect(find.text('CMYK'), findsOneWidget);
    expect(find.text('C95 M95 Y95 (3-color black)'), findsOneWidget);
    expect(find.text('Urgent — needed today'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    // Actions work.
    await tester.tap(find.text('Printing'));
    expect(statusSet, JobStatus.printing);
    await tester.tap(find.text('Send to Challenger'));
    expect(forwarded, isTrue);
  });

  testWidgets('preview banner shows the design and Open in RIP works',
      (tester) async {
    await loadPoppins();
    var opened = false;
    // The photo thumbnail bytes double as the preview here: a
    // real 96x96 JPEG, valid for Image.memory.
    await tester.pumpWidget(
      MaterialApp(
        theme: SigntechTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: JobDetailCard(
              job: testJob(
                preview: testPhotoBase64(),
                status: JobStatus.done,
              ),
              narrow: false,
              otherPrinterLabel: 'Challenger',
              onSetStatus: (_, __) {},
              onForward: (_) {},
              onOpenInRip: (_) => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // One image only: the preview banner (no designer photo).
    expect(find.byType(Image), findsOneWidget);
    // 'Done' appears twice: the status pill and the Done action.
    expect(find.text('Done'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Open in RIP'));
    expect(opened, isTrue);
  });

  testWidgets('job without a photo shows the initials avatar',
      (tester) async {
    await loadPoppins();
    await tester.pumpWidget(
      MaterialApp(
        theme: SigntechTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: JobDetailCard(
              job: testJob(designer: 'Designer 2', blackConverted: false),
              narrow: true,
              otherPrinterLabel: 'Challenger',
              onSetStatus: (_, __) {},
              onForward: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Designer 2'), findsOneWidget);
    expect(find.text('D2'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Not converted'), findsOneWidget);
    // No RIP button without the callback.
    expect(find.byTooltip('Open in RIP'), findsNothing);
    // Narrow actions use the short Forward label.
    expect(find.text('Forward'), findsOneWidget);
  });

  testWidgets('section tabs show counts and switch', (tester) async {
    await loadPoppins();
    var section = JobSection.active;

    await tester.pumpWidget(
      MaterialApp(
        theme: SigntechTheme.dark,
        home: Scaffold(
          body: JobSectionTabs(
            section: section,
            activeCount: 2,
            completeCount: 5,
            onSectionChanged: (s) => section = s,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Active (2)'), findsOneWidget);
    expect(find.text('Complete (5)'), findsOneWidget);
    await tester.tap(find.text('Complete (5)'));
    expect(section, JobSection.complete);
  });

  testWidgets('sidebar Jobs button switches to the Jobs view and back',
      (tester) async {
    tester.view.physicalSize = const Size(800, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPoppins();
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      MaterialApp(
        theme: SigntechTheme.dark,
        home: Scaffold(
          body: PrinterScreen(
            printer: PrinterTarget.yJet,
            otherPrinterIp: '',
            onOtherPrinterIpChanged: (_) {},
            isDark: true,
            onToggleTheme: () {},
            onOpenProfile: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Navigation buttons live in the sidebar.
    expect(find.text('NAVIGATION'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Jobs'), findsOneWidget);
    // Dashboard is the default view: overview only (v1.24),
    // stats + OK banner, no file list.
    expect(find.text('OK folder — auto Done'), findsOneWidget);
    expect(find.text('Incoming files'), findsNothing);

    await tester.ensureVisible(find.text('Jobs').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jobs').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Jobs view: its own heading, no dashboard list — and the
    // RIP-folder button moved here with the files. Sections
    // (v1.25) sit above the filters.
    expect(find.text('Incoming files'), findsNothing);
    expect(find.text('No files yet.'), findsOneWidget);
    expect(find.byTooltip('Open RIP folder'), findsOneWidget);
    expect(find.text('Active (0)'), findsOneWidget);
    expect(find.text('Complete (0)'), findsOneWidget);

    // Switching sections with no jobs at all still shows the
    // same empty state (there is nothing in either section).
    await tester.tap(find.text('Complete (0)'));
    await tester.pump();
    expect(find.text('No files yet.'), findsOneWidget);

    // The earlier ensureVisible scrolled the sidebar down, so
    // Dashboard sits above the fold — scroll it back first.
    await tester.ensureVisible(find.text('Dashboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard'));
    await tester.pump();
    expect(find.text('OK folder — auto Done'), findsOneWidget);
  });
}
