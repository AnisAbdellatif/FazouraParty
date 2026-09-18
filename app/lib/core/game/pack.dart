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

  /// On LAN this is a `lan://photo/<question id>` URL served by the host's own
  /// HTTP server, not a public URL.
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
  factory Pack.fromQuiz(QuizDocument quiz) {
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
            imageUrl: question.hasPhoto ? 'lan://photo/${index + 1}' : null,
            difficulty: _difficulty(question.difficulty),
          ),
      ],
    );
  }

  final String id;
  final String title;
  final List<PackQuestion> questions;
  final int? defaultTimeLimitMs;
  final bool defaultDifficultyMultiplier;

  static String _difficulty(String value) =>
      _difficulties.contains(value) ? value : 'easy';
}
