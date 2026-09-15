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
  late List<Object?> requestedPacks;

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection();
    requestedPacks = [];
    final api = RoomApi(
      baseUrl: 'http://localhost:4000',
      client: MockClient((request) async {
        requestedPacks.add(
          (jsonDecode(request.body) as Map<String, dynamic>)['pack_id'],
        );
        return http.Response(
          jsonEncode({'room_code': 'K7QX2M', 'host_token': 'host-tok'}),
          201,
        );
      }),
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

  Future<void> pickGeneralKnowledge(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pack-general-knowledge')));
    await settle(tester);
  }

  testWidgets('play along (default on) joins as host with display_name', (
    tester,
  ) async {
    await pumpHome(tester);
    await pickGeneralKnowledge(tester);

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

    expect(requestedPacks, ['general-knowledge']);
    expect(fake.hostJoins, [
      (roomCode: 'K7QX2M', hostToken: 'host-tok', displayName: 'Hana'),
    ]);
    expect(find.text('HOSTING'), findsOneWidget);
  });

  testWidgets('play along off joins as host without display_name', (
    tester,
  ) async {
    await pumpHome(tester);
    await pickGeneralKnowledge(tester);

    await tester.tap(find.byKey(const Key('playAlongSwitch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);

    expect(fake.hostJoins, [
      (roomCode: 'K7QX2M', hostToken: 'host-tok', displayName: null),
    ]);
  });

  testWidgets('placeholder packs marked SOON cannot be picked', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);

    expect(find.text('SOON'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('pack-house-rules')));
    await settle(tester);

    expect(find.text("Pick tonight's\npack"), findsOneWidget);
    expect(find.byKey(const Key('playAlongSwitch')), findsNothing);
    expect(requestedPacks, isEmpty);
  });
}
