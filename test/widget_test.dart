import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signtech_file_sharing/main.dart';

void main() {
  testWidgets('first launch asks which PC this is', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const SigntechFileSharingApp());
    await tester.pumpAndSettle();
    expect(find.text('What is this PC?'), findsOneWidget);
    // The user's printer logo is the app logo in the header.
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/logo.png'),
        findsOneWidget);
    expect(find.text('Designer PC'), findsOneWidget);
    expect(find.text('Printer PC — Human Y-Jet'), findsOneWidget);
    expect(find.text('Printer PC — Challenger'), findsOneWidget);
  });

  testWidgets('designer role opens the designer screen', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'signtech_role': 'designer',
    });
    await tester.pumpWidget(const SigntechFileSharingApp());
    await tester.pumpAndSettle();
    expect(find.text('Which printer to send to?'), findsOneWidget);
    // Identity bar is always on top, even before a name is set.
    expect(find.textContaining('Change name / IP in Profile'), findsOneWidget);
    // Notification bell lives in the top bar (designer only).
    expect(find.byIcon(Icons.notifications), findsOneWidget);
    expect(find.text('Human Y-Jet'), findsOneWidget);
    expect(find.text('Challenger'), findsOneWidget);
    // Customer / Order / Size / Quantity — total remove.
    expect(find.text('Customer name'), findsNothing);
    expect(find.text('Order No (SD-1001)'), findsNothing);
    expect(find.text('Size (W x H)'), findsNothing);
    expect(find.text('Quantity'), findsNothing);
    // Material + Note stay.
    expect(find.text('Material'), findsOneWidget);
    expect(find.text('Note (optional)'), findsOneWidget);
  });
}
