/// Immutable snapshot of the questions a LAN-hosted room plays.
///
/// Dart port of `server/lib/fazoura/game/pack.ex`. A round is played from one
/// pool drawn from every quiz the host selected ([Pack.merge], PROTOCOL.md
/// §6.4). The room copies it when it is created, so editing a quiz mid-game
/// can never affect a running room (AGENTS.md §4).
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

  PackQuestion copyWith({int? timeLimitMs, String? id}) => PackQuestion(
    id: id ?? this.id,
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
    required this.titles,
    required this.questions,
    this.defaultTimeLimitMs,
    this.defaultDifficultyMultiplier = false,
  });

  const Pack.empty()
    : titles = const [],
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
      titles: [quiz.title],
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

  /// One pool from the quizzes the host selected, in the order they selected
  /// them — the counterpart of `Fazoura.Game.Pack.merge/1` (PROTOCOL.md §6.4).
  ///
  /// Question ids are rewritten to stay unique across the pool: two quizzes
  /// may each call a question `q1`, and clients use the id to tell one
  /// question from the next. Ids are opaque (§1), so rewriting them is ours to
  /// do. Lobby defaults come from the first quiz, because a pool has none.
  factory Pack.merge(List<Pack> packs) {
    if (packs.length == 1) return packs.single;
    return Pack(
      titles: [for (final pack in packs) ...pack.titles],
      defaultTimeLimitMs: packs.first.defaultTimeLimitMs,
      defaultDifficultyMultiplier: packs.first.defaultDifficultyMultiplier,
      questions: [
        for (final (index, pack) in packs.indexed)
          for (final question in pack.questions)
            question.copyWith(id: '$index-${question.id}'),
      ],
    );
  }

  /// Builds a pack straight from the JSON shape the shared contract fixtures
  /// use, the counterpart of `Fazoura.Game.Pack.from_map/1`. Only the fixture
  /// runner needs it: a real pack comes from a quiz document.
  factory Pack.fromMap(Map<String, dynamic> map) => Pack(
    titles: [map['title'] as String],
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

  /// Titles of the selected quizzes, in the order the host chose them. Empty
  /// means nothing is selected yet (PROTOCOL.md §5.1, §6.4).
  final List<String> titles;
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
