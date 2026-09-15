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

  Future<void> pumpHome(WidgetTester tester) async {
    fake = FakeGameConnection();
    final api = RoomApi(
      baseUrl: 'http://localhost:4000',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'room_code': 'K7QX2M', 'host_token': 'host-tok'}),
          201,
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameConnectionProvider.overrideWithValue(fake),
          roomApiProvider.overrideWithValue(api),
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

  testWidgets('play along (default on) joins as host with display_name', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('playAlongSwitch')))
          .value,
      isTrue,
    );

    // An empty name is rejected while playing along.
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await tester.pump();
    expect(find.text('Enter a display name'), findsOneWidget);
    expect(fake.hostJoins, isEmpty);

    await tester.enterText(
      find.byKey(const Key('hostDisplayNameField')),
      '  Hana ',
    );
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);

    expect(fake.hostJoins, [
      (roomCode: 'K7QX2M', hostToken: 'host-tok', displayName: 'Hana'),
    ]);
    expect(find.text('Hosting'), findsOneWidget);
  });

  testWidgets('play along off joins as host without display_name', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('playAlongSwitch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);

    expect(fake.hostJoins, [
      (roomCode: 'K7QX2M', hostToken: 'host-tok', displayName: null),
    ]);
  });
}
