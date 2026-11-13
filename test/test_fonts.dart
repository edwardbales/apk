import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real Poppins fonts the app bundles, so widget tests
/// measure the layout the user actually sees. Without this, tests
/// fall back to Ahem (every glyph one full em wide), which makes
/// text wrap and overflow where the real app fits fine.
Future<void> loadPoppins() async {
  final loader = FontLoader('Poppins');
  for (final path in [
    'assets/fonts/Poppins-Regular.ttf',
    'assets/fonts/Poppins-Medium.ttf',
    'assets/fonts/Poppins-SemiBold.ttf',
    'assets/fonts/Poppins-Bold.ttf',
  ]) {
    loader.addFont(rootBundle.load(path));
  }
  await loader.load();
}
