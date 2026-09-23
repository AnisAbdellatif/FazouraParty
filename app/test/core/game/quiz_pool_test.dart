/// Several quizzes played as one pool (PROTOCOL.md §6.4).
///
/// The happy path over three quizzes is replayed from
/// `protocol/fixtures/scenarios/multiple_quizzes.json` against both hosts;
/// what is left here is the LAN side of everything around it — the merge
/// itself, the bounds, and what a malformed selection does.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fazoura_party/core/game/game.dart';
import 'package:fazoura_party/core/game/lan_images.dart';
import 'package:fazoura_party/core/game/lan_room.dart';
import 'package:fazoura_party/core/game/pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List pngBytes() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

Map<String, dynamic> quiz(
  String title,
  List<String> prompts, {
  int? timeLimitMs,
  bool? difficultyMultiplier,
  String difficulty = 'easy',
}) => {
  'format_version': 1,
  'title': title,
  'tags': ['fixture'],
  if (timeLimitMs != null || difficultyMultiplier != null)
    'default_settings': {
      'time_limit_ms': ?timeLimitMs,
      'difficulty_multiplier': ?difficultyMultiplier,
    },
  'questions': [
    for (final (index, prompt) in prompts.indexed)
      {
        // Every quiz numbers its questions from one: the collision the merge
        // exists to resolve.
        'id': 'q${index + 1}',
        'type': 'text',
        'prompt': prompt,
        'accepted_answers': [prompt],
        'difficulty': difficulty,
        'time_limit_ms': 30000,
      },
  ],
};

Pack packOf(String title, List<String> ids) => Pack.fromMap({
  'title': title,
  'questions': [
    for (final id in ids)
      {
        'id': id,
        'prompt': '$title $id?',
        'accepted_answers': ['a'],
        'time_limit_ms': 30000,
      },
  ],
});

Matcher throwsCode(String code) =>
    throwsA(isA<GameRuleError>().having((error) => error.code, 'code', code));

class _Client implements LanConnection {
  Map<String, dynamic>? _latest;
  Map<String, dynamic> get latest => _latest!;

  @override
  void pushState(Map<String, dynamic> state) => _latest = state;

  @override
  void pushClosed(String reason) {}
}

