// Renders every screen and dialog of the app at a phone size and a desktop
// size, so they can be looked over side by side after a visual change:
//
//   cd app && flutter test tool/ui_audit/audit_test.dart
//
// Writes <screen>-m.png (360 x 740) and <screen>-d.png (1280 x 800) to
// build/ui_audit/, or to AUDIT_OUT. AUDIT_ONLY=home,report renders just those.
// Every screen is fed a made-up room (../screens.dart), so no server is needed.
// A layout overflow fails the screen it happens on, which is half the point.
//
// Under tool/ rather than test/ so `flutter test` doesn't write files.
import 'dart:convert';
import 'dart:io';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/core/providers/quiz_providers.dart';
import 'package:fazoura_party/core/providers/update_providers.dart';
import 'package:fazoura_party/features/home/home_screen.dart';
import 'package:fazoura_party/features/join/join_screen.dart';
import 'package:fazoura_party/features/player/player_game_screen.dart';
import 'package:fazoura_party/features/public_rooms/public_rooms_screen.dart';
import 'package:fazoura_party/features/quizzes/quiz_browser_screen.dart';
import 'package:fazoura_party/features/quizzes/quiz_editor_screen.dart';
import 'package:fazoura_party/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/fake_game_connection.dart';
import '../../test/support/fake_quiz_server.dart';
import '../screens.dart';

final _out = Platform.environment['AUDIT_OUT'] ?? 'build/ui_audit';

// A small Android phone, and a laptop window.
const _sizes = {'m': (Size(360, 740), 2.0), 'd': (Size(1280, 800), 1.0)};

Map<String, Object?> _sub(
  String id,
  String answer,
  bool auto, {
  bool? override,
  int right = 25,
  int wrong = -10,
}) {
  final correct = override ?? auto;
  return {
    'player_id': id,
    'answer': answer,
    'auto_correct': auto,
    'override': override,
    'correct': correct,
    'delta': correct ? right : wrong,
  };
}

final _library = [
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
];

Future<void> _browser(WidgetTester tester, {bool mine = false}) async {
  final server = FakeQuizServer(_library);
  final database = (await tester.runAsync(memoryDatabase))!;
  await pumpScreen(
    tester,
    const QuizBrowserScreen(),
    overrides: [
      quizApiProvider.overrideWithValue(server.api()),
      localDatabaseProvider.overrideWith((ref) async => database),
    ],
  );
  if (mine) {
    await tester.tap(find.byKey(const Key('quizScopeMine')));
    await settleScreen(tester);
  }
}

