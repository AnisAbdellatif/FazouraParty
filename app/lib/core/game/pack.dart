/// Immutable pack snapshot used by a LAN-hosted room.
///
/// Dart port of `server/lib/fazoura/game/pack.ex`. The room copies the pack
/// when it is created, so editing a quiz mid-game can never affect a running
/// room (AGENTS.md §4).
library;

import '../models/quiz.dart';

const _defaultTimeLimitMs = 30000;
const _difficulties = {'easy', 'medium', 'hard'};

class PackQuestion {
  const PackQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    required this.acceptedAnswers,
    required this.timeLimitMs,
    this.imageUrl,
    this.difficulty = 'easy',
  });

  final String id;
  final String type;
  final String prompt;
  final List<String> acceptedAnswers;
  final int timeLimitMs;

  /// On LAN this points at the hosting device itself, e.g.
  /// `http://192.168.1.20:4040/api/room-images/<key>` — reachable on the
  /// local network only, but an ordinary URL as far as any client is
  /// concerned (PROTOCOL.md §5.1).
  final String? imageUrl;
  final String difficulty;

  PackQuestion copyWith({int? timeLimitMs}) => PackQuestion(
    id: id,
    type: type,
    prompt: prompt,
    acceptedAnswers: acceptedAnswers,
    timeLimitMs: timeLimitMs ?? this.timeLimitMs,
    imageUrl: imageUrl,
    difficulty: difficulty,
  );
}

class Pack {
  const Pack({
    required this.id,
    required this.title,
    required this.questions,
    this.defaultTimeLimitMs,
    this.defaultDifficultyMultiplier = false,
  });

  const Pack.empty()
    : id = 'unselected',
      title = '',
      questions = const [],
      defaultTimeLimitMs = null,
      defaultDifficultyMultiplier = false;

  /// Builds a pack from a quiz document held on the device.
  ///
  /// Questions without an explicit id get a positional one, matching what the
  /// server does when it stores a quiz: ids only have to be stable within the
  /// room, and clients must not parse them (PROTOCOL.md §1).
  ///
  /// [imageUrl] turns a stored photo key into the URL clients fetch it from,
  /// the same seam `Fazoura.Quizzes.to_pack/2` has. Without it a photo
  /// question keeps its prompt and scores normally but carries no image —
  /// which is all a pack built outside a running host can honestly say.
  factory Pack.fromQuiz(
    QuizDocument quiz, {
    String Function(String key)? imageUrl,
  }) {
    final questions = quiz.questions ?? const <QuizQuestion>[];
    return Pack(
      id: quiz.id ?? quiz.slug ?? 'local',
      title: quiz.title,
      defaultTimeLimitMs: quiz.defaultSettings.timeLimitMs,
      defaultDifficultyMultiplier: quiz.defaultSettings.difficultyMultiplier,
      questions: [
        for (final (index, question) in questions.indexed)
          PackQuestion(
            id: question.id ?? 'q${index + 1}',
            type: question.type,
            prompt: question.prompt,
            acceptedAnswers: question.acceptedAnswers,
            timeLimitMs: question.timeLimitMs ?? _defaultTimeLimitMs,
            imageUrl: _imageUrl(question, imageUrl),
            difficulty: _difficulty(question.difficulty),
          ),
      ],
    );
  }

  /// Builds a pack straight from the JSON shape the shared contract fixtures
  /// use, the counterpart of `Fazoura.Game.Pack.from_map/1`. Only the fixture
  /// runner needs it: a real pack comes from a quiz document.
  factory Pack.fromMap(Map<String, dynamic> map) => Pack(
    id: map['id'] as String? ?? 'inline',
    title: map['title'] as String,
    questions: [
      for (final question in map['questions'] as List)
        _questionFromMap(question as Map<String, dynamic>),
    ],
  );

  static PackQuestion _questionFromMap(Map<String, dynamic> map) {
    final difficulty = map['difficulty'] as String? ?? 'easy';
    if (!_difficulties.contains(difficulty)) {
      throw ArgumentError.value(
        difficulty,
        'difficulty',
        'unknown difficulty; use easy, medium or hard',
      );
    }
    return PackQuestion(
      id: map['id'] as String,
      type: map['type'] as String? ?? 'text',
      prompt: map['prompt'] as String,
      acceptedAnswers: [
        for (final answer in map['accepted_answers'] as List) answer as String,
      ],
      timeLimitMs: map['time_limit_ms'] as int? ?? _defaultTimeLimitMs,
      imageUrl: map['image_url'] as String?,
      difficulty: difficulty,
    );
  }

  final String id;
  final String title;
  final List<PackQuestion> questions;
  final int? defaultTimeLimitMs;
  final bool defaultDifficultyMultiplier;

  static String _difficulty(String value) =>
      _difficulties.contains(value) ? value : 'easy';

  /// Non-null only for a `text_photo` question whose photo was actually
  /// stored: `image_url` is what tells a client there is an image to show
  /// (PROTOCOL.md §5.1).
  static String? _imageUrl(
    QuizQuestion question,
    String Function(String key)? imageUrl,
  ) {
    final key = question.image?.key;
    if (!question.hasPhoto || key == null || imageUrl == null) return null;
    return imageUrl(key);
  }
}
