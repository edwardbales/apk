import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/theme.dart';

void main() {
  testWidgets('dark theme is dark, light theme is light, Team Drive blue kept',
      (tester) async {
    // The Team Drive screenshot font — Poppins in both themes.
    // (ThemeData carries the family on its text styles.)
    expect(SigntechTheme.dark.textTheme.bodyMedium?.fontFamily,
        'Poppins');
    expect(SigntechTheme.light.textTheme.bodyMedium?.fontFamily,
        'Poppins');
    expect(SigntechTheme.dark.brightness, Brightness.dark);
    expect(SigntechTheme.light.brightness, Brightness.light);
    expect(SigntechTheme.dark.colorScheme.primary, SigntechTheme.brandBlueDark);
    expect(SigntechTheme.light.colorScheme.primary, SigntechTheme.brandBlue);
    expect(SigntechTheme.dark.scaffoldBackgroundColor,
        const Color(0xFF0F0F12));
    expect(SigntechTheme.light.scaffoldBackgroundColor,
        const Color(0xFFF7F7F9));

    // Both themes actually render a screen without errors.
    for (final theme in [SigntechTheme.dark, SigntechTheme.light]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: AppBar(title: const Text('Signtech File Sharing')),
          body: Card(
            child: ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Human Y-Jet'),
              subtitle: Text('Test',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Signtech File Sharing'), findsOneWidget);
      expect(find.text('Human Y-Jet'), findsOneWidget);
    }
  });
}