final _screens = <String, Future<void> Function(WidgetTester)>{
  'home': (t) => pumpScreen(t, const HomeScreen()),
  'join': (t) => pumpScreen(t, const JoinScreen()),
  'join-code': (t) => pumpScreen(t, const JoinScreen(initialCode: 'K7QX2M')),
  'public-rooms': (t) => pumpScreen(
    t,
    const PublicRoomsScreen(),
    overrides: [
      roomApiProvider.overrideWithValue(
        RoomApi(
          baseUrl: 'http://localhost:4000',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'rooms': [
                  {
                    'room_code': 'K7QX2M',
                    'phase': 'lobby',
                    'pack_titles': ['Capital Cities of the World'],
                    'player_count': 5,
                    'question_index': null,
                    'question_count': 10,
                    'room_size': 32,
                  },
                  {
                    'room_code': 'ABCDEF',
                    'phase': 'question',
                    'pack_titles': ['Film Night', 'Tech Acronyms'],
                    'player_count': 12,
                    'question_index': 3,
                    'question_count': 15,
                    'room_size': 32,
                  },
                ],
              }),
              200,
            ),
          ),
        ),
      ),
    ],
  ),
  'public-rooms-empty': (t) => pumpScreen(
    t,
    const PublicRoomsScreen(),
    overrides: [
      roomApiProvider.overrideWithValue(
        RoomApi(
          baseUrl: 'http://localhost:4000',
          client: MockClient(
            (_) async => http.Response(jsonEncode({'rooms': []}), 200),
          ),
        ),
      ),
    ],
  ),
  'settings': (t) => pumpScreen(
    t,
    const SettingsScreen(),
    overrides: [
      installedBuildProvider.overrideWithValue((
        supported: false,
        version: '',
        versionCode: 0,
      )),
    ],
  ),
  'host-setup': (t) async {
    await pumpScreen(t, const HomeScreen());
    await t.tap(find.byKey(const Key('hostGameButton')));
    await settleScreen(t);
  },
  'library': (t) => _browser(t),
  'library-mine': (t) => _browser(t, mine: true),
  'editor': (t) async {
    final database = (await t.runAsync(memoryDatabase))!;
    await pumpScreen(
      t,
      const QuizEditorScreen(),
      overrides: [
        quizApiProvider.overrideWithValue(FakeQuizServer(_library).api()),
        localDatabaseProvider.overrideWith((ref) async => database),
      ],
    );
  },
  'host-lobby-empty': (t) => pumpHost(
    t,
    room(
      phase: 'lobby',
      index: null,
      packs: const [],
      you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
      players: playerJson(scored: false).take(1).toList(),
    ),
  ),
  'host-lobby': (t) => pumpHost(
    t,
    room(
      phase: 'lobby',
      index: null,
      you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
      players: playerJson(scored: false),
    ),
  ),
  'player-lobby': (t) => pumpPlayer(
    t,
    room(
      phase: 'lobby',
      index: null,
      you: {'role': 'player', 'player_id': 'p_sami'},
      players: playerJson(scored: false),
    ),
  ),
  'player-question': (t) => pumpPlayer(
    t,
    room(
      phase: 'question',
      question: question('What is the capital of Australia?', 'easy'),
      you: {'role': 'player', 'player_id': 'p_sami', 'submission': null},
      players: playerJson(submitted: {'p_lina', 'p_omar'}),
    ),
  ),
  'player-question-arabic': (t) => pumpPlayer(
    t,
    room(
      phase: 'question',
      question: question('ما هي عاصمة أستراليا؟', 'hard'),
      you: {'role': 'player', 'player_id': 'p_sami', 'submission': null},
    ),
  ),
  'player-locked': (t) => pumpPlayer(
    t,
    room(
      phase: 'question',
      question: question('What is the capital of Australia?', 'medium'),
      you: {
        'role': 'player',
        'player_id': 'p_sami',
        'submission': {'answer': 'Canberra'},
      },
      players: playerJson(submitted: {'p_sami', 'p_lina'}),
    ),
  ),
  'host-question': (t) => pumpHost(
    t,
    room(
      phase: 'question',
      question: question('What is the capital of Australia?', 'hard'),
      you: {
        'role': 'host',
        'player_id': 'p_lina',
        'host_token': 'h',
        'submission': null,
      },
      players: playerJson(submitted: {'p_omar'}),
    ),
  ),
  'host-question-nonplaying': (t) => pumpHost(
    t,
    room(
      phase: 'question',
      question: question('What is the capital of Australia?', 'hard'),
      you: {'role': 'host', 'player_id': null, 'host_token': 'h'},
      players: playerJson(submitted: {'p_omar'}),
    ),
  ),
  'host-scoring': (t) => pumpHost(
    t,
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
        _sub('p_lina', 'Leonardo da Vinci', true),
        _sub('p_sami', 'da vinci', false, override: true),
        _sub('p_omar', 'Michelangelo', false),
      ],
    ),
  ),
  'host-leaderboard': (t) => pumpHost(
    t,
    room(
      phase: 'leaderboard',
      question: question('Who painted the Mona Lisa?', 'medium'),
      accepted: ['Leonardo da Vinci'],
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
        _sub('p_lina', 'Leonardo da Vinci', true),
        _sub('p_omar', 'Michelangelo', false),
      ],
    ),
  ),
  'player-scoring': (t) => pumpPlayer(
    t,
    room(
      phase: 'scoring',
      question: question('Who painted the Mona Lisa?', 'medium'),
      accepted: ['Leonardo da Vinci'],
      you: {
        'role': 'player',
        'player_id': 'p_omar',
        'submission': {
          'answer': 'Michelangelo',
          'correct': false,
          'delta': -10,
        },
      },
      submissions: [
        _sub('p_lina', 'Leonardo da Vinci', true),
        _sub('p_omar', 'Michelangelo', false),
      ],
    ),
  ),
  'player-leaderboard': (t) => pumpPlayer(
    t,
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
        _sub('p_lina', 'Thimphu', true, right: 50, wrong: -5),
        _sub('p_yas', 'Thimphu', true, right: 50, wrong: -5),
        _sub('p_omar', 'Paro', false, right: 50, wrong: -5),
      ],
    ),
  ),
  'host-finished': (t) => pumpHost(
    t,
    room(
      phase: 'finished',
      index: 14,
      you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
    ),
  ),
  'player-finished': (t) => pumpPlayer(
    t,
    room(
      phase: 'finished',
      index: 14,
      you: {'role': 'player', 'player_id': 'p_omar'},
    ),
  ),
  'room-closed': (t) async {
    final fake = FakeGameConnection(
      initialState: room(
        phase: 'lobby',
        index: null,
        you: {'role': 'player', 'player_id': 'p_sami'},
      ),
    );
    fake.closedCompleter.complete(RoomClosedReason.closed);
    await pumpScreen(
      t,
      const PlayerGameScreen(roomCode: roomCode),
      overrides: [gameConnectionProvider.overrideWithValue(fake)],
    );
  },
  'host-exit': (t) async {
    await pumpHost(
      t,
      room(
        phase: 'lobby',
        index: null,
        you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
        players: playerJson(scored: false),
      ),
    );
    await t.tap(find.byTooltip('Leave'));
    await settleScreen(t);
  },
  'players-sheet': (t) async {
    await pumpHost(
      t,
      room(
        phase: 'question',
        question: question('What is the capital of Australia?', 'hard'),
        you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
      ),
    );
    await t.tap(find.byKey(const Key('playersButton')));
    await settleScreen(t);
  },
  'photo-question': (t) async {
    final flag = (await t.runAsync(drawFlag))!;
    await HttpOverrides.runZoned(() async {
      await pumpPlayer(
        t,
        room(
          phase: 'question',
          question: question(
            'Which country flies this flag?',
            'hard',
            imageUrl: photoUrl,
          ),
          you: {'role': 'player', 'player_id': 'p_yas', 'submission': null},
        ),
      );
      await t.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
    }, createHttpClient: PhotoHttp(flag).createHttpClient);
  },
  'host-paused': (t) => pumpHost(
    t,
    room(
      phase: 'question',
      question: question('What is the capital of Australia?', 'hard'),
      you: {
        'role': 'host',
        'player_id': 'p_lina',
        'host_token': 'h',
        'submission': null,
      },
    ).copyWith(deadline: null, pausedRemainingMs: 12000),
  ),
  'rules': (t) async {
    // The rules not yet agreed to, so going public asks first.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(t, const HomeScreen());
    await t.tap(find.byKey(const Key('hostGameButton')));
    await settleScreen(t);
    await t.enterText(find.byKey(const Key('hostDisplayNameField')), 'Lina');
    await t.tap(find.byKey(const Key('listedSwitch')));
    await settleScreen(t);
    await t.tap(find.byKey(const Key('createRoomButton')));
    await settleScreen(t);
  },
  'size-code': (t) async {
    await pumpHost(
      t,
      room(
        phase: 'lobby',
        index: null,
        you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
        players: playerJson(scored: false).take(2).toList(),
      ),
    );
    await t.tap(find.byKey(const Key('roomSizeCodeButton')));
    await settleScreen(t);
  },
  'report': (t) async {
    await pumpPlayer(
      t,
      room(
        phase: 'question',
        question: question('What is the capital of Australia?', 'easy'),
        you: {'role': 'player', 'player_id': 'p_sami', 'submission': null},
      ),
    );
    await t.tap(find.byKey(const Key('reportQuestion')));
    await settleScreen(t);
  },
};

void main() {
  setUpAll(loadScreenFonts);
  setUp(
    // A test, but under tool/ so `flutter test` doesn't run it.
    // ignore: invalid_use_of_visible_for_testing_member
    () => SharedPreferences.setMockInitialValues({
      'fazoura.community_rules_accepted': 1,
    }),
  );
  final only = Platform.environment['AUDIT_ONLY']?.split(',');
  for (final MapEntry(key: name, value: build) in _screens.entries) {
    if (only != null && !only.contains(name)) continue;
    for (final MapEntry(key: suffix, value: (size, ratio)) in _sizes.entries) {
      testWidgets('$name-$suffix', (tester) async {
        screenFrame = (size: size, ratio: ratio);
        await build(tester);
        await saveScreen(tester, '$_out/$name-$suffix.png');
      });
    }
  }
}
