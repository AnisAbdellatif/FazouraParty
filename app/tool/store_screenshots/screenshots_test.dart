// Renders the Google Play phone screenshots from the app's real screens.
//
//   cd app && flutter test tool/store_screenshots/screenshots_test.dart
//   store_listing/render.sh
//
// Each test pumps one screen with a made-up room, at a 9:16 phone size, and
// writes it to store_listing/screenshots/raw/. render.sh then frames each one
// with its caption (store_listing/screenshots/frame.svg). This lives under
// tool/ rather than test/ so `flutter test` doesn't write files on every run.
import 'dart:io';

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/quiz_providers.dart';
import 'package:fazoura_party/features/home/home_screen.dart';
import 'package:fazoura_party/features/quizzes/quiz_browser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/fake_quiz_server.dart';
import '../screens.dart';

const _out = '../store_listing/screenshots/raw';

// 9:16, as Play requires, and 1080 x 1920 once multiplied out.
const _size = Size(432, 768);
const _ratio = 2.5;

Future<void> _save(WidgetTester tester, String name) =>
    saveScreen(tester, '$_out/$name.png');

void main() {
  setUpAll(() async {
    screenFrame = (size: _size, ratio: _ratio);
    await loadScreenFonts();
  });
  setUp(
    // A test, but under tool/ so `flutter test` doesn't run it.
    // ignore: invalid_use_of_visible_for_testing_member
    () => SharedPreferences.setMockInitialValues({
      'fazoura.community_rules_accepted': 1,
    }),
  );

  testWidgets('home', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await _save(tester, '1-home');
  });

  testWidgets('lobby', (tester) async {
    await pumpHost(
      tester,
      room(
        phase: 'lobby',
        index: null,
        you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
        players: playerJson(scored: false),
      ),
    );
    await _save(tester, '2-lobby');
  });

  testWidgets('question', (tester) async {
    await pumpPlayer(
      tester,
      room(
        phase: 'question',
        question: question('What is the capital of Australia?', 'easy'),
        you: {'role': 'player', 'player_id': 'p_sami', 'submission': null},
        players: playerJson(submitted: {'p_lina', 'p_omar', 'p_maya'}),
      ),
    );
    await tester.enterText(find.byKey(const Key('answerField')), 'Canberra');
    await settleScreen(tester);
    await _save(tester, '3-question');
  });

  testWidgets('photo question', (tester) async {
    final flag = (await tester.runAsync(drawFlag))!;
    await HttpOverrides.runZoned(() async {
      await pumpPlayer(
        tester,
        room(
          phase: 'question',
          question: question(
            'Which country flies this flag?',
            'hard',
            imageUrl: photoUrl,
          ),
          you: {'role': 'player', 'player_id': 'p_yas', 'submission': null},
          players: playerJson(submitted: {'p_sami', 'p_nour'}),
        ),
      );
      await tester.enterText(find.byKey(const Key('answerField')), 'Mauritius');
      await settleScreen(tester);
      await _save(tester, '4-photo');
    }, createHttpClient: PhotoHttp(flag).createHttpClient);
  });

  testWidgets('host override', (tester) async {
    Map<String, Object?> sub(
      String id,
      String answer,
      bool auto, {
      bool? override,
    }) {
      final correct = override ?? auto;
      return {
        'player_id': id,
        'answer': answer,
        'auto_correct': auto,
        'override': override,
        'correct': correct,
        'delta': correct ? 25 : -10,
      };
    }

    await pumpHost(
      tester,
      room(
        phase: 'scoring',
        question: question('Who painted the Mona Lisa?', 'medium'),
        accepted: ['Leonardo da Vinci', 'Leonardo'],
        you: {
          'role': 'host',
          'player_id': 'p_lina',
          'host_token': 'h',
          'submission': {
            'answer': 'Leonardo da Vinci',
            'correct': true,
            'delta': 25,
          },
        },
        submissions: [
          sub('p_lina', 'Leonardo da Vinci', true),
          sub('p_sami', 'da vinci', false, override: true),
          sub('p_yas', 'leonardo', true),
          sub('p_omar', 'Michelangelo', false),
          sub('p_nour', 'Da Vinchi', false),
          sub('p_karim', 'Raphael', false),
        ],
      ),
    );
    await _save(tester, '5-override');
  });

  testWidgets('leaderboard', (tester) async {
    Map<String, Object?> sub(String id, String answer, bool correct) => {
      'player_id': id,
      'answer': answer,
      'auto_correct': correct,
      'override': null,
      'correct': correct,
      'delta': correct ? 50 : -5,
    };
    await pumpPlayer(
      tester,
      room(
        phase: 'leaderboard',
        question: question('What is the capital of Bhutan?', 'hard'),
        accepted: ['Thimphu'],
        you: {
          'role': 'player',
          'player_id': 'p_yas',
          'submission': {'answer': 'Thimphu', 'correct': true, 'delta': 50},
        },
        submissions: [
          sub('p_lina', 'Thimphu', true),
          sub('p_sami', 'Kathmandu', false),
          sub('p_yas', 'Thimphu', true),
          sub('p_omar', 'Paro', false),
        ],
      ),
    );
    await _save(tester, '6-leaderboard');
  });

  testWidgets('library', (tester) async {
    final server = FakeQuizServer([
      QuizDocument(
        id: 'capitals',
        title: 'Capital Cities of the World',
        description: 'One question for each of the 195 countries.',
        visibility: 'public',
        source: 'builtin',
        tags: const ['geography', 'world', 'capitals'],
        questionCount: 195,
      ),
      QuizDocument(
        id: 'acronyms',
        title: 'Tech Acronyms',
        description: 'The three- and four-letter words that run the internet.',
        visibility: 'public',
        source: 'builtin',
        tags: const ['technology', 'computing'],
        questionCount: 55,
      ),
      QuizDocument(
        id: 'films',
        title: 'Film Night',
        description: 'Famous lines, directors and the films they came from.',
        visibility: 'public',
        tags: const ['movies', 'pop culture'],
        questionCount: 40,
      ),
      QuizDocument(
        id: 'kitchen',
        title: 'Around the Kitchen',
        description: 'Dishes, spices and where they come from.',
        visibility: 'public',
        tags: const ['food', 'world'],
        questionCount: 32,
        hasPhotos: true,
      ),
    ]);
    final database = (await tester.runAsync(memoryDatabase))!;
    await pumpScreen(
      tester,
      const QuizBrowserScreen(),
      overrides: [
        quizApiProvider.overrideWithValue(server.api()),
        localDatabaseProvider.overrideWith((ref) async => database),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('quizCard-capitals')));
    await settleScreen(tester);
    await _save(tester, '7-library');
  });

  testWidgets('finished', (tester) async {
    await pumpHost(
      tester,
      room(
        phase: 'finished',
        index: 14,
        you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
      ),
    );
    await _save(tester, '8-finished');
  });
}
