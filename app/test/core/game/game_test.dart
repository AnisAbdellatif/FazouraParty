/// The LAN host's game rules, held to the same cases as `Fazoura.GameTest`.
///
/// Deliberately mirrors that file group for group: the two implementations
/// have to answer identically, and when one of them is changed the other's
/// test file should be the obvious next place to look (AGENTS.md §8). Where a
/// case comes from `protocol/fixtures/`, it is read from the fixture rather
/// than copied, so a change to the contract fails here too.
@TestOn('vm')
library;

import 'dart:math';

import 'package:fazoura_party/core/game/game.dart';
import 'package:fazoura_party/core/game/game_view.dart';
import 'package:fazoura_party/core/game/pack.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/protocol_fixtures.dart';

const t0 = 1000000;

Pack pack([int questionCount = 2]) => Pack.fromMap({
  'title': 'Test',
  'questions': [
    for (var i = 1; i <= questionCount; i++)
      {
        'id': 'q$i',
        'prompt': 'Question $i?',
        'accepted_answers': ['Right'],
        'time_limit_ms': 10000,
      },
  ],
});

Game gameWithPlayers(List<String> names, [int questionCount = 2]) {
  final game = Game(
    roomCode: 'ROOM42',
    pack: pack(questionCount),
    shuffleQuestions: false,
  );
  for (final name in names) {
    game.addPlayer(name, name);
  }
  return game;
}

/// Ending a question leaves it open for the closing window (PROTOCOL.md §6);
/// most tests only care that it ended, so this lets the window run out.
/// [close] stops short of it.
void host(Game game, String event, [Map<String, dynamic> payload = const {}]) {
  final ending = event == 'host_next' && game.phase == GamePhase.question;
  game.handle(const HostActor(), event, payload, t0);
  if (ending) game.tick(t0 + closingWindowMs);
}

void close(Game game, [int now = t0]) =>
    game.handle(const HostActor(), 'host_next', const {}, now);

void hostAt(Game game, String event, int now) =>
    game.handle(const HostActor(), event, const {}, now);

void submit(Game game, String id, Object? answer, [int now = t0]) =>
    game.handle(PlayerActor(id), 'submit', {'answer': answer}, now);

/// One question of [difficulty], with difficulty scoring on or off.
Game gradedGame(String difficulty, bool bonus, [int score = 0]) {
  final game = Game(
    roomCode: 'ROOM42',
    pack: Pack.fromMap({
      'title': 'T',
      'questions': [
        {
          'id': 'q1',
          'prompt': '?',
          'difficulty': difficulty,
          'accepted_answers': ['Right'],
          'time_limit_ms': 10000,
        },
      ],
    }),
    shuffleQuestions: false,
  );
  game.addPlayer('sam', 'Sam');
  game.players['sam'] = game.players['sam']!.copyWith(score: score);
  configure(game, 1, 10000, bonus);
  host(game, 'host_next');
  return game;
}

void configure(
  Game game,
  Object? count,
  Object? time, [
  Object? bonus = false,
]) => host(game, 'host_configure', {
  'question_count': count,
  'time_limit_ms': time,
  'difficulty_multiplier': bonus,
});

/// The code of the [GameRuleError] the callback throws.
Matcher throwsCode(String code) =>
    throwsA(isA<GameRuleError>().having((error) => error.code, 'code', code));

