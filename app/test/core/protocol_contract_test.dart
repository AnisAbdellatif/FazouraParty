@TestOn('vm')
library;

import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/connection/phoenix_game_connection.dart';
import 'package:fazoura_party/core/game/game.dart'
    show protocolMajor, protocolMinor;
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/shared/describe_error.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/protocol_fixtures.dart';

/// Holds the client to the shared contract in `protocol/fixtures/`, the same
/// files `FazouraWeb.ProtocolScenariosTest` replays against the server
/// (AGENTS.md §8, PROTOCOL.md §11).
///
/// The server owns the game rules, so the client cannot be replayed step by
/// step against a scenario the way a host implementation can. What it *can* be
/// held to is everything the fixtures say about the wire: that it decodes every
/// `state` snapshot the scenarios expect, encodes every intent they push, and
/// has a human-readable message for every error code they produce. Those are
/// precisely the places where a hand-copied fixture would drift unnoticed.
void main() {
  // The cloud client and the LAN engine each write their own major — the
  // client so it carries no dependency on the engine. They have to agree, or a
  // LAN host would refuse the very client shipped beside it (PROTOCOL.md §1.1).
  test('the client and the LAN host claim the same protocol major', () {
    expect(PhoenixGameConnection.protocolMajor, protocolMajor);
  });

  group('scenarios/*.json decode into RoomState (PROTOCOL.md §5.1)', () {
    for (final entry in ProtocolFixtures.scenarios()) {
      test('${entry.name}: ${entry.scenario['name']}', () {
        final steps = (entry.scenario['steps'] as List).cast<Object?>();
        var checked = 0;

        for (final step in steps) {
          final map = step as Map<String, dynamic>;
          final expected = map['expect_state'] as Map<String, dynamic>?;
          if (expected == null) continue;

          // A scenario's expect_state is a partial snapshot (§11), so complete
          // it with the spec's example before decoding: a partial map is not a
          // legal RoomState and the client never receives one.
          final state = RoomState.fromJson(
            _completeSnapshot(_substitute(expected)),
          );
          _assertRoundTrips(state, _substitute(expected), entry.name);
          checked++;
        }

        expect(
          checked,
          greaterThan(0),
          reason: '${entry.name} has no expect_state steps to verify',
        );
      });
    }
  });

  group('scenarios/*.json intents encode to the pushed payloads (§4.2)', () {
    test('every pushed event and payload is one the client can produce', () {
      final seen = <String>{};

      for (final entry in ProtocolFixtures.scenarios()) {
        for (final step in (entry.scenario['steps'] as List)) {
          final map = step as Map<String, dynamic>;
          final event = map['push'] as String?;
          if (event == null) continue;
          seen.add(event);

          final payload = (map['payload'] as Map<String, dynamic>?) ?? const {};
          final built = _encodeIntent(event, payload);
          if (built == null) continue; // deliberately malformed fixture payload

          expect(
            built,
            payload,
            reason:
                '${entry.name}: client encoding of "$event" differs from the '
                'fixture payload',
          );
        }
      }

      // Guards against a scenario gaining an intent the client cannot send.
      expect(seen, {
        'submit',
        'host_next',
        'host_pause',
        'host_resume',
        'host_override',
        'host_configure',
        'host_select_quiz',
        'host_rematch',
      });
    });

    test('join payloads carry the protocol version the fixtures join with', () {
      for (final entry in ProtocolFixtures.scenarios()) {
        for (final step in (entry.scenario['steps'] as List)) {
          final join = (step as Map<String, dynamic>)['join'];
          if (join is! Map<String, dynamic>) continue;
          if (join['protocol_version'] == _unsupportedVersion) continue;

          expect(
            join['protocol_version'],
            PhoenixGameConnection.protocolMajor,
            reason:
                '${entry.name} joins with protocol_version '
                '${join['protocol_version']}, the client sends '
                '${PhoenixGameConnection.protocolMajor}',
          );
        }
      }
    });
  });

  test('every error code in the scenarios has a message (§4)', () {
    final codes = <String>{};
    for (final entry in ProtocolFixtures.scenarios()) {
      for (final step in (entry.scenario['steps'] as List)) {
        final expect_ = (step as Map<String, dynamic>)['expect'];
        if (expect_ is! Map<String, dynamic>) continue;
        final response = expect_['response'];
        if (response is! Map<String, dynamic>) continue;
        final code = response['code'];
        if (code is String) codes.add(code);
      }
    }

    expect(codes, isNotEmpty);
    for (final code in codes) {
      // describeError's fallback is the only branch that embeds the raw code,
      // so reproducing it here identifies an unhandled code exactly — matching
      // on the code alone would also flag "paused", whose real message
      // legitimately contains the word.
      final fallback = 'Something went wrong ($code).';
      expect(
        describeError(GameError(code: code)),
        isNot(fallback),
        reason:
            'error code "$code" appears in the fixtures but describeError '
            'falls through to its generic text',
      );
    }
  });

  group('scoring.json (PROTOCOL.md §9)', () {
    final scoring = ProtocolFixtures.load('scoring.json');

    test('a Question carries the stakes the host sent, and computes none', () {
      for (final case_ in (scoring['points'] as List)) {
        final map = case_ as Map<String, dynamic>;
        final points = map['points'] as Map<String, dynamic>;

        final question = Question.fromJson({
          'id': 'q_1',
          'type': 'text',
          'prompt': '?',
          'time_limit_ms': 30000,
          'difficulty': map['difficulty'],
          'points': points,
        });

        expect(
          (
            question.points.right,
            question.points.wrong,
            question.points.skipped,
          ),
          (points['right'], points['wrong'], points['skipped']),
          reason:
              'the ${map['difficulty']} stakes are the host\'s to state, and '
              'this is the whole of what the client knows about scoring',
        );
      }
    });

    test('a skipped row decodes as an answerless row, not a missing one', () {
      for (final case_ in (scoring['skipped'] as List)) {
        final map = case_ as Map<String, dynamic>;

        final view = SubmissionView.fromJson({
          'player_id': 'p_1',
          'answer': null,
          'auto_correct': false,
          'override': null,
          'correct': false,
          'delta': map['delta'],
        });

        expect(view.answer, isNull, reason: map['name'] as String);
        expect(view.correct, isFalse);
        expect(view.delta, map['delta']);
      }
    });

    test('a SubmissionView decodes the override cases it will be sent', () {
      for (final case_ in (scoring['override'] as List)) {
        final map = case_ as Map<String, dynamic>;
        final overridden = map['override'] as bool;
        final delta =
            (map['score_after_override'] as int) -
            (map['score_before_question'] as int);

        final view = SubmissionView.fromJson({
          'player_id': 'p_1',
          'answer': 'whatever',
          'auto_correct': map['auto_correct'],
          'override': overridden,
          'correct': overridden,
          'delta': delta,
        });

        expect(view.overrideVerdict, overridden, reason: map['name'] as String);
        expect(view.correct, overridden);
        expect(
          view.delta,
          delta,
          reason: '${map['name']}: delta must be the score change it caused',
        );
      }
    });
  });

  test('normalize.json match cases belong to whoever is hosting (§8)', () {
    // Matching is host-authoritative (AGENTS.md §4), so nothing in the *client*
    // decides it and there is nothing to assert here beyond the fixture being
    // present. The LAN host does match, because it is a host: those cases are
    // replayed in `core/game/answer_test.dart`.
    final normalize = ProtocolFixtures.load('normalize.json');
    expect(normalize['normalize'], isNotEmpty);
    expect(normalize['match'], isNotEmpty);
  });
}

