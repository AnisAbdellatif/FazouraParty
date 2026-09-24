// Renders the Google Play phone screenshots from the app's real screens.
//
//   cd app && flutter test tool/store_screenshots/screenshots_test.dart
//   store_listing/render.sh
//
// Each test pumps one screen with a made-up room, at a 9:16 phone size, and
// writes it to store_listing/screenshots/raw/. render.sh then frames each one
// with its caption (store_listing/screenshots/frame.svg). This lives under
// tool/ rather than test/ so `flutter test` doesn't write files on every run.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/core/providers/quiz_providers.dart';
import 'package:fazoura_party/features/home/home_screen.dart';
import 'package:fazoura_party/features/host/host_screen.dart';
import 'package:fazoura_party/features/player/player_game_screen.dart';
import 'package:fazoura_party/features/quizzes/quiz_browser_screen.dart';
import 'package:fazoura_party/shared/theme/fz_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/fake_game_connection.dart';
import '../../test/support/fake_quiz_server.dart';

const _out = '../store_listing/screenshots/raw';

// 9:16, as Play requires, and 1080 x 1920 once multiplied out.
const _logical = Size(432, 768);
const _ratio = 2.5;

const _code = 'K7QX2M';
const _photoUrl = 'https://fazoura.test/flag.png';

// ---------------------------------------------------------------------------
// The party every screenshot shows.

const _players = [
  ('p_lina', 'Lina', 185, 42),
  ('p_sami', 'Sami', 160, 350),
  ('p_yas', 'Yasmine', 135, 205),
  ('p_omar', 'Omar', 95, 150),
  ('p_nour', 'Nour', 80, 275),
  ('p_karim', 'Karim', 60, 95),
  ('p_maya', 'Maya', 35, 320),
  ('p_adam', 'Adam', 10, 180),
];

List<Map<String, Object?>> _playerJson({
  bool scored = true,
  Set<String> submitted = const {},
}) => [
  for (final (id, name, score, hue) in _players)
    {
      'id': id,
      'name': name,
      'score': scored ? score : 0,
      'connected': true,
      'has_submitted': submitted.contains(id),
      'is_host': id == 'p_lina',
      'avatar_hue': hue,
    },
];

Map<String, Object?> _points(String difficulty) => switch (difficulty) {
  'easy' => {'right': 10, 'wrong': -15, 'skipped': -10},
  'medium' => {'right': 25, 'wrong': -10, 'skipped': -10},
  _ => {'right': 50, 'wrong': -5, 'skipped': -10},
};

Map<String, Object?> _question(
  String prompt,
  String difficulty, {
  String? imageUrl,
}) => {
  'id': 'q_07',
  'type': imageUrl == null ? 'text' : 'text_photo',
  'prompt': prompt,
  'image_url': imageUrl,
  'time_limit_ms': 30000,
  'difficulty': difficulty,
  'points': _points(difficulty),
};

RoomState _room({
  required String phase,
  Map<String, Object?>? question,
  List<String>? accepted,
  int? index = 6,
  required Map<String, Object?> you,
  List<Map<String, Object?>>? players,
  List<Map<String, Object?>>? submissions,
  List<String> packs = const ['Capital Cities of the World', 'Flags'],
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return RoomState.fromJson({
    'protocol_version': 9,
    'protocol_minor': 9,
    'listed': false,
    'room_size': 32,
    'room_size_limit': 32,
    'room_code': _code,
    'mode': 'cloud',
    'phase': phase,
    'server_time': now,
    'pack_titles': packs,
    'question_index': index,
    'question_count': 15,
    'game_number': 1,
    'settings': {
      'question_count': 15,
      'time_limit_ms': 30000,
      'difficulty_multiplier': true,
      'difficulties': ['easy', 'medium', 'hard'],
      'available_difficulties': ['easy', 'medium', 'hard'],
      'max_question_count': 40,
      'min_time_limit_ms': 10000,
      'max_time_limit_ms': 120000,
    },
    'question': question,
    // A little under the 30 s the question was given, and never reached.
    'deadline': question == null || phase != 'question' ? null : now + 19400,
    'paused_remaining_ms': null,
    'accepted_answers': accepted,
    'players': players ?? _playerJson(),
    'you': you,
    'submissions': submissions,
  });
}

// ---------------------------------------------------------------------------
// Rendering.

Future<void> _loadFonts() async {
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  // A phone draws the few symbols the bundled fonts lack (the host's auto ✓/✗)
  // from its system font. A test has none, so borrow this machine's, under the
  // `monospace` name FzTheme already falls back to.
  // flutter_tester points fontconfig at Flutter's own fonts, so ask with the
  // parent environment's font configuration rather than the test's.
  final environment = Map.of(Platform.environment)
    ..removeWhere((key, _) => key.startsWith('FONTCONFIG'));
  final match = await Process.run(
    'fc-list',
    [':charset=2713 2717:spacing=mono', 'file'],
    environment: environment,
    includeParentEnvironment: false,
  );
  final files = match.exitCode == 0
      ? (match.stdout as String)
            .split('\n')
            .map((line) => line.split(':').first.trim())
            .where((file) => file.endsWith('.ttf') || file.endsWith('.otf'))
            .toList()
      : <String>[];
  if (files.isEmpty) {
    stderr.writeln('No system font with ✓ and ✗ found; they will be boxes.');
    return;
  }
  // DejaVu where it is installed, which is most Linux machines, so two
  // machines render the same glyph.
  final path = files.firstWhere(
    (file) => file.endsWith('DejaVuSansMono.ttf'),
    orElse: () => files.first,
  );
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    'monospace',
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = _logical * _ratio;
  tester.view.devicePixelRatio = _ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildFzTheme(
            fz: FzTheme.fallback,
            applyTextFont: (base) => base.apply(fontFamily: 'Figtree'),
          ),
          home: screen,
        ),
      ),
    ),
  );
  await _settle(tester);
}

