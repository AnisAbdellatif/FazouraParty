import 'package:freezed_annotation/freezed_annotation.dart';

part 'quiz.freezed.dart';
part 'quiz.g.dart';

String quizVersionFromJson(Object? value) {
  if (value is num) return '${value.toInt()}.0';
  if (value is String && value.isNotEmpty) return value;
  return '1.0';
}

/// Quiz JSON document (protocol/QUIZ_FORMAT.md §2). Listing endpoints omit
/// [questions]; they are only present for the quiz's owner.
@freezed
abstract class QuizDocument with _$QuizDocument {
  const QuizDocument._();

  const factory QuizDocument({
    @Default(1) int formatVersion,
    @JsonKey(fromJson: quizVersionFromJson) @Default('1.0') String version,
    String? id,
    String? slug,
    required String title,
    String? description,
    @Default('en') String language,
    @Default(<String>[]) List<String> tags,
    @Default('custom') String source,
    @Default('private') String visibility,
    @Default(false) bool isOwner,
    @Default(QuizDefaultSettings()) QuizDefaultSettings defaultSettings,
    @Default(0) int questionCount,
    @Default(false) bool hasPhotos,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<QuizQuestion>? questions,
  }) = _QuizDocument;

  factory QuizDocument.fromJson(Map<String, dynamic> json) =>
      _$QuizDocumentFromJson(json);

  bool get isBuiltin => source == 'builtin';
  bool get isPublic => visibility == 'public';

  /// Id to send when hosting: the uuid, or the slug for built-ins.
  String get hostId => id ?? slug ?? '';

  /// Numeric ordering for the `<major>.<minor>` content revision.
  int get versionRank {
    final parts = version.split('.');
    final major = int.tryParse(parts.first) ?? 0;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return major * 1000000 + minor;
  }

  /// Body for hosting a private quiz inline (§5.7): photos as base64 data.
  ///
  /// Publishing has no counterpart here any more — it sends a `.fazoura`
  /// package rather than a JSON document (§5.4), so
  /// `QuizArchive.encode` is what shapes the photos for the server now.
  QuizDocument forInlineRoom() => copyWith(
    questions: [
      for (final question in questions ?? const <QuizQuestion>[])
        question.copyWith(
          image: question.hasPhoto && question.image != null
              ? QuizImage(data: question.image!.data, alt: question.image!.alt)
              : null,
        ),
    ],
  );
}

@freezed
abstract class QuizDefaultSettings with _$QuizDefaultSettings {
  const factory QuizDefaultSettings({
    @Default(30000) int timeLimitMs,
    @Default(false) bool difficultyMultiplier,
  }) = _QuizDefaultSettings;

  factory QuizDefaultSettings.fromJson(Map<String, dynamic> json) =>
      _$QuizDefaultSettingsFromJson(json);
}

/// One question (QUIZ_FORMAT.md §2.2).
@freezed
abstract class QuizQuestion with _$QuizQuestion {
  const QuizQuestion._();

  const factory QuizQuestion({
    String? id,
    @Default(QuizQuestion.typeText) String type,
    required String prompt,
    @Default(<String>[]) List<String> acceptedAnswers,
    @Default('easy') String difficulty,
    int? timeLimitMs,
    QuizImage? image,
    String? explanation,
  }) = _QuizQuestion;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) =>
      _$QuizQuestionFromJson(json);

  static const typeText = 'text';
  static const typePhoto = 'text_photo';

  bool get hasPhoto => type == typePhoto;
}

/// A question photo. [key] and [url] refer to an uploaded copy (published
/// quizzes); [data] is the base64 photo itself, kept on the device and sent
/// inline when hosting a private quiz (QUIZ_FORMAT.md §2.2, §5.7).
@freezed
abstract class QuizImage with _$QuizImage {
  const factory QuizImage({
    String? key,
    String? url,
    String? alt,
    String? data,
  }) = _QuizImage;

  factory QuizImage.fromJson(Map<String, dynamic> json) =>
      _$QuizImageFromJson(json);
}

/// A page of `GET /api/quizzes`.
class QuizPage {
  const QuizPage({required this.quizzes, this.nextOffset});

  final List<QuizDocument> quizzes;
  final int? nextOffset;
}

/// Tags offered as quick picks in the editor and the browser
/// (QUIZ_FORMAT.md §2.3). Any other tag can be typed in.
const defaultQuizTags = <String>[
  'general',
  'science',
  'history',
  'geography',
  'movies',
  'tv',
  'music',
  'sports',
  'food',
  'nature',
  'technology',
  'art',
  'books',
  'gaming',
  'pop culture',
  'language',
];

/// Maximum tags per quiz, and the longest a tag may be (QUIZ_FORMAT.md §2.3).
const maxQuizTags = 10;
const maxTagLength = 24;

/// Lower case, trimmed, inner whitespace collapsed — the server does the same,
/// so "Pop  Culture" and "pop culture" are one tag.
String normalizeTag(String tag) =>
    tag.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// A tag and how many public quizzes use it (`GET /api/tags`).
typedef TagCount = ({String tag, int count});

/// What `GET /api/tags` answers: tags in use, and the server's quick picks.
typedef QuizTags = ({List<TagCount> popular, List<String> suggested});

/// What became of a quiz this device sent for review (QUIZ_FORMAT.md §5.4).
///
/// A submission is the `.fazoura` package and nothing else: until somebody
/// approves it there is no quiz on the server, no photo in its uploads volume
/// and nothing for anyone else to find. Waiting costs its author nothing — they
/// still hold the quiz on their own device and host it inline as before.
@freezed
abstract class QuizSubmission with _$QuizSubmission {
  const QuizSubmission._();

  const factory QuizSubmission({
    required String id,
    @Default('') String title,
    @Default(QuizSubmission.pending) String status,
    @Default(0) int questionCount,
    @Default(false) bool hasPhotos,

    /// Why it was turned down. Only ever sent to the device that submitted it.
    String? reviewNote,

    /// The published quiz, once there is one.
    String? quizId,
    String? replacesQuizId,
    DateTime? submittedAt,
    DateTime? reviewedAt,
  }) = _QuizSubmission;

  factory QuizSubmission.fromJson(Map<String, dynamic> json) =>
      _$QuizSubmissionFromJson(json);

  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';

  bool get isPending => status == pending;
  bool get isApproved => status == approved;
  bool get isRejected => status == rejected;
}
