import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/core/providers/quiz_providers.dart';
import 'package:fazoura_party/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fake_quiz_server.dart';

const _quizId = '11111111-1111-1111-1111-111111111111';

void main() {
  late FakeGameConnection fake;
  late List<Map<String, dynamic>> roomRequests;

  Future<void> pumpHome(
    WidgetTester tester, {
    List<LocalQuiz> local = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection();
    roomRequests = [];
    final server = FakeQuizServer([
      const QuizDocument(
        id: _quizId,
        slug: 'general-knowledge',
        title: 'General Knowledge',
        source: 'builtin',
        visibility: 'public',
        questionCount: 20,
      ),
    ]);
    final roomClient = MockClient((request) async {
      roomRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({'room_code': 'K7QX2M', 'host_token': 'host-tok'}),
        201,
      );
    });
    // Real async: sembast work doesn't advance under the fake test clock.
    final database = (await tester.runAsync(() async {
      final db = await memoryDatabase();
      await seedLocal(db, local);
      return db;
    }))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameConnectionProvider.overrideWithValue(fake),
          roomApiProvider.overrideWithValue(
            RoomApi(baseUrl: 'http://localhost:4000', client: roomClient),
          ),
          quizApiProvider.overrideWithValue(server.api()),
          localDatabaseProvider.overrideWith((ref) async => database),
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

  Future<void> pick(
    WidgetTester tester,
    String cardId, {
    bool mine = false,
  }) async {
    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);
    if (mine) {
      await tester.tap(find.byKey(const Key('quizScopeMine')));
      await settle(tester);
    }
    await tester.tap(find.byKey(ValueKey('quizCard-$cardId')));
    await settle(tester);
  }

  testWidgets('play along (default on) joins as host with display_name', (
    tester,
  ) async {
    await pumpHome(tester);
    await pick(tester, _quizId);

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

    expect(roomRequests, [
      {'quiz_id': _quizId},
    ]);
    expect(fake.hostJoins, [
      (roomCode: 'K7QX2M', hostToken: 'host-tok', displayName: 'Hana'),
    ]);
    expect(find.text('HOSTING'), findsOneWidget);
  });

  testWidgets('play along off joins as host without display_name', (
    tester,
  ) async {
    await pumpHome(tester);
    await pick(tester, _quizId);

    await tester.tap(find.byKey(const Key('playAlongSwitch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);

    expect(fake.hostJoins, [
      (roomCode: 'K7QX2M', hostToken: 'host-tok', displayName: null),
    ]);
  });

  testWidgets('a private quiz is sent inline with its photo data', (
    tester,
  ) async {
    final photo = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    await pumpHome(
      tester,
      local: [
        localQuiz(
          'mine',
          'Secret Party',
          questions: [
            QuizQuestion(
              type: QuizQuestion.typePhoto,
              prompt: 'Which film?',
              acceptedAnswers: const ['Alien'],
              image: QuizImage(key: 'old.jpg', data: photo),
            ),
          ],
        ),
      ],
    );
    await pick(tester, 'mine', mine: true);

    await tester.tap(find.byKey(const Key('playAlongSwitch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);

    final body = roomRequests.single;
    expect(body.containsKey('quiz_id'), isFalse);
    final quiz = body['quiz'] as Map<String, dynamic>;
    expect(quiz['title'], 'Secret Party');
    final question = (quiz['questions'] as List).single as Map<String, dynamic>;
    expect(question['accepted_answers'], ['Alien']);
    expect((question['image'] as Map)['data'], photo);
    expect((question['image'] as Map)['key'], isNull);
    expect(fake.hostJoins, hasLength(1));
  });

  testWidgets('a published local quiz is hosted by its server id', (
    tester,
  ) async {
    await pumpHome(
      tester,
      local: [
        localQuiz(
          'shared',
          'Shared Night',
          visibility: 'public',
          publishedId: 'pub-7',
        ),
      ],
    );
    await pick(tester, 'shared', mine: true);

    await tester.tap(find.byKey(const Key('playAlongSwitch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('createRoomButton')));
    await settle(tester);

    expect(roomRequests, [
      {'quiz_id': 'pub-7'},
    ]);
  });

  testWidgets('backing out of the quiz browser creates no room', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('hostGameButton')));
    await settle(tester);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.byKey(const Key('hostGameButton')), findsOneWidget);
    expect(roomRequests, isEmpty);
  });
}
