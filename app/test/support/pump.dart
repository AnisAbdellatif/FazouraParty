import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps frames until the screen has caught up with itself.
///
/// [WidgetTester.pumpAndSettle] cannot be used on these screens: the app's own
/// motion includes animations that repeat for as long as they are on screen
/// (`FzBlink`), so settling never arrives and the call times out instead.
///
/// Four test files worked around that with their own loop, each having picked a
/// different pair of numbers — 5×200ms, 6×200ms, 6×150ms, 8×150ms — none of
/// which meant anything beyond "enough when it was written". One budget,
/// generous enough for the slowest of them, is both fewer magic numbers and
/// less likely to be the reason a test fails on a loaded machine.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Scrolls a keyed widget into view, taps it, and lets the screen catch up.
Future<void> tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}
