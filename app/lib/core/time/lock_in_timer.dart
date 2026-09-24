import 'dart:async';
import 'dart:math' as math;

import 'server_clock.dart';

/// How far before the deadline an answer must leave to be sure it lands.
///
/// The host refuses a submission that reaches it at or after the deadline
/// (PROTOCOL.md §4.2) — there is no grace window, deliberately, since one
/// would only be a longer deadline the countdown lies about — so the send
/// needs room for a round trip. 700 ms covers a phone's, and costs less than
/// the last second, which the countdown does not even render differently.
const lockInLead = Duration(milliseconds: 700);

/// Sends an answer in time: at a moment the caller prefers, or at the latest
/// moment it can still reach the host, whichever comes first.
///
/// The app's question screen uses it to send what somebody typed but did not
/// lock in before time runs out; `tools/fazoura-cli`'s bots use it to answer
/// after a pause for thought. One implementation, so testing the bots tests
/// the app's timing.
///
/// The deadline is the server's, so it is read through the server clock offset
/// (§5.1). It can move under a pending send: a pause takes it away, the resume
/// brings a new one, and the host ending the question pulls it in to the
/// closing window (§6). Every snapshot therefore re-arms, and a send already
/// due early enough is left alone. A timer that fires late — a backgrounded
/// tab throttles them — is checked against the clock again, and does nothing
/// once the deadline has passed.
class LockInTimer {
  LockInTimer({
    required this.onDue,
    int Function()? localNowMs,
    this.lead = lockInLead,
  }) : _localNowMs =
           localNowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// What to do when the send is due.
  final void Function() onDue;
  final int Function() _localNowMs;
  final Duration lead;

  Timer? _timer;
  int? _dueAt;

  /// Whether a send is scheduled.
  bool get isArmed => _timer != null;

  /// Schedules the send for [deadline] (server milliseconds), [offsetMs] being
  /// `server_time - local_now`. With [preferredAtLocalMs] it fires then if that
  /// is earlier than the latest safe moment. A null [deadline] — paused, or no
  /// question — disarms.
  void arm({
    required int? deadline,
    required int offsetMs,
    int? preferredAtLocalMs,
  }) {
    if (deadline == null) return disarm();
    final now = _localNowMs();
    final left = remainingMs(
      deadline: deadline,
      offsetMs: offsetMs,
      localNowMs: now,
    );
    if (left <= 0) return disarm();

    final latest = now + math.max<int>(0, left - lead.inMilliseconds);
    final preferred = preferredAtLocalMs;
    final int dueAt = preferred == null
        ? latest
        : math.min<int>(latest, math.max<int>(now, preferred));
    if (_timer != null && _dueAt == dueAt) return;

    disarm();
    _dueAt = dueAt;
    _timer = Timer(Duration(milliseconds: dueAt - now), () {
      _timer = null;
      _dueAt = null;
      final stillInTime =
          remainingMs(
            deadline: deadline,
            offsetMs: offsetMs,
            localNowMs: _localNowMs(),
          ) >
          0;
      if (stillInTime) onDue();
    });
  }

  void disarm() {
    _timer?.cancel();
    _timer = null;
    _dueAt = null;
  }
}