const _unsupportedVersion = 3;

/// Substitutes the `"$player_id:<actor>"` placeholders (§11). The client test
/// never learns real ids, so a stable fake per actor is enough to decode.
Object? _substitute(Object? value) {
  if (value is String) {
    return value.startsWith(r'$player_id:')
        ? 'p_${value.substring(r'$player_id:'.length)}'
        : value;
  }
  if (value is List) return value.map(_substitute).toList();
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: _substitute(entry.value),
    };
  }
  return value;
}

/// Fills a partial `expect_state` out to a complete snapshot, keeping every key
/// the fixture specified.
Map<String, dynamic> _completeSnapshot(Object? partial) {
  final expected = (partial as Map).cast<String, dynamic>();
  final players = expected['players'] as List?;

  return <String, dynamic>{
    'protocol_version': PhoenixGameConnection.protocolMajor,
    'protocol_minor': protocolMinor,
    'room_code': 'K7QX2M',
    'mode': 'cloud',
    'phase': 'lobby',
    'server_time': 1789502400000,
    'pack_titles': ['Fixture Pack'],
    'question_count': 1,
    ...expected,
    // players/you entries in a fixture are themselves partial. `you` is always
    // written: _completeYou supplies the defaults when the fixture omits it.
    if (players != null)
      'players': [for (final player in players) _completePlayer(player as Map)],
    'you': _completeYou(expected['you'] as Map?),
    if (expected['question'] != null)
      'question': _completeQuestion(expected['question'] as Map),
    if (expected['settings'] != null)
      'settings': _completeSettings(expected['settings'] as Map),
    if (expected['submissions'] != null)
      'submissions': [
        for (final submission in expected['submissions'] as List)
          _completeSubmission(submission as Map),
      ],
  };
}

