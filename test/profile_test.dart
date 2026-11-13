import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/models/print_job.dart';
import 'package:signtech_file_sharing/screens/profile_screen.dart';
import 'package:signtech_file_sharing/theme.dart';

void main() {
  testWidgets('profile holds designer name + printer IPs, no job fields',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var savedName = '';
    final savedIps = <PrinterTarget, String>{};
    await tester.pumpWidget(MaterialApp(
      theme: SigntechTheme.dark,
      home: ProfileScreen(
        roleLabel: 'Designer PC',
        isDesigner: true,
        designerName: 'Designer 1',
        yJetIp: '192.168.1.101',
        challengerIp: '192.168.1.102',
        otherPrinterLabel: 'Challenger',
        otherPrinterIp: '',
        onDesignerNameChanged: (v) => savedName = v,
        onPrinterIpChanged: (p, ip) => savedIps[p] = ip,
        onOtherPrinterIpChanged: (_) {},
        onChangeRole: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Profile / Settings'), findsOneWidget);
    // Profile photo section (designer only).
    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Designer name  (e.g. Designer 1)'), findsOneWidget);
    expect(find.text('Human Y-Jet PC IP  (e.g. 192.168.1.101)'),
        findsOneWidget);
    expect(find.text('Challenger PC IP  (e.g. 192.168.1.102)'),
        findsOneWidget);
    // Job fields must NOT be in the profile.
    expect(find.text('Customer name'), findsNothing);
    expect(find.text('Order No (SD-1001)'), findsNothing);
    expect(find.text('Size (W x H)'), findsNothing);
    expect(find.text('Quantity'), findsNothing);
    expect(find.textContaining('removed from the app completely'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(savedName, 'Designer 1');
    expect(savedIps[PrinterTarget.yJet], '192.168.1.101');
    expect(savedIps[PrinterTarget.challenger], '192.168.1.102');
    expect(find.text('Profile saved.'), findsOneWidget);
  });
}
