import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:signtech_file_sharing/services/window_size.dart';

void main() {
  test('printer roles open wide, designer stays portrait', () {
    expect(windowSizeForRole('yjet'), const Size(800, 650));
    expect(windowSizeForRole('challenger'), const Size(800, 650));
    expect(windowSizeForRole('designer'), const Size(430, 740));
    expect(windowSizeForRole(null), const Size(430, 740));
    expect(windowSizeForRole('something-else'), const Size(430, 740));
  });
}
