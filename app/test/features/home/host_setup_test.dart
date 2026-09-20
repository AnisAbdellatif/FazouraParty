import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_game_connection.dart';

void main() {
  late FakeGameConnection fake;
  late List<Map<String, dynamic>> roomRequests;
  late MockClient roomClient;

  Future<void> pumpHome(WidgetTester tester) async {
    // The host token is remembered on the device, so the room survives the tab
    // being closed (PROTOCOL.md §3.3).
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection();
    roomRequests = [];
    roomClient = MockClient((request) async {
      roomRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({'room_code': 'K7QX2M', 'host_token': 'host-tok'}),
        201,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameConnectionProvider.overrideWithValue(fake),
          roomApiProvider.overrideWithValue(
            RoomApi(baseUrl: 'http://localhost:4000', client: roomClient),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('the host token outlives the screen and leads back in', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('hostDisplayNameField')),
      'Hana',
    );
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);
    expect(find.text('HOSTING'), findsOneWidget);

    // A fresh app against the same device storage — what a browser refresh
    // leaves behind. The host never typed the code, so without the remembered
    // token there would be no way back to their own room (PROTOCOL.md §3.3).
    fake = FakeGameConnection();
    await tester.pumpWidget(
      ProviderScope(
        key: const Key('afterRefresh'),
        overrides: [
          gameConnectionProvider.overrideWithValue(fake),
          roomApiProvider.overrideWithValue(
            RoomApi(baseUrl: 'http://localhost:4000', client: roomClient),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await settle(tester);

    final resume = find.byKey(const Key('resumeHostingButton'));
    expect(resume, findsOneWidget);
    expect(find.text('Back to room K7QX2M'), findsOneWidget);

    await tester.tap(resume);
    await settle(tester);

    expect(fake.hostJoins, [
      (roomCode: 'K7QX2M', hostToken: 'host-tok', displayName: null),
    ]);
    expect(find.text('HOSTING'), findsOneWidget);
  });

  testWidgets('a room that ended is forgotten rather than offered again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'fazoura.room_tokens': jsonEncode([
        {
          'code': 'GONE12',
          'player_token': null,
          'host_token': 'stale',
          'saved_at': DateTime.now().toUtc().toIso8601String(),
        },
      ]),
    });
    fake = FakeGameConnection();
    fake.joinError = const GameError(code: 'room_not_found', message: 'gone');
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(const Key('resumeHostingButton')));
    await settle(tester);

    expect(find.byKey(const Key('resumeHostingButton')), findsNothing);
  });

  testWidgets('creates the room before the host chooses a quiz', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);

    expect(find.byKey(const Key('createRoomButton')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('hostDisplayNameField')),
      '  Hana ',
    );
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);

    expect(roomRequests, [<String, dynamic>{}]);
    expect(fake.hostJoins, [
      (roomCode: 'K7QX2M', hostToken: 'host-tok', displayName: 'Hana'),
    ]);
    expect(find.text('HOSTING'), findsOneWidget);
  });

  testWidgets('can host without playing along', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('playAlongSwitch')));
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);

    expect(roomRequests, [<String, dynamic>{}]);
    expect(fake.hostJoins.single.displayName, isNull);
  });
}
