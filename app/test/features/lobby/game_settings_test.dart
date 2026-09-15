import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/host/host_screen.dart';
import 'package:fazoura_party/features/lobby/lobby_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

RoomState lobbyState({required Role role}) => exampleRoomState().copyWith(
  phase: Phase.lobby,
  question: null,
  questionIndex: null,
  deadline: null,
  you: You(role: role, playerId: 'p_3f9a'),
);

void main() {
  late FakeGameConnection fake;

  Future<void> pump(WidgetTester tester, Widget home, RoomState state) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection(initialState: state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Text textByKey(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key)));

  testWidgets('host edits question count and time per question', (
    tester,
  ) async {
    await pump(
      tester,
      const HostScreen(roomCode: 'K7QX2M'),
      lobbyState(role: Role.host),
    );

    expect(find.byKey(const Key('gameSettingsEditor')), findsOneWidget);
    expect(textByKey(tester, 'questionCountValue').data, '10');
    expect(textByKey(tester, 'timeLimitValue').data, '30s');

    await tester.tap(find.byKey(const ValueKey('timeChip-20')));
    await tester.pump();
    expect(fake.configures, [
      (questionCount: 10, timeLimitMs: 20000, difficultyMultiplier: false),
    ]);
    expect(textByKey(tester, 'timeLimitValue').data, '20s');

    final slider = tester.widget<Slider>(
      find.byKey(const Key('questionCountSlider')),
    );
    expect((slider.min, slider.max, slider.divisions), (1.0, 10.0, 9));
    slider.onChanged!(4);
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const Key('questionCountSlider')))
        .onChangeEnd!(4);
    await tester.pump();

    expect(fake.configures.last, (
      questionCount: 4,
      timeLimitMs: 20000,
      difficultyMultiplier: false,
    ));
    expect(textByKey(tester, 'questionCountValue').data, '4');

    await tester.tap(find.byKey(const Key('difficultyBonusSwitch')));
    await tester.pump();
    expect(fake.configures.last, (
      questionCount: 4,
      timeLimitMs: 20000,
      difficultyMultiplier: true,
    ));
  });

  testWidgets('the question slider goes up to 20 when the pack allows', (
    tester,
  ) async {
    await pump(
      tester,
      const HostScreen(roomCode: 'K7QX2M'),
      lobbyState(role: Role.host).copyWith(
        settings: const GameSettings(
          questionCount: 20,
          timeLimitMs: 30000,
          maxQuestionCount: 20,
        ),
      ),
    );

    final slider = tester.widget<Slider>(
      find.byKey(const Key('questionCountSlider')),
    );
    expect((slider.max, slider.divisions), (20.0, 19));
  });

  testWidgets('players see the settings read-only', (tester) async {
    final state = lobbyState(role: Role.player).copyWith(
      questionCount: 5,
      settings: const GameSettings(
        questionCount: 5,
        timeLimitMs: 45000,
        maxQuestionCount: 10,
        difficultyMultiplier: true,
      ),
    );
    await pump(tester, Scaffold(body: LobbyView(state: state)), state);

    expect(find.byKey(const Key('gameSettingsEditor')), findsNothing);
    expect(
      textByKey(tester, 'lobbyGameSummary').data,
      'General Knowledge · 5 questions · 45s each · difficulty bonus',
    );
  });
}
