import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/host/host_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

void main() {
  late FakeGameConnection fake;

  Future<void> pumpHost(WidgetTester tester, RoomState state) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection(initialState: state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: HostScreen(roomCode: 'K7QX2M')),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder inRow(String playerId, Finder finder) => find.descendant(
    of: find.byKey(ValueKey('submission-$playerId')),
    matching: finder,
  );

  group('playing host during question', () {
    testWidgets('shows the answer input and submitting calls submit', (
      tester,
    ) async {
      await pumpHost(tester, questionStateForHost(playing: true));

      expect(find.byKey(const Key('hostRoomCode')), findsOneWidget);
      expect(find.byKey(const Key('answerField')), findsOneWidget);
      expect(find.text('End question'), findsOneWidget);
      expect(find.text('CORRECT ANSWER'), findsNothing);
      expect(find.byType(Switch), findsNothing);

      await tester.enterText(find.byKey(const Key('answerField')), 'Canberra');
      tester.widget<Slider>(find.byKey(const Key('wagerSlider'))).onChanged!(6);
      await tester.pump();
      await tester.tap(find.byKey(const Key('submitButton')));
      await tester.pump();

      expect(fake.submissions, [(answer: 'Canberra', wager: 6)]);
      expect(find.byKey(const Key('ownSubmission')), findsOneWidget);
      expect(find.byKey(const Key('answerField')), findsNothing);

      // Host controls stay available while playing.
      await tester.tap(find.byKey(const Key('hostPauseButton')));
      await tester.tap(find.byKey(const Key('hostNextButton')));
      await tester.pump();
      expect(fake.pauseCalls, 1);
      expect(fake.nextCalls, 1);
    });
  });

  group('non-playing host during question', () {
    testWidgets('shows controls and has_submitted, no answer input', (
      tester,
    ) async {
      final state = questionStateForHost(playing: false)
          .copyWith(deadline: null, pausedRemainingMs: 12000);
      await pumpHost(tester, state);

      expect(find.byKey(const Key('answerField')), findsNothing);
      expect(find.text('What is the capital of Australia?'), findsOneWidget);
      expect(find.byKey(const ValueKey('submitted-p_3f9a')), findsOneWidget);
      expect(find.text('1 of 1 answered'), findsOneWidget);
      expect(find.text('PAUSED · 12s'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);

      // Paused question: Resume enabled, Pause disabled.
      await tester.tap(find.byKey(const Key('hostResumeButton')));
      await tester.tap(find.byKey(const Key('hostPauseButton')));
      await tester.pump();
      expect(fake.resumeCalls, 1);
      expect(fake.pauseCalls, 0);
    });
  });

  group('host after the game', () {
    testWidgets('Play again sends host_rematch', (tester) async {
      await pumpHost(
        tester,
        scoringStateForHost().copyWith(
          phase: Phase.finished,
          question: null,
          acceptedAnswers: null,
          submissions: null,
        ),
      );

      await tester.tap(find.byKey(const Key('hostRematchButton')));
      await tester.pump();
      expect(fake.rematchCalls, 1);
    });
  });

  group('host during scoring', () {
    testWidgets('shows the correct answer and all submissions', (tester) async {
      await pumpHost(tester, scoringStateForHost());

      expect(find.text('CORRECT ANSWER'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('acceptedAnswers')),
          matching: find.text('Canberra'),
        ),
        findsOneWidget,
      );
      expect(inRow('p_3f9a', find.text('Sam')), findsOneWidget);
      expect(inRow('p_3f9a', find.text('canbera')), findsOneWidget);
      expect(inRow('p_b2c1', find.text('Alex')), findsOneWidget);
      expect(inRow('p_b2c1', find.text('Canberra')), findsOneWidget);
      expect(inRow(hostPlayerId, find.text('Hana (you)')), findsOneWidget);
      expect(inRow(hostPlayerId, find.text('Canbra')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('host-badge-$hostPlayerId')),
        findsOneWidget,
      );
      expect(find.text('Show standings'), findsOneWidget);
    });

    testWidgets('toggling their own submission calls hostOverride', (
      tester,
    ) async {
      await pumpHost(tester, scoringStateForHost());

      await tester.tap(find.byKey(const ValueKey('submission-$hostPlayerId')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('submission-p_b2c1')));
      await tester.pump();

      expect(fake.overrides, [
        (playerId: hostPlayerId, correct: true),
        (playerId: 'p_b2c1', correct: false),
      ]);
    });
  });
}
