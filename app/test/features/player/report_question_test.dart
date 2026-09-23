import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/core/providers/room_tokens.dart';
import 'package:fazoura_party/core/storage/room_token_store.dart';
import 'package:fazoura_party/features/player/player_game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

void main() {
  late List<http.Request> reports;
  late int status;

  // The lobby animates while it waits for players, so it never settles. Pump
  // a fixed run of frames instead of waiting for quiet.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pumpGame(WidgetTester tester, RoomState state) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    reports = [];
    status = 204;
    SharedPreferences.setMockInitialValues({});

    final store = RoomTokenStore();
    await store.save('K7QX2M', playerToken: 'player-token-1');

    final api = RoomApi(
      baseUrl: 'http://localhost:4000',
      client: MockClient((request) async {
        reports.add(request);
        return status == 204
            ? http.Response('', 204)
            : http.Response(
                jsonEncode({
                  'code': 'quiz_not_public',
                  'message': "That quiz isn't published.",
                }),
                status,
              );
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameConnectionProvider.overrideWithValue(
            FakeGameConnection(initialState: state),
          ),
          roomApiProvider.overrideWithValue(api),
          roomTokenStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(home: PlayerGameScreen(roomCode: 'K7QX2M')),
      ),
    );
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await settle(tester);
  }

  testWidgets('reports the question on screen, by its id', (tester) async {
    final state = questionStateForPlayer();
    await pumpGame(tester, state);

    await tapKey(tester, const Key('reportQuestion'));
    await tapKey(tester, const Key('reportReason-sexual'));
    await tester.enterText(
      find.byKey(const Key('reportNoteField')),
      'The photo on this one.',
    );
    await tapKey(tester, const Key('sendReport'));

    expect(reports, hasLength(1));
    final sent = jsonDecode(reports.single.body) as Map<String, dynamic>;
    expect(reports.single.url.path, '/api/rooms/K7QX2M/report');
    expect(sent['reason'], 'sexual');
    expect(sent['note'], 'The photo on this one.');
    // The question the player is looking at — the server maps it back to the
    // quiz, so no id had to be broadcast to get here.
    expect(sent['question_id'], state.question!.id);
    // Proof of being in the room, which is what stops this endpoint saying
    // which room codes are live games.
    expect(reports.single.headers['x-player-token'], 'player-token-1');
    expect(find.text('Reported. Somebody will read it.'), findsOneWidget);
  });

  testWidgets('a room with nothing chosen has nothing to report', (
    tester,
  ) async {
    await pumpGame(tester, lobbyStateWithQuiz().copyWith(packTitles: const []));

    expect(find.byKey(const Key('reportQuestion')), findsNothing);
  });

  testWidgets('a lobby with a quiz chosen can still report it', (tester) async {
    // No question on screen yet, so none is named: the server falls back to
    // the quiz the room is playing.
    await pumpGame(tester, lobbyStateWithQuiz());

    await tapKey(tester, const Key('reportQuestion'));
    await tapKey(tester, const Key('reportReason-spam'));
    await tapKey(tester, const Key('sendReport'));

    final sent = jsonDecode(reports.single.body) as Map<String, dynamic>;
    expect(sent.containsKey('question_id'), isFalse);
  });

  testWidgets('a private quiz says there is nothing to take down', (
    tester,
  ) async {
    await pumpGame(tester, questionStateForPlayer());
    status = 422;

    await tapKey(tester, const Key('reportQuestion'));
    await tapKey(tester, const Key('reportReason-hate'));
    await tapKey(tester, const Key('sendReport'));

    expect(find.byKey(const Key('reportError')), findsOneWidget);
    expect(find.text('Reported. Somebody will read it.'), findsNothing);
  });
}
