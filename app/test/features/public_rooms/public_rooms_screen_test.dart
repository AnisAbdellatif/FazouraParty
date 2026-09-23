import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/join/join_screen.dart';
import 'package:fazoura_party/features/public_rooms/public_rooms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // These are about what happens once the community rules are agreed to;
  // community_rules_test.dart is about the agreeing.
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'fazoura.community_rules_accepted': 1,
    }),
  );

  late int requests;

  Future<void> pumpList(WidgetTester tester, List<Object> rooms) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    requests = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roomApiProvider.overrideWithValue(
            RoomApi(
              baseUrl: 'http://localhost:4000',
              client: MockClient((_) async {
                requests++;
                return http.Response(jsonEncode({'rooms': rooms}), 200);
              }),
            ),
          ),
        ],
        child: const MaterialApp(home: PublicRoomsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Map<String, Object?> room(
    String code, {
    String phase = 'lobby',
    List<String> titles = const ['Capitals'],
    int players = 2,
    int? questionIndex,
    int? roomSize,
  }) => {
    'room_code': code,
    'phase': phase,
    'pack_titles': titles,
    'player_count': players,
    'question_index': questionIndex,
    'question_count': 10,
    'room_size': ?roomSize,
  };

  testWidgets('shows each room by what it plays and where it is', (
    tester,
  ) async {
    await pumpList(tester, [
      room('AAAAAA', titles: ['Capitals', 'Flags'], players: 1),
      room('BBBBBB', phase: 'question', questionIndex: 3, players: 5),
      room('CCCCCC', titles: []),
    ]);

    expect(find.text('Capitals · Flags'), findsOneWidget);
    expect(find.text('Waiting to start · 1 player'), findsOneWidget);
    expect(find.text('Question 4 of 10 · 5 players'), findsOneWidget);
    expect(find.text('Choosing quizzes…'), findsOneWidget);
  });

  testWidgets('says how full a room is when the host sent its size', (
    tester,
  ) async {
    await pumpList(tester, [room('AAAAAA', players: 3, roomSize: 16)]);

    expect(find.text('Waiting to start · 3 / 16 players'), findsOneWidget);
  });

  testWidgets('tapping a room opens Join with its code filled in', (
    tester,
  ) async {
    await pumpList(tester, [room('K7QX2M')]);

    await tester.tap(find.byKey(const ValueKey('publicRoom-K7QX2M')));
    await tester.pumpAndSettle();

    final join = tester.widget<JoinScreen>(find.byType(JoinScreen));
    expect(join.initialCode, 'K7QX2M');
    // A listed room is always online: nothing to ask about Wi-Fi.
    expect(find.byKey(const Key('joinOverLanSwitch')), findsNothing);
  });

  testWidgets('says so when nobody has listed a room', (tester) async {
    await pumpList(tester, []);
    expect(find.byKey(const Key('noRooms')), findsOneWidget);
  });

  testWidgets('keeps itself fresh while open', (tester) async {
    await pumpList(tester, [room('K7QX2M')]);
    expect(requests, 1);

    await tester.pump(PublicRoomsScreen.refreshEvery);
    await tester.pump();
    expect(requests, 2);

    // Gone from the screen, so no more polling.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(PublicRoomsScreen.refreshEvery * 2);
    expect(requests, 2);
  });
}