final _boundary = GlobalKey();

/// The app's motion includes animations that repeat while on screen, so
/// pumpAndSettle never returns (test/support/pump.dart).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  // Network photos decode off the fake clock.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await _settle(tester);
  final render =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: _ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_out/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

// ---------------------------------------------------------------------------
// The photo question's photo: a flag, drawn here rather than taken from
// anywhere, so the listing shows nobody's artwork or trademark.

Future<Uint8List> _flag() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const colors = [
    Color(0xFFEA2839),
    Color(0xFF1A206D),
    Color(0xFFFFD500),
    Color(0xFF00A551),
  ];
  for (var i = 0; i < colors.length; i++) {
    canvas.drawRect(
      Rect.fromLTWH(0, i * 100.0, 600, 100),
      Paint()..color = colors[i],
    );
  }
  final image = await recorder.endRecording().toImage(600, 400);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Serves [bytes] to every request, so `Image.network` has something to show.
class _PhotoHttp extends HttpOverrides {
  _PhotoHttp(this.bytes);
  final Uint8List bytes;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(bytes);
}

class _Client implements HttpClient {
  _Client(this.bytes);
  final Uint8List bytes;
  @override
  bool autoUncompress = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientResponse> close() async => _Response(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------

Future<void> _host(WidgetTester tester, RoomState state) => _pump(
  tester,
  const HostScreen(roomCode: _code),
  overrides: [
    gameConnectionProvider.overrideWithValue(
      FakeGameConnection(initialState: state),
    ),
  ],
);

Future<void> _player(WidgetTester tester, RoomState state) => _pump(
  tester,
  const PlayerGameScreen(roomCode: _code),
  overrides: [
    gameConnectionProvider.overrideWithValue(
      FakeGameConnection(initialState: state),
    ),
  ],
);

void main() {
  setUpAll(_loadFonts);
  setUp(
    // A test, but under tool/ so `flutter test` doesn't run it.
    // ignore: invalid_use_of_visible_for_testing_member
    () => SharedPreferences.setMockInitialValues({
      'fazoura.community_rules_accepted': 1,
    }),
  );

  testWidgets('home', (tester) async {
    await _pump(tester, const HomeScreen());
    await _save(tester, '1-home');
  });

  testWidgets('lobby', (tester) async {
    await _host(
      tester,
      _room(
        phase: 'lobby',
        index: null,
        you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
        players: _playerJson(scored: false),
      ),
    );
    await _save(tester, '2-lobby');
  });

  testWidgets('question', (tester) async {
    await _player(
      tester,
      _room(
        phase: 'question',
        question: _question('What is the capital of Australia?', 'easy'),
        you: {'role': 'player', 'player_id': 'p_sami', 'submission': null},
        players: _playerJson(submitted: {'p_lina', 'p_omar', 'p_maya'}),
      ),
    );
    await tester.enterText(find.byKey(const Key('answerField')), 'Canberra');
    await _settle(tester);
    await _save(tester, '3-question');
  });

  testWidgets('photo question', (tester) async {
    final flag = (await tester.runAsync(_flag))!;
    await HttpOverrides.runZoned(() async {
      await _player(
        tester,
        _room(
          phase: 'question',
          question: _question(
            'Which country flies this flag?',
            'hard',
            imageUrl: _photoUrl,
          ),
          you: {'role': 'player', 'player_id': 'p_yas', 'submission': null},
          players: _playerJson(submitted: {'p_sami', 'p_nour'}),
        ),
      );
      await tester.enterText(find.byKey(const Key('answerField')), 'Mauritius');
      await _settle(tester);
      await _save(tester, '4-photo');
    }, createHttpClient: _PhotoHttp(flag).createHttpClient);
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

    await _host(
      tester,
      _room(
        phase: 'scoring',
        question: _question('Who painted the Mona Lisa?', 'medium'),
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
    await _player(
      tester,
      _room(
        phase: 'leaderboard',
        question: _question('What is the capital of Bhutan?', 'hard'),
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
    await _pump(
      tester,
      const QuizBrowserScreen(),
      overrides: [
        quizApiProvider.overrideWithValue(server.api()),
        localDatabaseProvider.overrideWith((ref) async => database),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('quizCard-capitals')));
    await _settle(tester);
    await _save(tester, '7-library');
  });

  testWidgets('finished', (tester) async {
    await _host(
      tester,
      _room(
        phase: 'finished',
        index: 14,
        you: {'role': 'host', 'player_id': 'p_lina', 'host_token': 'h'},
      ),
    );
    await _save(tester, '8-finished');
  });
}
