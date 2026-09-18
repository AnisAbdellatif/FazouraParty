import 'dart:convert';

import 'package:fazoura_party/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

void main() {
  group('RoomState JSON (PROTOCOL.md §5.1)', () {
    final json = jsonDecode(roomStateExampleJson) as Map<String, dynamic>;

    test('parses the spec example', () {
      final state = RoomState.fromJson(json);

      expect(state.protocolVersion, 7);
      expect(state.roomCode, 'K7QX2M');
      expect(state.mode, Mode.cloud);
      expect(state.phase, Phase.question);
      expect(state.serverTime, 1789502400000);
      expect(state.packTitle, 'General Knowledge');
      expect(state.questionIndex, 2);
      expect(state.questionCount, 10);
      expect(
        state.question,
        const Question(
          id: 'q_03',
          type: QuestionType.text,
          prompt: 'What is the capital of Australia?',
          timeLimitMs: 30000,
        ),
      );
      expect(state.deadline, 1789502430000);
      expect(state.pausedRemainingMs, isNull);
      expect(state.acceptedAnswers, isNull);
      expect(state.players, const [
        PlayerSummary(
          id: 'p_3f9a',
          name: 'Sam',
          score: 12,
          connected: true,
          hasSubmitted: true,
          avatarHue: 212,
        ),
      ]);
      expect(
        state.you,
        const You(
          role: Role.player,
          playerId: 'p_3f9a',
          submission: OwnSubmission(answer: 'Canberra', wager: 7),
        ),
      );
      expect(state.submissions, isNull);
    });

    test('round-trips to the identical JSON', () {
      final state = RoomState.fromJson(json);
      final encoded = jsonDecode(jsonEncode(state.toJson()));

      expect(encoded, json);
      expect(RoomState.fromJson(encoded as Map<String, dynamic>), state);
    });

    test('ignores unknown keys and treats absent optionals as null', () {
      final withExtras = Map<String, dynamic>.from(json)
        ..['future_field'] = {'x': 1}
        ..remove('paused_remaining_ms')
        ..remove('submissions');
      (withExtras['you'] as Map<String, dynamic>)['extra'] = true;

      final state = RoomState.fromJson(withExtras);
      expect(state.pausedRemainingMs, isNull);
      expect(state.submissions, isNull);
      expect(state, RoomState.fromJson(json));
    });
  });

  test('SubmissionView parses and round-trips the spec example', () {
    final json = jsonDecode(submissionExampleJson) as Map<String, dynamic>;
    final view = SubmissionView.fromJson(json);

    expect(
      view,
      const SubmissionView(
        playerId: 'p_3f9a',
        answer: 'canbera',
        wager: 7,
        autoCorrect: false,
        overrideVerdict: true,
        correct: true,
        delta: 7,
      ),
    );
    expect(view.toJson(), json);
  });

  test('PlayerSummary parses is_host (v2) and defaults it to false', () {
    final host = PlayerSummary.fromJson({
      'id': 'p_host',
      'name': 'Hana',
      'score': 0,
      'connected': true,
      'has_submitted': false,
      'is_host': true,
    });
    expect(host.isHost, isTrue);
    expect(host.toJson()['is_host'], true);

    final legacy = PlayerSummary.fromJson({
      'id': 'p_3f9a',
      'name': 'Sam',
      'score': 0,
      'connected': true,
      'has_submitted': false,
    });
    expect(legacy.isHost, isFalse);
  });

  test('JoinResult parses a playing host reply', () {
    expect(
      JoinResult.fromJson({
        'role': 'host',
        'player_id': 'p_host',
        'player_token': null,
      }),
      const JoinResult(role: Role.host, playerId: 'p_host'),
    );
  });

  test('JoinResult parses player and host replies', () {
    expect(
      JoinResult.fromJson({
        'role': 'player',
        'player_id': 'p_3f9a',
        'player_token': 'tok',
      }),
      const JoinResult(
        role: Role.player,
        playerId: 'p_3f9a',
        playerToken: 'tok',
      ),
    );
    expect(
      JoinResult.fromJson({
        'role': 'host',
        'player_id': null,
        'player_token': null,
      }),
      const JoinResult(role: Role.host),
    );
  });

  test('GameError parses an error reply response', () {
    expect(
      GameError.fromJson({'code': 'invalid_wager', 'message': 'nope'}),
      const GameError(code: 'invalid_wager', message: 'nope'),
    );
  });

  test('text_photo question type maps to QuestionType.textPhoto', () {
    final question = Question.fromJson({
      'id': 'q',
      'type': 'text_photo',
      'prompt': 'p',
      'image_url': 'https://example.com/x.png',
      'time_limit_ms': 1000,
    });
    expect(question.type, QuestionType.textPhoto);
    expect(question.toJson()['type'], 'text_photo');
  });
}
