// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quiz.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_QuizDocument _$QuizDocumentFromJson(Map<String, dynamic> json) =>
    _QuizDocument(
      formatVersion: (json['format_version'] as num?)?.toInt() ?? 1,
      id: json['id'] as String?,
      slug: json['slug'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      language: json['language'] as String? ?? 'en',
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const <String>[],
      source: json['source'] as String? ?? 'custom',
      visibility: json['visibility'] as String? ?? 'private',
      isOwner: json['is_owner'] as bool? ?? false,
      defaultSettings: json['default_settings'] == null
          ? const QuizDefaultSettings()
          : QuizDefaultSettings.fromJson(
              json['default_settings'] as Map<String, dynamic>,
            ),
      questionCount: (json['question_count'] as num?)?.toInt() ?? 0,
      hasPhotos: json['has_photos'] as bool? ?? false,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      questions: (json['questions'] as List<dynamic>?)
          ?.map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$QuizDocumentToJson(_QuizDocument instance) =>
    <String, dynamic>{
      'format_version': instance.formatVersion,
      'id': instance.id,
      'slug': instance.slug,
      'title': instance.title,
      'description': instance.description,
      'language': instance.language,
      'tags': instance.tags,
      'source': instance.source,
      'visibility': instance.visibility,
      'is_owner': instance.isOwner,
      'default_settings': instance.defaultSettings.toJson(),
      'question_count': instance.questionCount,
      'has_photos': instance.hasPhotos,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
      'questions': instance.questions?.map((e) => e.toJson()).toList(),
    };

_QuizDefaultSettings _$QuizDefaultSettingsFromJson(Map<String, dynamic> json) =>
    _QuizDefaultSettings(
      timeLimitMs: (json['time_limit_ms'] as num?)?.toInt() ?? 30000,
      difficultyMultiplier: json['difficulty_multiplier'] as bool? ?? false,
    );

Map<String, dynamic> _$QuizDefaultSettingsToJson(
  _QuizDefaultSettings instance,
) => <String, dynamic>{
  'time_limit_ms': instance.timeLimitMs,
  'difficulty_multiplier': instance.difficultyMultiplier,
};

_QuizQuestion _$QuizQuestionFromJson(Map<String, dynamic> json) =>
    _QuizQuestion(
      id: json['id'] as String?,
      type: json['type'] as String? ?? QuizQuestion.typeText,
      prompt: json['prompt'] as String,
      acceptedAnswers:
          (json['accepted_answers'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      difficulty: json['difficulty'] as String? ?? 'easy',
      timeLimitMs: (json['time_limit_ms'] as num?)?.toInt(),
      image: json['image'] == null
          ? null
          : QuizImage.fromJson(json['image'] as Map<String, dynamic>),
      explanation: json['explanation'] as String?,
    );

Map<String, dynamic> _$QuizQuestionToJson(_QuizQuestion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'prompt': instance.prompt,
      'accepted_answers': instance.acceptedAnswers,
      'difficulty': instance.difficulty,
      'time_limit_ms': instance.timeLimitMs,
      'image': instance.image?.toJson(),
      'explanation': instance.explanation,
    };

_QuizImage _$QuizImageFromJson(Map<String, dynamic> json) => _QuizImage(
  key: json['key'] as String?,
  url: json['url'] as String?,
  alt: json['alt'] as String?,
  data: json['data'] as String?,
);

Map<String, dynamic> _$QuizImageToJson(_QuizImage instance) =>
    <String, dynamic>{
      'key': instance.key,
      'url': instance.url,
      'alt': instance.alt,
      'data': instance.data,
    };
