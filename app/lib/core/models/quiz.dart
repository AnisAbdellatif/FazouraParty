import 'package:freezed_annotation/freezed_annotation.dart';

part 'quiz.freezed.dart';
part 'quiz.g.dart';

/// Quiz JSON document (protocol/QUIZ_FORMAT.md §2). Listing endpoints omit
/// [questions]; they are only present for the quiz's owner.
@freezed
abstract class QuizDocument with _$QuizDocument {
  const QuizDocument._();

  const factory QuizDocument({
    @Default(1) int formatVersion,
    String? id,
    String? slug,
    required String title,
    String? description,
    @Default('en') String language,
    @Default('general') String category,
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

  /// Body for publishing (§5.3): photos by uploaded key only.
  QuizDocument forPublishing() =>
      _mapImages((image) => QuizImage(key: image.key, alt: image.alt));

  /// Body for hosting a private quiz inline (§5.7): photos as base64 data.
  QuizDocument forInlineRoom() =>
      _mapImages((image) => QuizImage(data: image.data, alt: image.alt));

  QuizDocument _mapImages(QuizImage Function(QuizImage image) convert) =>
      copyWith(
        questions: [
          for (final question in questions ?? const <QuizQuestion>[])
            question.copyWith(
              image: question.hasPhoto && question.image != null
                  ? convert(question.image!)
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

/// Categories from QUIZ_FORMAT.md §2.3 with display labels.
const quizCategories = <String, String>{
  'general': 'General',
  'science': 'Science',
  'history': 'History',
  'geography': 'Geography',
  'movies': 'Movies',
  'music': 'Music',
  'sports': 'Sports',
  'food': 'Food',
  'language': 'Language',
  'pop_culture': 'Pop culture',
  'other': 'Other',
};

String categoryLabel(String category) => quizCategories[category] ?? 'Other';
