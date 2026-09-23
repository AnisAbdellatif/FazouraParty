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

    /// The last time this quiz was sent for review, and what became of it
    /// (QUIZ_FORMAT.md §4). Kept on the device so a rejection has somewhere to
    /// be read; cleared once the quiz is published.
    QuizSubmission? submission,
  }) = _LocalQuiz;

  factory LocalQuiz.fromJson(Map<String, dynamic> json) =>
      _$LocalQuizFromJson(json);

  bool get isPublished => publishedId != null;
  bool get wantsPublic => quiz.isPublic;

  /// Sent for review and not yet read. There is nothing to retry and nothing
  /// to see on the server: the queue is simply not empty yet.
  bool get inReview => submission?.isPending ?? false;

  /// Turned down, with a note its author has not acted on yet.
  bool get wasRejected => submission?.isRejected ?? false;

  /// False when the last submit or unpublish didn't reach the server. Waiting
  /// in the review queue is not out of sync — it is the normal way to publish.
  bool get inSync => wantsPublic ? isPublished || inReview : !isPublished;

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
