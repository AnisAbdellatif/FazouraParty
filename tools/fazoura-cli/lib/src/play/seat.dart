import 'dart:async';

import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';

import '../context.dart';
import 'narrator.dart' as narrator;

/// One connection to one room — a host or a player — and what it has seen.
///
/// Several seats can share a process (`fazoura join --count 5`); each has its
/// own socket, exactly as if it were a separate phone.
class Seat {
  Seat({
    required this.label,
    required this.connection,
    required this.output,
    this.narrate = true,
  });

  /// How this seat is named in output: the display name, or `host`.
  final String label;
  final GameConnection connection;
  final Output output;

  /// Whether to tell the room's story in text. Several bots in one process
  /// share one room, so only the first does; the rest print what they did
  /// themselves. JSON output always carries every seat's snapshots.
  final bool narrate;

  RoomState? _state;
  bool _roomClosed = false;
  final _updates = StreamController<RoomState>.broadcast(sync: true);
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Server clock minus this machine's, from the latest snapshot's
  /// `server_time` (PROTOCOL.md §5.1). Deadlines are the server's, so this is
  /// what turns one into "how long from now".
  int _offsetMs = 0;

  RoomState? get state => _state;
  Stream<RoomState> get updates => _updates.stream;
  Future<RoomClosedReason> get closed => connection.closed;

  /// Milliseconds until [deadline] by the server's clock.
  int remainingMs(int deadline) =>
      deadline - (DateTime.now().millisecondsSinceEpoch + _offsetMs);

  /// Starts printing what happens. Call before joining, so the first snapshot
  /// is not missed.
  void watch() {
    unawaited(connection.closed.then((_) => _roomClosed = true));
    _subscriptions
      ..add(connection.state.listen(_onState))
      ..add(
        connection.status.listen((status) {
          if (status == ConnectionStatus.reconnecting) {
            _say('connection', {'status': status.name}, 'reconnecting…');
          }
        }),
      );
    if (!narrate) return;
    unawaited(
      connection.closed.then(
        (reason) => _say('closed', {
          'reason': reason.name,
        }, 'room closed (${reason.name})'),
      ),
    );
  }

  void _onState(RoomState state) {
    final before = _state;
    _state = state;
    _offsetMs = state.serverTime - DateTime.now().millisecondsSinceEpoch;
    if (output.json) {
      output.event('state', {'seat': label, 'state': state.toJson()}, null);
    } else if (narrate) {
      for (final line in narrator.narrate(before, state)) {
        output.say('[$label] $line');
      }
    }
    _updates.add(state);
  }

  void _say(String event, Map<String, Object?> fields, String human) =>
      output.event(event, {'seat': label, ...fields}, '[$label] $human');

  /// Prints an event on behalf of this seat.
  void note(String event, Map<String, Object?> fields, String human) =>
      _say(event, fields, human);

  /// The player a person meant by [nameOrId]: an exact id, else a name,
  /// ignoring case.
  PlayerSummary? findPlayer(String nameOrId) {
    final players = _state?.players ?? const <PlayerSummary>[];
    for (final player in players) {
      if (player.id == nameOrId) return player;
    }
    final wanted = nameOrId.toLowerCase();
    for (final player in players) {
      if (player.name.toLowerCase() == wanted) return player;
    }
    return null;
  }

  /// Runs [intent] and reports a refusal instead of throwing: one bad command
  /// should not end a session.
  Future<bool> send(String what, Future<void> Function() intent) async {
    try {
      await intent();
      return true;
    } on GameError catch (error) {
      if (what == 'close' && await _closesSoon()) return true;
      _say('refused', {
        'intent': what,
        'code': error.code,
        'message': error.message,
      }, '$what refused: ${error.message ?? error.code}');
      return false;
    } on Object catch (error) {
      // Closing the room drops the socket before the reply to the intent
      // that closed it can arrive; that is the intent working.
      if (_roomClosed || (what == 'close' && await _closesSoon())) return true;
      _say('failed', {
        'intent': what,
        'message': '$error',
      }, '$what failed: $error');
      return false;
    }
  }

  /// Closing the room drops the socket, often before the reply to the intent
  /// that closed it can arrive — so a lost reply to `close` is success if the
  /// room does go.
  Future<bool> _closesSoon() => connection.closed
      .then((_) => true)
      .timeout(const Duration(seconds: 3), onTimeout: () => false);

  Future<void> leave() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await connection.leave();
    } on Object {
      // Leaving a room that is already gone is still leaving it.
    }
    await _updates.close();
  }
}
