import 'dart:math' as math;

/// Returns `server_time - local_now` (PROTOCOL.md §5.1), measured when the
/// snapshot is received.
int clockOffsetMs({required int serverTime, required int localNowMs}) =>
    serverTime - localNowMs;

/// Remaining time until the server [deadline]:
/// `deadline - (local_now + offset)`, clamped at zero.
///
/// Timers are always rendered from the absolute deadline, never from a local
/// countdown.
int remainingMs({
  required int deadline,
  required int offsetMs,
  required int localNowMs,
}) => math.max(0, deadline - (localNowMs + offsetMs));
