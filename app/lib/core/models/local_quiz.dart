import 'package:freezed_annotation/freezed_annotation.dart';

import 'quiz.dart';

part 'local_quiz.freezed.dart';
part 'local_quiz.g.dart';

/// A quiz made on this device, kept in the app's local database
/// (QUIZ_FORMAT.md §4). Private quizzes only exist here; public ones are also
/// published to the server as [publishedId].
@freezed
abstract class LocalQuiz with _$LocalQuiz {
  const LocalQuiz._();

  const factory LocalQuiz({
    required String localId,

    /// The full document, questions and photo data included. Its
    /// `visibility` is what the creator chose.
    required QuizDocument quiz,

    /// Server id of the published copy, if any.
    String? publishedId,
    DateTime? updatedAt,

    /// Base64-encoded `.fazoura` archive for downloaded community quizzes.
    String? archiveData,
  }) = _LocalQuiz;

  factory LocalQuiz.fromJson(Map<String, dynamic> json) =>
      _$LocalQuizFromJson(json);

  bool get isPublished => publishedId != null;
  bool get wantsPublic => quiz.isPublic;

  /// False when the last publish or unpublish didn't reach the server.
  bool get inSync => isPublished == wantsPublic;

  /// Card summary, with the counts a listing would carry.
  QuizDocument get summary {
    final questions = quiz.questions ?? const <QuizQuestion>[];
    return quiz.copyWith(
      id: publishedId,
      isOwner: true,
      questionCount: questions.length,
      hasPhotos: questions.any((question) => question.hasPhoto),
    );
  }
}
