import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/screens/printer_screen.dart';
import 'package:signtech_file_sharing/theme.dart';

void main() {
  testWidgets('printer dashboard has a sidebar with profile, IP, '
      'theme and profile buttons', (tester) async {
    var themeToggled = false;
    var profileOpened = false;

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
    // Theme button (dark mode is on, so it offers Light).
    expect(find.text('Light theme'), findsOneWidget);
    expect(find.text('Profile / Settings'), findsOneWidget);
    // Main area still shows the incoming files.
    expect(find.text('Incoming files'), findsOneWidget);
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
}
