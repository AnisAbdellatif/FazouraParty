import 'package:fazoura_party/core/time/server_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('server clock', () {
    test('offset is server_time - local_now', () {
      expect(clockOffsetMs(serverTime: 10000, localNowMs: 7000), 3000);
      expect(clockOffsetMs(serverTime: 7000, localNowMs: 10000), -3000);
    });

    test('remaining time uses deadline - (local_now + offset)', () {
      // Spec example: server_time 1789502400000, deadline +30 s.
      const serverTime = 1789502400000;
      const deadline = 1789502430000;
      // Local clock is 5 s behind the server.
      const localAtReceipt = serverTime - 5000;
      final offset = clockOffsetMs(
        serverTime: serverTime,
        localNowMs: localAtReceipt,
      );

      expect(
        remainingMs(
          deadline: deadline,
          offsetMs: offset,
          localNowMs: localAtReceipt,
        ),
        30000,
      );
      expect(
        remainingMs(
          deadline: deadline,
          offsetMs: offset,
          localNowMs: localAtReceipt + 12000,
        ),
        18000,
      );
    });

    test('remaining time is clamped at zero after the deadline', () {
      expect(remainingMs(deadline: 1000, offsetMs: 0, localNowMs: 5000), 0);
    });

    test('a local clock ahead of the server does not shorten the timer', () {
      const serverTime = 50000;
      const localAtReceipt = 90000; // 40 s ahead
      final offset = clockOffsetMs(
        serverTime: serverTime,
        localNowMs: localAtReceipt,
      );
      expect(
        remainingMs(
          deadline: serverTime + 20000,
          offsetMs: offset,
          localNowMs: localAtReceipt + 1000,
        ),
        19000,
      );
    });
  });
}
