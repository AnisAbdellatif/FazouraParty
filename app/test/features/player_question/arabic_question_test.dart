/// An Arabic quiz on the screens that show a quiz.
///
/// Flutter shapes Arabic correctly wherever it appears; what it cannot guess is
/// a paragraph's base direction, which is what decides the edge the text starts
/// at. These check that the direction comes from the words themselves, so an
/// Arabic question reads as Arabic inside an English interface.
@TestOn('vm')
library;

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/player_question/player_question_view.dart';
import 'package:fazoura_party/shared/widgets/reveal_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

const _arabicPrompt = 'ما هي عاصمة أستراليا؟';
const _arabicAnswer = 'كانبرا';

void main() {
  /// The direction the widget under [finder] is actually laid out in.
  TextDirection directionAt(WidgetTester tester, Finder finder) =>
      Directionality.of(tester.element(finder));

  RoomState withArabicQuestion(RoomState state) {
    final question = state.question!;
    return state.copyWith(question: question.copyWith(prompt: _arabicPrompt));
  }

  Future<void> pumpQuestion(WidgetTester tester, RoomState state) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameConnectionProvider.overrideWithValue(
            FakeGameConnection(initialState: state),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: PlayerQuestionView(state: state)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an Arabic question reads right to left', (tester) async {
    await pumpQuestion(tester, withArabicQuestion(questionStateForPlayer()));

    expect(
      directionAt(tester, find.byKey(const Key('questionPrompt'))),
      TextDirection.rtl,
    );
  });

  testWidgets('an English question is left alone', (tester) async {
    await pumpQuestion(tester, questionStateForPlayer());

    expect(
      directionAt(tester, find.byKey(const Key('questionPrompt'))),
      TextDirection.ltr,
    );
  });

  testWidgets('the answer field turns round as Arabic is typed', (
    tester,
  ) async {
    await pumpQuestion(tester, withArabicQuestion(questionStateForPlayer()));

    final field = find.byKey(const Key('answerField'));
    expect(directionAt(tester, field), TextDirection.ltr, reason: 'empty');

    await tester.enterText(field, _arabicAnswer);
    await tester.pump();
    expect(directionAt(tester, field), TextDirection.rtl);

    // And back, because a player may answer in either — the room does not
    // belong to one language.
    await tester.enterText(field, 'Canberra');
    await tester.pump();
    expect(directionAt(tester, field), TextDirection.ltr);
  });

  testWidgets('the reveal turns the question and its answers round together', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RevealSummary(
            prompt: _arabicPrompt,
            acceptedAnswers: [_arabicAnswer],
          ),
        ),
      ),
    );

    // The pills are laid out by the same direction as the question, so they
    // start at the same edge rather than at the opposite one.
    expect(
      directionAt(tester, find.byKey(const Key('acceptedAnswers'))),
      TextDirection.rtl,
    );
    expect(directionAt(tester, find.text(_arabicPrompt)), TextDirection.rtl);
  });
}
