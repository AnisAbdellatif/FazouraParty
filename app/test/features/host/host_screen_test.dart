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
    tester.view.physicalSize = const Size(1200, 2400);
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

  testWidgets('shows room code, accepted answers and submissions', (
    tester,
  ) async {
    await pumpHost(tester, scoringStateForHost());

    expect(find.byKey(const Key('hostRoomCode')), findsOneWidget);
    expect(find.text('K7QX2M'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Canberra'), findsOneWidget);
    expect(find.text('Sam: canbera'), findsOneWidget);
    expect(find.text('Alex: Canberra'), findsOneWidget);
  });

  testWidgets('toggling a submission calls hostOverride', (tester) async {
    await pumpHost(tester, scoringStateForHost());

    await tester.tap(find.byKey(const ValueKey('submission-p_3f9a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submission-p_b2c1')));
    await tester.pump();

    expect(fake.overrides, [
      (playerId: 'p_3f9a', correct: true),
      (playerId: 'p_b2c1', correct: false),
    ]);
  });

  testWidgets('override toggles are disabled during the question', (
    tester,
  ) async {
    final state = scoringStateForHost().copyWith(
      phase: Phase.question,
      pausedRemainingMs: 12000,
    );
    await pumpHost(tester, state);

    final tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('submission-p_3f9a')),
    );
    expect(tile.onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('submission-p_3f9a')));
    await tester.pump();
    expect(fake.overrides, isEmpty);

    // Paused question: Resume enabled, Pause disabled.
    await tester.tap(find.byKey(const Key('hostResumeButton')));
    await tester.tap(find.byKey(const Key('hostPauseButton')));
    await tester.tap(find.byKey(const Key('hostNextButton')));
    await tester.pump();
    expect(fake.resumeCalls, 1);
    expect(fake.pauseCalls, 0);
    expect(fake.nextCalls, 1);
  });
}
