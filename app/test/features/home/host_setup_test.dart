import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fake_game_connection.dart';

void main() {
  late FakeGameConnection fake;
  late List<Map<String, dynamic>> roomRequests;

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection();
    roomRequests = [];
    final roomClient = MockClient((request) async {
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
