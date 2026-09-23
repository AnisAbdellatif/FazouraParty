/// What a browser choice becomes on the wire (PROTOCOL.md §6.4).
///
/// The two hosts want opposite things from the same pick. Cloud has the quiz
/// already and takes its id; a LAN host has no database at all, so the whole
/// document has to travel with the intent — and "whole" is the part that is
/// easy to get wrong, because an ordinary read answers without questions.
@TestOn('vm')
library;

import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/features/host/host_screen.dart';
import 'package:fazoura_party/features/quizzes/quiz_choice.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_quiz_server.dart';

void main() {
  late FakeQuizServer server;

  QuizDocument published() => QuizDocument(
    id: 'quiz-1',
    formatVersion: '1.0',
    title: 'Film Night',
    tags: const ['movies'],
    questions: const [
      QuizQuestion(
        id: 'q1',
        type: QuizQuestion.typeText,
        prompt: 'Which film?',
        acceptedAnswers: ['The Matrix'],
      ),
    ],
  );

  setUp(() => server = FakeQuizServer([published()]));

  test('a LAN host gets the questions, not just the cover', () async {
    final selection = await quizSelectionFor(
      server.api(),
      PublicQuizChoice(published()),
      isLan: true,
    );

    // `GET /api/quizzes/:id` withholds questions from everyone but the
    // publisher, so a selection built from it reaches the room empty and comes
    // back `empty_pack` — "That quiz has no playable questions", for every
    // public quiz, every time.
    final inline = selection as InlineQuizSelection;
    expect(inline.quiz.questions, isNotEmpty);
    expect(inline.quiz.questions!.single.acceptedAnswers, ['The Matrix']);
  });

  test('a cloud host sends the id and lets the server look it up', () async {
    final selection = await quizSelectionFor(
      server.api(),
      PublicQuizChoice(published()),
      isLan: false,
    );

    expect(selection, isA<StoredQuizSelection>());
    expect((selection as StoredQuizSelection).quizId, 'quiz-1');
  });

  test("a quiz of this device's own travels inline either way", () async {
    final local = LocalQuiz(localId: 'local-1', quiz: published());

    for (final isLan in [true, false]) {
      final selection = await quizSelectionFor(
        server.api(),
        LocalQuizChoice(local),
        isLan: isLan,
      );

      // It is on the device and nowhere else, so there is no id to send.
      final inline = selection as InlineQuizSelection;
      expect(inline.quiz.questions, isNotEmpty, reason: 'isLan: $isLan');
    }
  });
}
