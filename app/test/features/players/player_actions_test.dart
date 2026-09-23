import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/host/host_screen.dart';
import 'package:fazoura_party/features/players/player_actions.dart';
import 'package:fazoura_party/features/room_closed/room_closed_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

void main() {
  PlayerSummary player(String id, {bool host = false}) => PlayerSummary(
    id: id,
    name: id,
    score: 0,
    connected: true,
    hasSubmitted: false,
    isHost: host,
  );

  RoomState room({required Role role, required bool listed, String? you}) =>
      lobbyStateWithQuiz().copyWith(
        listed: listed,
        players: [player('Hana', host: true), player('Sam'), player('Kim')],
        you: You(role: role, playerId: you),
      );

  group('who may do what', () {
    test('the host removes anybody but the host; nobody reports by code', () {
      final state = room(role: Role.host, listed: false, you: 'Hana');
      expect(playerActionsFor(state, player('Sam')), (
        remove: true,
        report: false,
      ));
      expect(playerActionsFor(state, player('Hana', host: true)), (
        remove: false,
        report: false,
      ));
    });

    test('in a public room anybody reports anybody else', () {
      final state = room(role: Role.player, listed: true, you: 'Sam');
      expect(playerActionsFor(state, player('Kim')), (
        remove: false,
        report: true,
      ));
      expect(playerActionsFor(state, player('Sam')), (
        remove: false,
        report: false,
      ));
    });

    test('a player in a room joined by code has nothing to do', () {
      expect(
        anyPlayerActions(room(role: Role.player, listed: false, you: 'Sam')),
        isFalse,
      );
    });
  });

  testWidgets(
    'the host removes a player from the players sheet, after asking',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final state = room(role: Role.host, listed: false, you: 'Hana');
      final fake = FakeGameConnection(initialState: state);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [gameConnectionProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: HostScreen(roomCode: 'K7QX2M')),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('playersButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('removePlayer-Sam')));
      await tester.pumpAndSettle();
      expect(fake.removedPlayers, isEmpty, reason: 'nothing before confirming');

      await tester.tap(find.byKey(const Key('confirmRemovePlayer')));
      await tester.pumpAndSettle();
      expect(fake.removedPlayers, ['Sam']);
    },
  );

  testWidgets('a removed player is told why the room went away', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RoomClosedView(reason: RoomClosedReason.removed)),
      ),
    );
    expect(find.text('The host removed you from the room.'), findsOneWidget);
  });
}