Map<String, dynamic> _completePlayer(Map partial) => <String, dynamic>{
  'id': 'p_${partial['name'] ?? 'x'}',
  'name': 'Player',
  'score': 0,
  'connected': true,
  'has_submitted': false,
  ...partial.cast<String, dynamic>(),
};

Map<String, dynamic> _completeYou(Map? partial) => <String, dynamic>{
  'role': 'player',
  'player_id': 'p_sam',
  ...?partial?.cast<String, dynamic>(),
  if (partial?['submission'] != null)
    'submission': <String, dynamic>{
      'answer': 'answer',
      'wager': 1,
      ...(partial!['submission'] as Map).cast<String, dynamic>(),
    },
};

Map<String, dynamic> _completeQuestion(Map partial) => <String, dynamic>{
  'id': 'q1',
  'type': 'text',
  'prompt': 'Prompt?',
  'time_limit_ms': 30000,
  ...partial.cast<String, dynamic>(),
};

Map<String, dynamic> _completeSettings(Map partial) => <String, dynamic>{
  'question_count': 1,
  'time_limit_ms': 30000,
  'max_question_count': 1,
  ...partial.cast<String, dynamic>(),
};

Map<String, dynamic> _completeSubmission(Map partial) => <String, dynamic>{
  'player_id': 'p_sam',
  'answer': 'answer',
  'wager': 1,
  ...partial.cast<String, dynamic>(),
};

/// Re-encodes [state] and asserts every key the fixture pinned survived the
/// round trip, so a renamed or dropped `@JsonKey` fails here.
void _assertRoundTrips(RoomState state, Object? expected, String label) {
  final encoded = state.toJson();
  _assertMatches(expected, encoded, label);
}

void _assertMatches(Object? expected, Object? actual, String label) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: '$label: expected an object');
    final actualMap = (actual as Map).cast<String, dynamic>();
    for (final entry in expected.entries) {
      final key = entry.key as String;
      expect(
        actualMap.containsKey(key),
        isTrue,
        reason: '$label: RoomState JSON is missing "$key"',
      );
      _assertMatches(entry.value, actualMap[key], '$label.$key');
    }
    return;
  }
  if (expected is List) {
    expect(actual, isA<List>(), reason: '$label: expected a list');
    final actualList = actual as List;
    expect(actualList, hasLength(expected.length), reason: label);
    for (var i = 0; i < expected.length; i++) {
      _assertMatches(expected[i], actualList[i], '$label[$i]');
    }
    return;
  }
  expect(actual, expected, reason: label);
}

/// The client's encoding of a pushed intent, or null when the fixture payload
/// is deliberately malformed (those cases exist to assert a server rejection,
/// and the typed client API cannot express them).
Map<String, dynamic>? _encodeIntent(
  String event,
  Map<String, dynamic> payload,
) {
  switch (event) {
    case 'submit':
      final answer = payload['answer'];
      if (answer is! String) return null;
      return PhoenixGameConnection.submitPayload(answer);
    case 'host_override':
      return PhoenixGameConnection.overridePayload(
        payload['player_id'] as String,
        payload['correct'] as bool,
      );
    case 'host_configure':
      final multiplier = payload['difficulty_multiplier'];
      if (multiplier is! bool) return null;
      return PhoenixGameConnection.configurePayload(
        questionCount: payload['question_count'] as int,
        timeLimitMs: payload['time_limit_ms'] as int,
        difficultyMultiplier: multiplier,
        difficulties: (payload['difficulties'] as List).cast<String>(),
      );
    case 'host_select_quiz':
      final entries = payload['quizzes'] as List;
      // A fixture entry naming a stored quiz is rebuilt exactly; one carrying
      // a document is not, because the fixtures use a minimal custom document
      // and production adds its canonical inline-room fields before sending.
      if (entries.any((entry) => (entry as Map)['quiz_id'] is! String)) {
        return null;
      }
      return PhoenixGameConnection.selectQuizPayload([
        for (final entry in entries)
          StoredQuizSelection((entry as Map)['quiz_id'] as String),
      ]);
    case 'host_next':
    case 'host_pause':
    case 'host_resume':
    case 'host_rematch':
      return const {};
    default:
      return null;
  }
}
