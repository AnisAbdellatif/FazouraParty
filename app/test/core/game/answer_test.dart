/// Answer matching, held to `protocol/fixtures/normalize.json` — the same
/// cases `Fazoura.Game.AnswerTest` holds the Elixir side to.
///
/// This matters more here than almost anywhere else in the port. Dart has no
/// Unicode normalization and no `\p{Mn}`, so `answer.dart` carries a
/// hand-written NFD table where Elixir gets both for free. If the two ever
/// disagree, the same answer scores differently depending on who is hosting,
/// which is the one thing a party game cannot do.
@TestOn('vm')
library;

import 'package:fazoura_party/core/game/answer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/protocol_fixtures.dart';

void main() {
  final fixtures = ProtocolFixtures.load('normalize.json');

  group('normalize', () {
    for (final entry in fixtures['normalize'] as List) {
      final c = entry as Map<String, dynamic>;
      test('normalize ${c['input']}', () {
        expect(normalizeAnswer(c['input'] as String), c['output']);
      });
    }
  });

  group('match', () {
    for (final entry in fixtures['match'] as List) {
      final c = entry as Map<String, dynamic>;
      test('${c['answer']} against ${c['accepted']} is ${c['correct']}', () {
        expect(
          answerIsCorrect(
            c['answer'] as String,
            (c['accepted'] as List).cast<String>(),
          ),
          c['correct'],
        );
      });
    }
  });

  test('the fixture actually covers the hard cases', () {
    // A guard on the guard: these assertions are worth nothing if the fixture
    // is emptied or trimmed down to ASCII, and the failure would be silent.
    final inputs = [
      for (final entry in fixtures['normalize'] as List)
        (entry as Map<String, dynamic>)['input'] as String,
    ];
    expect(inputs, contains('São Paulo'));
    expect(inputs, contains('Crème Brûlée'));
    expect(inputs.any((input) => input.contains('\t')), isTrue);
    expect((fixtures['match'] as List).length, greaterThanOrEqualTo(8));
  });
}
