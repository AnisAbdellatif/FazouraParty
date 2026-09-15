// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_quiz.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LocalQuiz _$LocalQuizFromJson(Map<String, dynamic> json) => _LocalQuiz(
  localId: json['local_id'] as String,
  quiz: QuizDocument.fromJson(json['quiz'] as Map<String, dynamic>),
  publishedId: json['published_id'] as String?,
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$LocalQuizToJson(_LocalQuiz instance) =>
    <String, dynamic>{
      'local_id': instance.localId,
      'quiz': instance.quiz.toJson(),
      'published_id': instance.publishedId,
      'updated_at': instance.updatedAt?.toIso8601String(),
    };
