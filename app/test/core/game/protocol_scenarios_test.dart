/// Replays every `protocol/fixtures/scenarios/*.json` script against the LAN
/// host, exactly as `FazouraWeb.ProtocolScenariosTest` replays them against
/// Phoenix (PROTOCOL.md §11).
///
/// This is what holds the Dart port of the game rules to the Elixir one. The
/// two implementations share no code and never will — a LAN host has no
/// Elixir — so the fixtures are the only thing that can catch them drifting
/// apart (AGENTS.md §3, §8).
///
/// The scripts are replayed against [LanRoom] rather than through a socket:
/// the room is the whole of the contract's behaviour, and a fake connection
/// per actor gives the per-recipient snapshots the scenarios assert on.
/// `lan_host_test.dart` covers the socket layer above it.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:fazoura_party/core/game/game.dart';
import 'package:fazoura_party/core/game/lan_room.dart';
import 'package:fazoura_party/core/game/pack.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/protocol_fixtures.dart';

/// The clock every scenario starts at, matching the Elixir runner — the
/// fixtures assert on absolute deadlines computed from it.
const _clockStart = 1789502400000;

void main() {
  for (final entry in ProtocolFixtures.scenarios()) {
    test('scenario ${entry.name}: ${entry.scenario['name']}', () {
      _ScenarioRun(entry.scenario).run();
    });
  }
}

class _ScenarioRun {
  _ScenarioRun(this.scenario);

  final Map<String, dynamic> scenario;
  final Map<String, _FakeConnection> actors = {};
  final Map<String, Object?> vars = {};

  int clock = _clockStart;
  late final LanRoom room = LanRoom.create(
    pack: Pack.fromMap(scenario['pack'] as Map<String, dynamic>),
    now: () => clock,
    // The scripts name the question they expect next, so the pack has to be
    // played in its written order — `shuffle_questions?: false` on the server.
    shuffleQuestions: false,
  );

  void run() {
    vars[r'$host_token'] = room.hostToken;
    try {
      final steps = scenario['steps'] as List;
      for (final (index, step) in steps.indexed) {
        _step(
          step as Map<String, dynamic>,
          'step ${index + 1}: ${jsonEncode(step)}',
        );
      }
    } finally {
      room.close(LanCloseReason.shutdown);
    }
  }

  void _step(Map<String, dynamic> step, String label) {
    if (step['advance_clock_ms'] case final int ms) {
      clock += ms;
      // The room's own timer cannot fire against an injected clock, so the
      // runner advances it by hand — what `Rooms.tick/1` is for on the server.
      room.tick();
      return;
    }

    final name = step['actor'] as String;

    if (step['join'] != null) {
      _join(name, step, label);
      return;
    }
    if (step['push'] case final String event) {
      final reply = _reply(() {
        room.handle(
          _actor(name, label),
          event,
          _substitute(step['payload']) as Map<String, dynamic>? ?? {},
        );
        return null;
      });
      _expectMatches(_substitute(step['expect']), reply, label);
      return;
    }
    if (step['expect_state'] != null) {
      _expectMatches(
        _substitute(step['expect_state']),
        _actor(name, label).latestState,
        label,
      );
      return;
    }
    if (step['expect_closed'] case final String reason) {
      expect(_actor(name, label).closedReason, reason, reason: label);
      return;
    }
    if (step['disconnect'] == true) {
      room.leave(_actor(name, label));
      actors.remove(name);
      return;
    }
    fail('$label: unknown step');
  }

  void _join(String name, Map<String, dynamic> step, String label) {
    final connection = _FakeConnection();
    LanJoinReply? joined;

    final reply = _reply(() {
      joined = room.join(
        connection,
        _substitute(step['join']) as Map<String, dynamic>,
      );
      return {
        'role': joined!.role,
        'player_id': joined!.playerId,
        'player_token': joined!.playerToken,
      };
    });

    _expectMatches(_substitute(step['expect']), reply, label);

    final result = joined;
    if (result == null) return;
    actors[name] = connection;
    if (result.playerId != null) {
      vars[r'$player_id:' + name] = result.playerId;
      vars[r'$player_token:' + name] = result.playerToken;
    }
  }

  /// Runs an intent and shapes the outcome like a `phx_reply` payload, which
  /// is what the fixtures' `expect` blocks describe (§4.2).
  Map<String, dynamic> _reply(Map<String, dynamic>? Function() intent) {
    try {
      return _wire({'status': 'ok', 'response': intent() ?? {}});
    } on GameRuleError catch (error) {
      return _wire({
        'status': 'error',
        'response': {'code': error.code, 'message': 'ignored'},
      });
    }
  }

  _FakeConnection _actor(String name, String label) =>
      actors[name] ?? (fail('$label: unknown actor $name'));

  /// Substitutes the `$host_token`, `$player_id:<actor>` and
  /// `$player_token:<actor>` placeholders (§11).
  Object? _substitute(Object? value) => switch (value) {
    String() => vars.containsKey(value) ? vars[value] : value,
    Map() => {
      for (final entry in value.entries)
        entry.key as String: _substitute(entry.value),
    },
    List() => [for (final item in value) _substitute(item)],
    _ => value,
  };

  void _expectMatches(Object? expected, Object? actual, String label) {
    expect(
      _matches(expected, actual),
      isTrue,
      reason: '$label\nexpected:\n$expected\ngot:\n$actual',
    );
  }

  /// Partial match, the same rule the server's runner uses (§11): every key
  /// present in `expected` must be present and equal, keys it omits are
  /// unchecked, and lists must be the same length element for element.
  static bool _matches(Object? expected, Object? actual) {
    if (expected is Map && actual is Map) {
      return expected.entries.every(
        (entry) =>
            actual.containsKey(entry.key) &&
            _matches(entry.value, actual[entry.key]),
      );
    }
    if (expected is List && actual is List) {
      return expected.length == actual.length &&
          List.generate(
            expected.length,
            (i) => _matches(expected[i], actual[i]),
          ).every((matched) => matched);
    }
    return expected == actual;
  }
}

/// Round-trips through JSON so assertions see exactly what goes over the wire,
/// and so a value the snapshot cannot encode fails here rather than on a
/// socket.
Map<String, dynamic> _wire(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// One client, from the room's point of view.
class _FakeConnection implements LanConnection {
  Map<String, dynamic>? latestState;
  String? closedReason;

  @override
  void pushState(Map<String, dynamic> state) => latestState = _wire(state);

  @override
  void pushClosed(String reason) => closedReason = reason;
}
