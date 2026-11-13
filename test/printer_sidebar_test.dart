import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/screens/printer_screen.dart';
import 'package:signtech_file_sharing/theme.dart';

import 'test_fonts.dart';

void main() {
  testWidgets('printer dashboard has a sidebar with profile, IP, '
      'theme and profile buttons', (tester) async {
    var themeToggled = false;
    var profileOpened = false;

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
          onToggleTheme: () => themeToggled = true,
          onOpenProfile: () => profileOpened = true,
            )),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Sidebar sections.
    expect(find.text('Printer dashboard'), findsOneWidget);
    expect(find.text('PRINTER PROFILE'), findsOneWidget);
    expect(find.text('Human Y-Jet'), findsWidgets);
    expect(find.text('SERVER ADDRESS'), findsOneWidget);
    // RIP folder card (v1.21): operator can pick the folder.
    expect(find.text('RIP FOLDER'), findsOneWidget);
    expect(find.text('Select folder'), findsOneWidget);
    // Theme button (dark mode is on, so it offers Light).
    expect(find.text('Light theme'), findsOneWidget);
    expect(find.text('Profile / Settings'), findsOneWidget);
    // Dashboard is overview only (v1.24): stats + OK banner + a
    // hint that the files live under Jobs — no file list here.
    expect(find.text('Incoming files'), findsNothing);
    expect(find.text('OK folder — auto Done'), findsOneWidget);
    expect(find.textContaining('Files live under Jobs'), findsOneWidget);
    // OK folder banner: auto-Done + a button to open the folder.
    expect(find.text('OK folder — auto Done'), findsOneWidget);
    expect(find.text('Open OK folder'), findsOneWidget);

    // Sidebar buttons sit at the bottom of the panel — scroll
    // them into view first (600px test window).
    await tester.ensureVisible(find.text('Light theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light theme'));
    expect(themeToggled, isTrue);

    await tester.ensureVisible(find.text('Profile / Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile / Settings'));
    expect(profileOpened, isTrue);
  });

  testWidgets('portrait 430x740: sidebar stays, narrower (240px)',
      (tester) async {
    tester.view.physicalSize = const Size(430, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPoppins();
    var profileOpened = false;

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
          onOpenProfile: () => profileOpened = true,
            )),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The sidebar panel system is the printer dashboard at every
    // width — at 430px it is narrower (240px), not a top card.
    expect(find.text('Printer dashboard'), findsOneWidget);
    expect(find.text('PRINTER PROFILE'), findsOneWidget);
    expect(find.text('SERVER ADDRESS'), findsOneWidget);
    expect(find.text('RIP FOLDER'), findsOneWidget);
    expect(find.text('Select folder'), findsOneWidget);
    expect(find.text('Human Y-Jet'), findsWidgets);
    expect(find.text('Light theme'), findsOneWidget);
    expect(find.text('Profile / Settings'), findsOneWidget);
    // Dashboard is overview only (v1.24) — no file list here.
    expect(find.text('Files'), findsNothing);
    expect(find.text('Incoming files'), findsNothing);
    // Narrow banner uses the short title (the full title
    // wraps to three lines beside the 240px sidebar).
    expect(find.text('OK folder'), findsOneWidget);
    expect(find.text('OK folder — auto Done'), findsNothing);

    await tester.ensureVisible(find.text('Profile / Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile / Settings'));
    expect(profileOpened, isTrue);
  });
}
