import 'package:fazoura_party/core/time/lock_in_timer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The timing both the app's auto-submit and the CLI's bots answer with.
/// Driven by a fake clock inside a widget test's fake-async zone, so timers
/// only fire when the test moves time.
void main() {
  const start = 1789502400000;
  late int now;
  late List<int> fired;

  LockInTimer timer() =>
      LockInTimer(onDue: () => fired.add(now), localNowMs: () => now);

  // In small steps, so the clock a timer reads when it fires is the moment it
  // was due, not the end of the whole advance.
  Future<void> advance(WidgetTester tester, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left < 50 ? left : 50;
      now += step;
      left -= step;
      await tester.pump(Duration(milliseconds: step));
    }
  }

  setUp(() {
    now = start;
    fired = [];
  });

  testWidgets('fires the lead before the deadline, by the server clock', (
    tester,
  ) async {
    // The server is 2 s ahead of this device.
    final lockIn = timer()..arm(deadline: start + 12000, offsetMs: 2000);

    await advance(tester, 10000 - lockInLead.inMilliseconds - 1);
    expect(fired, isEmpty);
    await advance(tester, 1);
    expect(fired, [start + 10000 - lockInLead.inMilliseconds]);
    expect(lockIn.isArmed, isFalse);
  });

  testWidgets('fires when preferred, if that is earlier', (tester) async {
    timer().arm(
      deadline: start + 30000,
      offsetMs: 0,
      preferredAtLocalMs: start + 2000,
    );
    await advance(tester, 2000);
    expect(fired, [start + 2000]);
  });

  testWidgets('moves forward when the host ends the question early', (
    tester,
  ) async {
    final lockIn = timer()
      ..arm(
        deadline: start + 30000,
        offsetMs: 0,
        preferredAtLocalMs: start + 20000,
      );
    await advance(tester, 1000);

    // The closing window: 3 s from now (PROTOCOL.md §6).
    lockIn.arm(
      deadline: now + 3000,
      offsetMs: 0,
      preferredAtLocalMs: start + 20000,
    );
    await advance(tester, 3000 - lockInLead.inMilliseconds);
    expect(fired, [start + 1000 + 3000 - lockInLead.inMilliseconds]);
  });

  testWidgets('a pause disarms it and the resume arms it again', (
    tester,
  ) async {
    final lockIn = timer()..arm(deadline: start + 10000, offsetMs: 0);
    lockIn.arm(deadline: null, offsetMs: 0);
    expect(lockIn.isArmed, isFalse);
    await advance(tester, 20000);
    expect(fired, isEmpty);

    lockIn.arm(deadline: now + 5000, offsetMs: 0);
    await advance(tester, 5000);
    expect(fired, hasLength(1));
  });

  testWidgets('re-arming for the same moment keeps the timer it has', (
    tester,
  ) async {
    final lockIn = timer()..arm(deadline: start + 10000, offsetMs: 0);
    for (var i = 0; i < 5; i++) {
      lockIn.arm(deadline: start + 10000, offsetMs: 0);
    }
    await advance(tester, 10000);
    expect(fired, hasLength(1), reason: 'one send, not five');
  });

  testWidgets('never fires once the deadline has passed', (tester) async {
    timer().arm(deadline: start - 1, offsetMs: 0);
    await advance(tester, 1000);
    expect(fired, isEmpty);
  });
}
