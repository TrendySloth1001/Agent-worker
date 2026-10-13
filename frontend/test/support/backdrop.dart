import 'package:flutter_test/flutter_test.dart';

/// Pumps past the page backdrop's opening wave and ambient breathing until it
/// has come to rest, so a golden captures the settled grid (deterministic).
Future<void> settleBackdrop(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
