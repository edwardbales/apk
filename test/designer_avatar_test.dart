import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/widgets/designer_avatar.dart';

void main() {
  test('designer initials', () {
    expect(designerInitials('Designer 1'), 'D1');
    expect(designerInitials('Designer 2'), 'D2');
    expect(designerInitials('Monjurul Islam'), 'MI');
    expect(designerInitials('Rafi'), 'RA');
    expect(designerInitials(''), '?');
  });

  test('same designer always gets the same colour, different designers differ',
      () {
    expect(designerColor('Designer 1'), designerColor('Designer 1'));
    expect(designerColor('Designer 1'),
        isNot(designerColor('Designer 2')));
  });

  testWidgets('avatar shows initials in the designer colour',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DesignerAvatar(name: 'Designer 1'),
      ),
    ));
    await tester.pump();
    expect(find.text('D1'), findsOneWidget);
    expect(find.byType(DesignerChip), findsNothing);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DesignerChip(name: 'Designer 2')),
    ));
    await tester.pump();
    expect(find.text('Designer 2'), findsOneWidget);
  });
}