void main() {
  group('Pack.merge', () {
    test('one pack is itself, untouched', () {
      final only = packOf('Solo', ['q1', 'q2']);
      final merged = Pack.merge([only]);

      expect(merged, same(only));
      expect(merged.questions.map((q) => q.id), ['q1', 'q2']);
    });

    test('several become one pool with unique ids and every title', () {
      final merged = Pack.merge([
        packOf('One', ['q1', 'q2']),
        packOf('Two', ['q1']),
        packOf('Three', ['q1']),
      ]);

      expect(merged.titles, ['One', 'Two', 'Three']);
      expect(merged.questions, hasLength(4));
      expect(merged.questions.map((q) => q.id).toSet(), hasLength(4));
      // The prompts still say which quiz each question came from, so nothing
      // is lost by renaming the ids.
      expect(merged.questions.map((q) => q.prompt), [
        'One q1?',
        'One q2?',
        'Two q1?',
        'Three q1?',
      ]);
    });

    test('defaults come from the first pack, not the last', () {
      final merged = Pack.merge([
        const Pack(
          titles: ['First'],
          questions: [],
          defaultTimeLimitMs: 90000,
          defaultDifficultyMultiplier: true,
        ),
        const Pack(
          titles: ['Second'],
          questions: [],
          defaultTimeLimitMs: 15000,
        ),
      ]);

      expect(merged.defaultTimeLimitMs, 90000);
      expect(merged.defaultDifficultyMultiplier, isTrue);
    });
  });

  group('selecting quizzes on a LAN host', () {
    late LanRoom room;
    late _Client host;

    setUp(() {
      room = LanRoom.create(
        pack: const Pack.empty(),
        shuffleQuestions: false,
        broadcastGap: Duration.zero,
      );
      host = _Client();
      room.join(host, {
        'protocol_version': protocolMajor,
        'host_token': room.hostToken,
      });
    });

    tearDown(() => room.close(LanCloseReason.shutdown));

    void select(List<Map<String, dynamic>> quizzes) =>
        room.handle(host, 'host_select_quiz', {
          'quizzes': [
            for (final one in quizzes) {'quiz': one},
          ],
        });

    test('one quiz still works exactly as it did', () {
      select([
        quiz('Science', ['Sci one?', 'Sci two?']),
      ]);

      expect(host.latest['pack_titles'], ['Science']);
      expect(host.latest['question_count'], 2);
    });

    test('three quizzes make one pool the round draws from', () {
      select([
        quiz('Science', ['Sci one?', 'Sci two?']),
        quiz('History', ['Hist one?']),
        quiz('Movies', ['Mov one?']),
      ]);

      expect(host.latest['pack_titles'], ['Science', 'History', 'Movies']);
      expect(host.latest['question_count'], 4);
      expect((host.latest['settings'] as Map)['max_question_count'], 4);
      expect(room.game.pack.questions.map((q) => q.id).toSet(), hasLength(4));
    });

    test('lobby defaults come from the first quiz selected', () {
      select([
        quiz('Slow', ['a?'], timeLimitMs: 90000, difficultyMultiplier: true),
        quiz('Fast', ['b?'], timeLimitMs: 15000),
      ]);

      final settings = host.latest['settings'] as Map<String, dynamic>;
      expect(settings['time_limit_ms'], 90000);
      expect(settings['difficulty_multiplier'], isTrue);
    });

    test('difficulties are the union across the pool', () {
      select([
        quiz('Easy', ['a?']),
        quiz('Hard', ['b?'], difficulty: 'hard'),
      ]);

      final settings = host.latest['settings'] as Map<String, dynamic>;
      expect(settings['available_difficulties'], ['easy', 'hard']);
      expect(settings['difficulties'], ['easy', 'hard']);
    });

    test('selecting again replaces the whole selection', () {
      select([
        quiz('First', ['a?']),
        quiz('Second', ['b?']),
      ]);
      expect(host.latest['pack_titles'], ['First', 'Second']);

      select([
        quiz('Third', ['c?']),
      ]);
      expect(host.latest['pack_titles'], ['Third']);
      expect(host.latest['question_count'], 1);
    });

    test('ten quizzes are allowed, eleven are not', () {
      final ten = [
        for (var i = 1; i <= maxQuizzes; i++) quiz('Quiz $i', ['q$i?']),
      ];

      select(ten);
      expect(host.latest['question_count'], maxQuizzes);

      expect(
        () => select([
          ...ten,
          quiz('One too many', ['x?']),
        ]),
        throwsCode('invalid_quiz'),
      );
      // The refusal changed nothing.
      expect(host.latest['question_count'], maxQuizzes);
    });

    test('an empty or malformed selection is refused', () {
      for (final payload in <Map<String, dynamic>>[
        {'quizzes': <Object>[]},
        {'quizzes': 'science'},
        {
          'quizzes': [<String, dynamic>{}],
        },
        {
          'quizzes': [
            {'quiz': 'not a document'},
          ],
        },
        // The shape before v8: one quiz, named directly.
        {'quiz_id': 'the old single shape'},
        <String, dynamic>{},
      ]) {
        expect(
          () => room.handle(host, 'host_select_quiz', payload),
          throwsCode('invalid_quiz'),
          reason: '$payload',
        );
      }
    });

    test('a LAN host cannot resolve a stored id, only a document', () {
      // Cloud looks `quiz_id` up in its database; a LAN host has neither the
      // database nor the internet, so the client sends the document instead.
      expect(
        () => room.handle(host, 'host_select_quiz', {
          'quizzes': [
            {'quiz_id': 'some-uuid'},
          ],
        }),
        throwsCode('invalid_quiz'),
      );
    });

    test('photos are bounded across the whole selection', () {
      // Four quizzes of two near-cap photos each: each quiz is fine alone, the
      // selection is not. Counting per quiz would let ten quizzes hold ten
      // times what one room is allowed (QUIZ_FORMAT.md §5.7).
      final photo = base64Encode([
        ...pngBytes(),
        ...List.filled(LanImages.maxImageBytes - 1000, 0),
      ]);
      Map<String, dynamic> heavy(String title) => {
        ...quiz(title, ['a?', 'b?']),
        'questions': [
          for (final id in ['q1', 'q2'])
            {
              'id': id,
              'type': 'text_photo',
              'prompt': 'Which?',
              'accepted_answers': ['a'],
              'time_limit_ms': 30000,
              'image': {'data': photo},
            },
        ],
      };

      select([heavy('One')]);
      expect(room.images.length, 2);

      expect(
        () => select([for (var i = 0; i < 4; i++) heavy('Quiz $i')]),
        throwsCode('quiz_too_large'),
      );
      // The refusal left the accepted selection alone.
      expect(room.images.length, 2);
      expect(host.latest['pack_titles'], ['One']);
    });

    test('a pool of nothing is refused', () {
      expect(
        () => select([quiz('Hollow', const [])]),
        throwsCode('empty_pack'),
      );
    });

    test('the selection cannot change once the game is under way', () {
      select([
        quiz('Science', ['a?']),
      ]);
      room.handle(host, 'host_next', {});

      expect(
        () => select([
          quiz('Too late', ['b?']),
        ]),
        throwsCode('invalid_phase'),
      );
    });

    test('a rematch clears the selection', () {
      select([
        quiz('Science', ['a?']),
      ]);
      for (var i = 0; i < 4; i++) {
        room.handle(host, 'host_next', {});
      }
      expect(room.game.phase, GamePhase.finished);

      room.handle(host, 'host_rematch', {});
      expect(host.latest['pack_titles'], isEmpty);
      expect(host.latest['question_count'], 0);
    });
  });
}