void main() {
  final scoring = ProtocolFixtures.load('scoring.json');

  group('difficulty scoring (fixtures)', () {
    for (final entry in scoring['points'] as List) {
      final c = entry as Map<String, dynamic>;
      test('${c['difficulty']}, difficulty scoring ${c['bonus']}', () {
        final game = gradedGame(c['difficulty'] as String, c['bonus'] as bool);
        final view = roomState(game, const HostActor(), t0);

        expect((view['question'] as Map)['points'], c['points']);
      });
    }

    for (final entry in scoring['delta'] as List) {
      final c = entry as Map<String, dynamic>;
      final correct = c['correct'] as bool;
      test('${c['difficulty']}, bonus ${c['bonus']}, correct=$correct', () {
        final game = gradedGame(c['difficulty'] as String, c['bonus'] as bool);
        submit(game, 'sam', correct ? 'Right' : 'Wrong');
        host(game, 'host_next');

        expect(game.players['sam']!.score, c['delta']);
        final rows =
            roomState(game, const HostActor(), t0)['submissions'] as List;
        expect((rows.single as Map)['delta'], c['delta']);
      });
    }

    for (final entry in scoring['skipped'] as List) {
      final c = entry as Map<String, dynamic>;
      test('skipped: ${c['name']}', () {
        final game = gradedGame(
          c['difficulty'] as String,
          c['bonus'] as bool,
          c['score_before_question'] as int,
        );
        host(game, 'host_next');
        expect(game.players['sam']!.score, c['score_after_scoring']);

        // A player who said nothing still gets a row, with no answer to show.
        final view = roomState(game, const PlayerActor('sam'), t0);
        expect(view['submissions'], [
          {
            'player_id': 'sam',
            'answer': null,
            'auto_correct': false,
            'override': null,
            'correct': false,
            'delta': c['delta'],
          },
        ]);
        expect((view['you'] as Map)['submission'], {
          'answer': null,
          'correct': false,
          'delta': c['delta'],
        });
      });
    }

    for (final entry in scoring['override'] as List) {
      final c = entry as Map<String, dynamic>;
      test('override: ${c['name']}', () {
        final autoCorrect = c['auto_correct'] as bool;
        final game = gradedGame(
          c['difficulty'] as String,
          c['bonus'] as bool,
          c['score_before_question'] as int,
        );

        submit(game, 'sam', autoCorrect ? 'Right' : 'Wrong');
        host(game, 'host_next');
        expect(game.players['sam']!.score, c['score_after_scoring']);

        host(game, 'host_override', {
          'player_id': 'sam',
          'correct': c['override'],
        });
        expect(game.players['sam']!.score, c['score_after_override']);
      });
    }

    test('a player who joined mid-question is not charged for it', () {
      final game = gradedGame('easy', true);
      game.addPlayer('late', 'Late');
      host(game, 'host_next');

      expect(game.players['sam']!.score, -10);
      expect(game.players['late']!.score, 0);

      // ...and has no row at all, rather than an empty one.
      final rows =
          roomState(game, const HostActor(), t0)['submissions'] as List;
      expect(rows.map((r) => (r as Map)['player_id']), ['sam']);
      final late = roomState(game, const PlayerActor('late'), t0);
      expect((late['you'] as Map)['submission'], isNull);
    });

    test('not answering cannot be overridden', () {
      final game = gradedGame('easy', true);
      host(game, 'host_next');

      expect(
        () =>
            host(game, 'host_override', {'player_id': 'sam', 'correct': true}),
        throwsCode('no_submission'),
      );
    });
  });

  group('players', () {
    test('names are trimmed, 1-20 chars and unique case-insensitively', () {
      final game = Game(roomCode: 'ROOM42', pack: pack());
      game.addPlayer('p1', '  Sam ');
      expect(game.players['p1']!.name, 'Sam');
      expect(() => game.addPlayer('p2', 'sAM'), throwsCode('name_taken'));
      expect(() => game.addPlayer('p2', '   '), throwsCode('invalid_name'));
      expect(() => game.addPlayer('p2', 'a' * 21), throwsCode('invalid_name'));
      expect(() => game.addPlayer('p2', null), throwsCode('invalid_name'));
    });

    test('a name is 20 graphemes, not 20 code units', () {
      final game = Game(roomCode: 'ROOM42', pack: pack());
      // 20 emoji are 40 UTF-16 code units; the limit counts characters (§4.1).
      game.addPlayer('p1', '🎉' * 20);
      expect(() => game.addPlayer('p2', '🎉' * 21), throwsCode('invalid_name'));
    });

    test('room is capped at maxPlayers', () {
      final game = gameWithPlayers([
        for (var i = 1; i <= maxPlayers; i++) 'player$i',
      ]);
      expect(() => game.addPlayer('extra', 'Extra'), throwsCode('room_full'));
    });
  });

  group('phases', () {
    test('full cycle over two questions', () {
      final game = gameWithPlayers(['sam']);
      expect(game.phase, GamePhase.lobby);

      host(game, 'host_next');
      expect(
        (game.phase, game.questionIndex, game.deadline),
        (GamePhase.question, 0, t0 + 10000),
      );

      host(game, 'host_next');
      expect(game.phase, GamePhase.scoring);
      host(game, 'host_next');
      expect(game.phase, GamePhase.leaderboard);
      host(game, 'host_next');
      expect((game.phase, game.questionIndex), (GamePhase.question, 1));

      host(game, 'host_next');
      host(game, 'host_next');
      host(game, 'host_next');
      expect(game.phase, GamePhase.finished);
      expect(() => host(game, 'host_next'), throwsCode('invalid_phase'));
    });

    test('an empty lobby has nothing to start', () {
      final game = Game(roomCode: 'ROOM42', pack: const Pack.empty());
      expect(() => host(game, 'host_next'), throwsCode('quiz_required'));
    });

    test('tick scores the question once the deadline passes', () {
      // Kim never answers, so the question runs its clock rather than ending
      // the moment Sam is done.
      final game = gameWithPlayers(['sam', 'kim']);
      host(game, 'host_next');
      submit(game, 'sam', 'right');

      game.tick(t0 + 9999);
      expect(game.phase, GamePhase.question);
      game.tick(t0 + 10000);
      expect(game.phase, GamePhase.scoring);
      expect(game.players['sam']!.score, 10);
      expect(game.players['kim']!.score, -10);
    });

    test('the question ends the moment the last player answers', () {
      final game = gameWithPlayers(['sam', 'kim']);
      host(game, 'host_next');

      submit(game, 'sam', 'right');
      expect(game.phase, GamePhase.question, reason: 'still waiting on kim');

      submit(game, 'kim', 'right', t0 + 1);
      expect(game.phase, GamePhase.scoring);
      expect(game.deadline, isNull);
      expect(game.players['sam']!.score, 10);
    });

    test('a room nobody answered in runs its clock down', () {
      // Everyone gone and nothing submitted: the pack must not race past
      // unattended, so only the deadline ends this.
      final game = gameWithPlayers(['sam']);
      host(game, 'host_next');
      game.setConnected('sam', false, t0);

      game.tick(t0 + 9999);
      expect(game.phase, GamePhase.question);
      game.tick(t0 + 10000);
      expect(game.phase, GamePhase.scoring);
    });

    test('a dropped player is waited out, then stops holding the room', () {
      final game = gameWithPlayers(['sam', 'kim']);
      host(game, 'host_next');
      game.setConnected('kim', false, t0);
      submit(game, 'sam', 'right', t0 + 1);

      expect(
        game.phase,
        GamePhase.question,
        reason: 'kim may still be coming back',
      );
      game.tick(t0 + 4999);
      expect(game.phase, GamePhase.question);

      // The grace runs from the disconnect, not from the last submission.
      game.tick(t0 + 5000);
      expect(game.phase, GamePhase.scoring);
      expect(game.players['kim']!.score, -10);
    });

    test(
      'a player who reconnects inside the grace still gets the question',
      () {
        final game = gameWithPlayers(['sam', 'kim']);
        host(game, 'host_next');
        game.setConnected('kim', false, t0);
        submit(game, 'sam', 'right', t0 + 1);
        game.setConnected('kim', true, t0 + 4000);

        game.tick(t0 + 9000);
        expect(game.phase, GamePhase.question);

        submit(game, 'kim', 'right', t0 + 9000);
        expect(game.phase, GamePhase.scoring);
      },
    );

    test('the grace is not renewed by flapping', () {
      final game = gameWithPlayers(['sam', 'kim']);
      host(game, 'host_next');
      game.setConnected('kim', false, t0);
      game.setConnected('kim', false, t0 + 4000);
      submit(game, 'sam', 'right', t0 + 1);

      game.tick(t0 + 5000);
      expect(game.phase, GamePhase.scoring);
    });

    test('a paused question never ends itself', () {
      final game = gameWithPlayers(['sam', 'kim']);
      host(game, 'host_next');
      game.setConnected('kim', false, t0);
      submit(game, 'sam', 'right', t0 + 1);
      game.handle(const HostActor(), 'host_pause', const {}, t0 + 2);

      game.tick(t0 + 60000);
      expect(game.phase, GamePhase.question);
      expect(game.timerDeadline, isNull);
    });

    test('the timer wakes for a grace that expires before the deadline', () {
      final game = gameWithPlayers(['sam', 'kim']);
      host(game, 'host_next');
      game.setConnected('kim', false, t0);
      submit(game, 'sam', 'right', t0 + 1);

      expect(
        game.timerDeadline,
        t0 + 5000,
        reason: 'the grace, not the far-off deadline',
      );
    });

    test('ending a question gives what is still being typed the closing '
        'window to arrive', () {
      final game = gameWithPlayers(['sam', 'kim']);
      host(game, 'host_next');

      close(game, t0 + 1000);
      expect(game.phase, GamePhase.question);
      expect(game.deadline, t0 + 1000 + closingWindowMs);

      // Sam's typed answer is sent for them just before the new deadline, and
      // counts.
      final deadline = game.deadline!;
      submit(game, 'sam', 'Right', deadline - 700);
      expect(game.phase, GamePhase.question, reason: 'still waiting on kim');

      game.tick(deadline);
      expect(game.phase, GamePhase.scoring);
      expect(
        (game.players['sam']!.score, game.players['kim']!.score),
        (10, -10),
      );
    });

    test('the closing window still ends the moment nobody is left to wait '
        'for', () {
      final game = gameWithPlayers(['sam']);
      host(game, 'host_next');
      close(game);
      submit(game, 'sam', 'Right', t0 + 500);
      expect(game.phase, GamePhase.scoring);
    });

    test('ending a closing question again does not cut the window short', () {
      final game = gameWithPlayers(['sam']);
      host(game, 'host_next');
      close(game);
      final deadline = game.deadline;
      close(game, t0 + 1500);
      expect(game.deadline, deadline);
    });

    test('ending a question with less time left than the window keeps the '
        'deadline', () {
      final game = gameWithPlayers(['sam']);
      host(game, 'host_next');
      close(game, t0 + 9000);
      expect(game.deadline, t0 + 10000);
    });

    test('ending a paused question resumes it into the closing window', () {
      final game = gameWithPlayers(['sam']);
      host(game, 'host_next');
      host(game, 'host_pause');

      close(game, t0 + 60000);
      expect(
        (game.deadline, game.pausedRemainingMs),
        (t0 + 60000 + closingWindowMs, null),
      );
      submit(game, 'sam', 'Right', t0 + 60500);
      expect(game.phase, GamePhase.scoring);
    });

    test('ending a question nobody can still answer scores it at once', () {
      final game = gameWithPlayers(['kim']);
      host(game, 'host_next');
      game.setConnected('kim', false, t0);

      close(game, t0 + 1000);
      expect(
        game.phase,
        GamePhase.question,
        reason: 'kim is inside the grace and may be back',
      );
      close(game, t0 + 5000);
      expect(game.phase, GamePhase.scoring);
    });

    test('pause freezes the timer and resume restores the remaining time', () {
      final game = gameWithPlayers(['sam']);
      host(game, 'host_next');

      hostAt(game, 'host_pause', t0 + 4000);
      expect((game.deadline, game.pausedRemainingMs), (null, 6000));
      expect(() => host(game, 'host_pause'), throwsCode('paused'));
      game.tick(t0 + 999999);
      expect(game.phase, GamePhase.question);
      expect(() => submit(game, 'sam', 'Right'), throwsCode('paused'));

      hostAt(game, 'host_resume', t0 + 50000);
      expect((game.deadline, game.pausedRemainingMs), (t0 + 56000, null));
      expect(() => host(game, 'host_resume'), throwsCode('not_paused'));
    });
  });

  group('intent validation', () {
    late Game game;
    setUp(() {
      game = gameWithPlayers(['sam', 'alex']);
      host(game, 'host_next');
    });

    test('role checks', () {
      expect(
        () => game.handle(const PlayerActor('sam'), 'host_next', {}, t0),
        throwsCode('not_host'),
      );
      expect(
        () => game.handle(const PlayerActor('sam'), 'host_override', {}, t0),
        throwsCode('not_host'),
      );
      expect(
        () => game.handle(const HostActor(), 'submit', {}, t0),
        throwsCode('not_player'),
      );
    });

    test('an unknown intent is refused rather than ignored', () {
      expect(() => host(game, 'host_teleport'), throwsCode('invalid_payload'));
    });

    test('one submission per player, before the deadline', () {
      submit(game, 'sam', 'Right');
      expect(
        () => submit(game, 'sam', 'Right'),
        throwsCode('already_submitted'),
      );
      expect(
        () => submit(game, 'alex', 'Right', t0 + 10000),
        throwsCode('invalid_phase'),
      );
    });

    test('answer must be 1-100 chars', () {
      expect(() => submit(game, 'sam', '  '), throwsCode('invalid_answer'));
      expect(
        () => submit(game, 'sam', 'a' * 101),
        throwsCode('invalid_answer'),
      );
      expect(() => submit(game, 'sam', 42), throwsCode('invalid_answer'));
    });

    test('override errors', () {
      submit(game, 'sam', 'Right');
      expect(
        () =>
            host(game, 'host_override', {'player_id': 'sam', 'correct': false}),
        throwsCode('invalid_phase'),
      );

      host(game, 'host_next');
      expect(
        () => host(game, 'host_override', {
          'player_id': 'nobody',
          'correct': true,
        }),
        throwsCode('unknown_player'),
      );
      expect(
        () =>
            host(game, 'host_override', {'player_id': 'alex', 'correct': true}),
        throwsCode('no_submission'),
      );
      expect(
        () => host(game, 'host_override', {'player_id': 'sam'}),
        throwsCode('invalid_payload'),
      );
    });
  });

  group('settings', () {
    test("defaults to the whole pack at the first question's time limit", () {
      final game = gameWithPlayers(['sam'], 3);

      expect(game.settings.questionCount, 3);
      expect(game.settings.timeLimitMs, 10000);
      expect(game.settings.difficultyMultiplier, isFalse);
      expect(game.settings.difficulties, ['easy']);
      expect(game.settings.availableDifficulties, ['easy']);

      final view = roomState(game, const HostActor(), t0);
      expect(view['question_count'], 3);
      expect(view['settings'], {
        'question_count': 3,
        'time_limit_ms': 10000,
        'difficulty_multiplier': false,
        'max_question_count': 3,
        'difficulties': ['easy'],
        'available_difficulties': ['easy'],
        'min_time_limit_ms': 10000,
        'max_time_limit_ms': 120000,
      });
    });

    test('host sets question count and time limit in the lobby only', () {
      final game = gameWithPlayers(['sam'], 3);

      for (final (count, time) in const [
        (0, 20000),
        (4, 20000),
        (2, 9999),
        (2, 120001),
        ('2', 20000),
      ]) {
        expect(
          () => configure(game, count, time),
          throwsCode('invalid_settings'),
          reason: 'count=$count time=$time',
        );
      }

      expect(
        () => host(game, 'host_configure', {}),
        throwsCode('invalid_settings'),
      );
      expect(
        () => host(game, 'host_configure', {
          'question_count': 2,
          'time_limit_ms': 20000,
        }),
        throwsCode('invalid_settings'),
      );
      expect(
        () => configure(game, 2, 20000, 'yes'),
        throwsCode('invalid_settings'),
      );
      expect(
        () => game.handle(const PlayerActor('sam'), 'host_configure', {}, t0),
        throwsCode('not_host'),
      );

      configure(game, 2, 15000);
      host(game, 'host_next');
      expect(game.deadline, t0 + 15000);
      expect(
        (roomState(game, const HostActor(), t0)['question']
            as Map<String, dynamic>)['time_limit_ms'],
        15000,
      );
      expect(() => configure(game, 1, 15000), throwsCode('invalid_phase'));

      for (var i = 0; i < 6; i++) {
        host(game, 'host_next');
      }
      expect(game.phase, GamePhase.finished);
    });

    test('a difficulty the pack does not have cannot be selected', () {
      final game = gameWithPlayers(['sam'], 3);
      expect(
        () => host(game, 'host_configure', {
          'question_count': 1,
          'time_limit_ms': 15000,
          'difficulty_multiplier': false,
          'difficulties': ['easy', 'hard'],
        }),
        throwsCode('invalid_settings'),
      );
      expect(
        () => host(game, 'host_configure', {
          'question_count': 1,
          'time_limit_ms': 15000,
          'difficulty_multiplier': false,
          'difficulties': <String>[],
        }),
        throwsCode('invalid_settings'),
      );
      expect(
        () => host(game, 'host_configure', {
          'question_count': 1,
          'time_limit_ms': 15000,
          'difficulty_multiplier': false,
          'difficulties': ['easy', 42],
        }),
        throwsCode('invalid_settings'),
      );
    });

    test('narrowing the difficulties clamps the count instead of failing', () {
      final game = Game(
        roomCode: 'ROOM42',
        shuffleQuestions: false,
        pack: Pack.fromMap({
          'title': 'Mixed',
          'questions': [
            for (final (i, difficulty) in ['easy', 'easy', 'hard'].indexed)
              {
                'id': 'q${i + 1}',
                'prompt': '?',
                'difficulty': difficulty,
                'accepted_answers': ['Right'],
                'time_limit_ms': 10000,
              },
          ],
        }),
      );
      expect(game.settings.availableDifficulties, ['easy', 'hard']);
      expect(game.maxAllowedQuestionCount, 3);

      // Three questions were on offer; only the one hard question now is, so
      // the count follows the selection down rather than being refused.
      host(game, 'host_configure', {
        'question_count': 3,
        'time_limit_ms': 10000,
        'difficulty_multiplier': false,
        'difficulties': ['hard'],
      });
      expect(game.settings.questionCount, 1);
      expect(game.maxAllowedQuestionCount, 1);

      // Asking for more than the *current* selection holds is a mistake.
      expect(
        () => host(game, 'host_configure', {
          'question_count': 2,
          'time_limit_ms': 10000,
          'difficulty_multiplier': false,
          'difficulties': ['hard'],
        }),
        throwsCode('invalid_settings'),
      );

      // The pack is played from the filtered order, not the whole pack, so the
      // only hard question is the one asked.
      host(game, 'host_next');
      final question =
          roomState(game, const HostActor(), t0)['question']
              as Map<String, dynamic>;
      expect(question['id'], 'q3');
      expect(question['difficulty'], 'hard');
    });
  });

  group('question count and difficulty scoring', () {
    test('the round can use the full pack size', () {
      final game = gameWithPlayers(['sam'], 25);
      expect(game.settings.questionCount, 25);
      expect(
        (roomState(game, const HostActor(), t0)['settings']
            as Map<String, dynamic>)['max_question_count'],
        25,
      );
      expect(() => configure(game, 26, 30000), throwsCode('invalid_settings'));
      configure(game, 25, 30000);
      expect(game.settings.questionCount, 25);
    });

    test('unknown difficulties are rejected when loading a pack', () {
      expect(
        () => Pack.fromMap({
          'title': 'T',
          'questions': [
            {
              'id': 'q',
              'prompt': '?',
              'difficulty': 'brutal',
              'accepted_answers': <String>[],
            },
          ],
        }),
        throwsArgumentError,
      );
    });
  });

  group('avatar hues', () {
    test(
      'stay within 0..359 and spread away from hues already in the room',
      () {
        final game = Game(roomCode: 'ROOM42', pack: pack());
        game.addPlayer('a', 'A', avatarHue: 100);

        final candidates = [
          for (var i = 0; i < 3; i++) ...[95, 110, 280, 102],
        ];
        var index = 0;
        expect(
          game.pickAvatarHue(_ScriptedRandom(() => candidates[index++])),
          280,
        );

        for (var i = 0; i < 50; i++) {
          expect(game.pickAvatarHue(), inInclusiveRange(0, 359));
        }
        final players =
            roomState(game, const HostActor(), t0)['players'] as List;
        expect((players.first as Map<String, dynamic>)['avatar_hue'], 100);
      },
    );
  });

  group('rematch', () {
    test('resets scores and returns to quiz selection in the same room', () {
      final game = gameWithPlayers(['sam', 'alex'], 3);
      configure(game, 2, 10000);

      host(game, 'host_next');
      submit(game, 'sam', 'Right');
      for (var i = 0; i < 6; i++) {
        host(game, 'host_next');
      }
      expect(game.phase, GamePhase.finished);
      // One right (+10) and one let go by (-10) for Sam; alex answered neither.
      expect(game.players['sam']!.score, 0);
      expect(game.players['alex']!.score, -20);

      expect(
        () => game.handle(const PlayerActor('sam'), 'host_rematch', {}, t0),
        throwsCode('not_host'),
      );

      host(game, 'host_rematch');
      expect(
        (game.phase, game.gameNumber, game.questionIndex),
        (GamePhase.lobby, 2, null),
      );
      expect(game.players.values.map((p) => p.score), [0, 0]);
      expect(game.players.length, 2);
      expect(game.settings.questionCount, 0);
      expect(game.pack.questions, isEmpty);
      expect(() => host(game, 'host_rematch'), throwsCode('invalid_phase'));

      game.selectQuiz(pack(3));
      host(game, 'host_next');
      final view = roomState(game, const HostActor(), t0);
      expect(
        (view['question'] as Map<String, dynamic>)['id'],
        isIn(['q1', 'q2', 'q3']),
      );
      expect(view['game_number'], 2);
    });

    test('a quiz can only be chosen in the lobby, and cannot be empty', () {
      final game = gameWithPlayers(['sam']);
      expect(
        () => game.selectQuiz(const Pack.empty()),
        throwsCode('empty_pack'),
      );
      host(game, 'host_next');
      expect(() => game.selectQuiz(pack(3)), throwsCode('invalid_phase'));
    });
  });

  group('views', () {
    test("players never see answers or others' submissions before scoring", () {
      final game = gameWithPlayers(['sam', 'alex']);
      host(game, 'host_next');
      submit(game, 'sam', 'Right');

      final player = roomState(game, const PlayerActor('alex'), t0);
      expect(player['accepted_answers'], isNull);
      expect(player['submissions'], isNull);
      expect((player['you'] as Map<String, dynamic>)['submission'], isNull);
      expect(
        (player['players'] as List).cast<Map<String, dynamic>>().firstWhere(
          (p) => p['id'] == 'sam',
        )['has_submitted'],
        isTrue,
      );

      final own = roomState(game, const PlayerActor('sam'), t0);
      expect((own['you'] as Map<String, dynamic>)['submission'], {
        'answer': 'Right',
        'correct': null,
        'delta': null,
      });

      final hostView = roomState(game, const HostActor(), t0);
      expect(hostView['accepted_answers'], isNull);
      expect(hostView['submissions'], isNull);
      expect(hostView['you'], {
        'role': 'host',
        'player_id': null,
        'host_token': null,
        'submission': null,
      });

      host(game, 'host_next');
      final scored = roomState(game, const PlayerActor('alex'), t0);
      expect(scored['accepted_answers'], ['Right']);
      final submissions = (scored['submissions'] as List)
          .cast<Map<String, dynamic>>();
      expect(submissions.map((s) => s['player_id']), ['sam', 'alex']);
      expect(submissions.first['correct'], isTrue);
      expect(submissions.first['delta'], 10);
      // alex never answered, so her row carries the skip penalty instead.
      expect(submissions.last['answer'], isNull);
      expect(submissions.last['delta'], -10);
    });

    test(
      'a playing host submits, sees nothing early, and can override their own '
      'answer',
      () {
        final game = gameWithPlayers(['sam']);
        game.addHostPlayer('hana', 'Hana');
        // Already playing: a reconnecting host does not become a second player.
        game.addHostPlayer('other', 'Other');
        expect(game.hostPlayerId, 'hana');
        expect(game.players.length, 2);
        expect(() => game.addPlayer('x', 'HANA'), throwsCode('name_taken'));

        host(game, 'host_next');
        host(game, 'submit', {'answer': 'Rigth'});
        expect(
          () => host(game, 'submit', {'answer': 'Right'}),
          throwsCode('already_submitted'),
        );

        final during = roomState(game, const HostActor(), t0);
        expect(
          (during['accepted_answers'], during['submissions']),
          (null, null),
        );
        expect(during['you'], {
          'role': 'host',
          'player_id': 'hana',
          'host_token': null,
          'submission': {'answer': 'Rigth', 'correct': null, 'delta': null},
        });
        final players = (during['players'] as List)
            .cast<Map<String, dynamic>>();
        expect(players.map((p) => p['id']), ['hana', 'sam']);
        expect(players.first['is_host'], isTrue);
        expect(players.first['has_submitted'], isTrue);
        expect(players[1]['is_host'], isFalse);

        host(game, 'host_next');
        expect(game.players['hana']!.score, -10);
        expect(roomState(game, const HostActor(), t0)['accepted_answers'], [
          'Right',
        ]);

        host(game, 'host_override', {'player_id': 'hana', 'correct': true});
        expect(game.players['hana']!.score, 10);

        // Sam let the question go by, and is told what that cost rather than
        // nothing.
        expect(
          (roomState(game, const PlayerActor('sam'), t0)['you']
              as Map<String, dynamic>)['submission'],
          {'answer': null, 'correct': false, 'delta': -10},
        );
      },
    );

    test('players are sorted by score desc, then name case-insensitively', () {
      final game = gameWithPlayers(['bob', 'Alice', 'carl']);
      game.players['carl'] = game.players['carl']!.copyWith(score: 5);

      final names = (roomState(game, const HostActor(), t0)['players'] as List)
          .cast<Map<String, dynamic>>()
          .map((p) => p['name']);
      expect(names, ['carl', 'Alice', 'bob']);
    });

    test('finished hides question data from everyone', () {
      final game = gameWithPlayers(['sam'], 1);
      for (var i = 0; i < 4; i++) {
        host(game, 'host_next');
      }
      expect(game.phase, GamePhase.finished);

      final view = roomState(game, const HostActor(), t0);
      expect(
        (view['question'], view['accepted_answers'], view['submissions']),
        (null, null, null),
      );
    });

    test('a promoted player is told they are the host', () {
      final game = gameWithPlayers(['sam']);
      host(game, 'host_transfer', {'player_id': 'sam'});

      expect(
        (roomState(game, const PlayerActor('sam'), t0)['you']
            as Map<String, dynamic>)['role'],
        'host',
      );
      // The connection that handed the role away is an ordinary client now,
      // and the snapshot has to say so (§3.4).
      expect(
        (roomState(game, const HostActor(holder: false), t0)['you']
            as Map<String, dynamic>)['role'],
        'player',
      );
    });

    test('a LAN host has no public list to put a room on', () {
      final game = gameWithPlayers(['sam']);
      expect(
        () => host(game, 'host_set_listed', {'listed': true}),
        throwsCode('cloud_only'),
      );
    });

    test('the snapshot carries every field PROTOCOL.md §5.1 names', () {
      final game = gameWithPlayers(['sam']);
      host(game, 'host_next');
      final view = roomState(game, const HostActor(), t0);

      expect(view.keys.toSet(), {
        'protocol_version',
        'protocol_minor',
        'room_code',
        'mode',
        'listed',
        'phase',
        'server_time',
        'pack_titles',
        'question_index',
        'question_count',
        'game_number',
        'settings',
        'question',
        'deadline',
        'paused_remaining_ms',
        'accepted_answers',
        'players',
        'you',
        'submissions',
      });
      expect((view['settings'] as Map).keys.toSet(), {
        'question_count',
        'time_limit_ms',
        'difficulty_multiplier',
        'max_question_count',
        'difficulties',
        'available_difficulties',
        'min_time_limit_ms',
        'max_time_limit_ms',
      });
      expect((view['question'] as Map).keys.toSet(), {
        'id',
        'type',
        'prompt',
        'image_url',
        'time_limit_ms',
        'difficulty',
        'points',
      });
      expect(((view['players'] as List).first as Map).keys.toSet(), {
        'id',
        'name',
        'score',
        'connected',
        'has_submitted',
        'is_host',
        'avatar_hue',
      });
      expect((view['you'] as Map).keys.toSet(), {
        'role',
        'player_id',
        'host_token',
        'submission',
      });
      expect(view['mode'], 'lan');
      expect(view['listed'], false);
      expect(view['protocol_version'], protocolMajor);
      expect(view['server_time'], t0);
    });
  });
}

/// Hands out a scripted sequence where a hue would be picked at random.
class _ScriptedRandom implements Random {
  _ScriptedRandom(this._next);
  final int Function() _next;

  @override
  int nextInt(int max) => _next();

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
