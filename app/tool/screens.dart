// What the screen-rendering scripts under tool/ share: the fonts, a made-up
// room at any phase, a flag to stand in for a photo, and pumping a screen at a
// chosen size and saving what it draws.
//
// Used by store_screenshots/ (the Play listing) and ui_audit/ (every screen,
// phone and desktop). Not a test itself, so `flutter test` never runs it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/host/host_screen.dart';
import 'package:fazoura_party/features/player/player_game_screen.dart';
import 'package:fazoura_party/shared/theme/fz_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fake_game_connection.dart';

const roomCode = 'K7QX2M';
const photoUrl = 'https://fazoura.test/flag.png';

// ---------------------------------------------------------------------------
// The party every screenshot shows.

const players = [
  ('p_lina', 'Lina', 185, 42),
  ('p_sami', 'Sami', 160, 350),
  ('p_yas', 'Yasmine', 135, 205),
  ('p_omar', 'Omar', 95, 150),
  ('p_nour', 'Nour', 80, 275),
  ('p_karim', 'Karim', 60, 95),
  ('p_maya', 'Maya', 35, 320),
  ('p_adam', 'Adam', 10, 180),
];

List<Map<String, Object?>> playerJson({
  bool scored = true,
  Set<String> submitted = const {},
}) => [
  for (final (id, name, score, hue) in players)
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

Map<String, Object?> points(String difficulty) => switch (difficulty) {
  'easy' => {'right': 10, 'wrong': -15, 'skipped': -10},
  'medium' => {'right': 25, 'wrong': -10, 'skipped': -10},
  _ => {'right': 50, 'wrong': -5, 'skipped': -10},
};

Map<String, Object?> question(
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
  'points': points(difficulty),
};

RoomState room({
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
    'protocol_minor': 10,
    'listed': false,
    'room_size': 32,
    'room_size_limit': 32,
    'room_code': roomCode,
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
    'players': players ?? playerJson(),
    'you': you,
    'submissions': submissions,
  });
}

// ---------------------------------------------------------------------------
// Rendering.

Future<void> loadScreenFonts() async {
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

/// The logical size a screen is laid out at, and the device pixel ratio it is
/// drawn with. Set it before pumping; every later pump and save uses it.
({Size size, double ratio}) screenFrame = (
  size: const Size(360, 740),
  ratio: 2,
);

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = screenFrame.size * screenFrame.ratio;
  tester.view.devicePixelRatio = screenFrame.ratio;
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
  await settleScreen(tester);
}

final _boundary = GlobalKey();

/// The app's motion includes animations that repeat while on screen, so
/// pumpAndSettle never returns (test/support/pump.dart).
Future<void> settleScreen(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Writes what is on screen to [path] as a PNG, at the frame's pixel ratio.
Future<void> saveScreen(WidgetTester tester, String path) async {
  // Network photos decode off the fake clock.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await settleScreen(tester);
  final render =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: screenFrame.ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

// ---------------------------------------------------------------------------
// The photo question's photo: a flag, drawn here rather than taken from
// anywhere, so the listing shows nobody's artwork or trademark.

Future<Uint8List> drawFlag() async {
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
class PhotoHttp extends HttpOverrides {
  PhotoHttp(this.bytes);
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

Future<void> pumpHost(WidgetTester tester, RoomState state) => pumpScreen(
  tester,
  const HostScreen(roomCode: roomCode),
  overrides: [
    gameConnectionProvider.overrideWithValue(
      FakeGameConnection(initialState: state),
    ),
  ],
);

Future<void> pumpPlayer(WidgetTester tester, RoomState state) => pumpScreen(
  tester,
  const PlayerGameScreen(roomCode: roomCode),
  overrides: [
    gameConnectionProvider.overrideWithValue(
      FakeGameConnection(initialState: state),
    ),
  ],
);
