// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'local_quiz.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LocalQuiz {

 String get localId;/// The full document, questions and photo data included. Its
/// `visibility` is what the creator chose.
 QuizDocument get quiz;/// Server id of the published copy, if any.
 String? get publishedId; DateTime? get updatedAt;/// Base64-encoded `.fazoura` archive for downloaded community quizzes.
 String? get archiveData;/// The last time this quiz was sent for review, and what became of it
/// (QUIZ_FORMAT.md §4). Kept on the device so a rejection has somewhere to
/// be read; cleared once the quiz is published.
 QuizSubmission? get submission;
/// Create a copy of LocalQuiz
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalQuizCopyWith<LocalQuiz> get copyWith => _$LocalQuizCopyWithImpl<LocalQuiz>(this as LocalQuiz, _$identity);

  /// Serializes this LocalQuiz to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as LocalQuiz;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalQuiz&&(identical(other.localId, _this.localId) || other.localId == _this.localId)&&(identical(other.quiz, _this.quiz) || other.quiz == _this.quiz)&&(identical(other.publishedId, _this.publishedId) || other.publishedId == _this.publishedId)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.archiveData, _this.archiveData) || other.archiveData == _this.archiveData)&&(identical(other.submission, _this.submission) || other.submission == _this.submission));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as LocalQuiz;
  return Object.hash(runtimeType,_this.localId,_this.quiz,_this.publishedId,_this.updatedAt,_this.archiveData,_this.submission);
}

@override
String toString() {
  final _this = this as LocalQuiz;
  return 'LocalQuiz(localId: ${_this.localId}, quiz: ${_this.quiz}, publishedId: ${_this.publishedId}, updatedAt: ${_this.updatedAt}, archiveData: ${_this.archiveData}, submission: ${_this.submission})';
}


}

/// @nodoc
abstract mixin class $LocalQuizCopyWith<$Res>  {
  factory $LocalQuizCopyWith(LocalQuiz value, $Res Function(LocalQuiz) _then) = _$LocalQuizCopyWithImpl;
@useResult
$Res call({
 String localId, QuizDocument quiz, String? publishedId, DateTime? updatedAt, String? archiveData, QuizSubmission? submission
});


$QuizDocumentCopyWith<$Res> get quiz;$QuizSubmissionCopyWith<$Res>? get submission;

}
/// @nodoc
class _$LocalQuizCopyWithImpl<$Res>
    implements $LocalQuizCopyWith<$Res> {
  _$LocalQuizCopyWithImpl(this._self, this._then);

  final LocalQuiz _self;
  final $Res Function(LocalQuiz) _then;

/// Create a copy of LocalQuiz
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? localId = null,Object? quiz = null,Object? publishedId = freezed,Object? updatedAt = freezed,Object? archiveData = freezed,Object? submission = freezed,}) {
  return _then(LocalQuiz(
localId: null == localId ? _self.localId : localId // ignore: cast_nullable_to_non_nullable
as String,quiz: null == quiz ? _self.quiz : quiz // ignore: cast_nullable_to_non_nullable
as QuizDocument,publishedId: freezed == publishedId ? _self.publishedId : publishedId // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,archiveData: freezed == archiveData ? _self.archiveData : archiveData // ignore: cast_nullable_to_non_nullable
as String?,submission: freezed == submission ? _self.submission : submission // ignore: cast_nullable_to_non_nullable
as QuizSubmission?,
  ));
}
/// Create a copy of LocalQuiz
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizDocumentCopyWith<$Res> get quiz {
  
  return $QuizDocumentCopyWith<$Res>(_self.quiz, (value) {
    return _then(_self.copyWith(quiz: value));
  });
}/// Create a copy of LocalQuiz
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizSubmissionCopyWith<$Res>? get submission {
    if (_self.submission == null) {
    return null;
  }

  return $QuizSubmissionCopyWith<$Res>(_self.submission!, (value) {
    return _then(_self.copyWith(submission: value));
  });
}
}


/// Adds pattern-matching-related methods to [LocalQuiz].
extension LocalQuizPatterns on LocalQuiz {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LocalQuiz value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LocalQuiz() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LocalQuiz value)  $default,){
final _that = this;
switch (_that) {
case _LocalQuiz():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LocalQuiz value)?  $default,){
final _that = this;
switch (_that) {
case _LocalQuiz() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String localId,  QuizDocument quiz,  String? publishedId,  DateTime? updatedAt,  String? archiveData,  QuizSubmission? submission)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LocalQuiz() when $default != null:
return $default(_that.localId,_that.quiz,_that.publishedId,_that.updatedAt,_that.archiveData,_that.submission);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String localId,  QuizDocument quiz,  String? publishedId,  DateTime? updatedAt,  String? archiveData,  QuizSubmission? submission)  $default,) {final _that = this;
switch (_that) {
case _LocalQuiz():
return $default(_that.localId,_that.quiz,_that.publishedId,_that.updatedAt,_that.archiveData,_that.submission);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String localId,  QuizDocument quiz,  String? publishedId,  DateTime? updatedAt,  String? archiveData,  QuizSubmission? submission)?  $default,) {final _that = this;
switch (_that) {
case _LocalQuiz() when $default != null:
return $default(_that.localId,_that.quiz,_that.publishedId,_that.updatedAt,_that.archiveData,_that.submission);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LocalQuiz extends LocalQuiz {
  const _LocalQuiz({required this.localId, required this.quiz, this.publishedId, this.updatedAt, this.archiveData, this.submission}): super._();
  factory _LocalQuiz.fromJson(Map<String, dynamic> json) => _$LocalQuizFromJson(json);

@override final  String localId;
/// The full document, questions and photo data included. Its
/// `visibility` is what the creator chose.
@override final  QuizDocument quiz;
/// Server id of the published copy, if any.
@override final  String? publishedId;
@override final  DateTime? updatedAt;
/// Base64-encoded `.fazoura` archive for downloaded community quizzes.
@override final  String? archiveData;
/// The last time this quiz was sent for review, and what became of it
/// (QUIZ_FORMAT.md §4). Kept on the device so a rejection has somewhere to
/// be read; cleared once the quiz is published.
@override final  QuizSubmission? submission;

/// Create a copy of LocalQuiz
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LocalQuizCopyWith<_LocalQuiz> get copyWith => __$LocalQuizCopyWithImpl<_LocalQuiz>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LocalQuizToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LocalQuiz&&(identical(other.localId, localId) || other.localId == localId)&&(identical(other.quiz, quiz) || other.quiz == quiz)&&(identical(other.publishedId, publishedId) || other.publishedId == publishedId)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.archiveData, archiveData) || other.archiveData == archiveData)&&(identical(other.submission, submission) || other.submission == submission));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,localId,quiz,publishedId,updatedAt,archiveData,submission);
}

@override
String toString() {
    return 'LocalQuiz(localId: $localId, quiz: $quiz, publishedId: $publishedId, updatedAt: $updatedAt, archiveData: $archiveData, submission: $submission)';
}


}

/// @nodoc
abstract mixin class _$LocalQuizCopyWith<$Res> implements $LocalQuizCopyWith<$Res> {
  factory _$LocalQuizCopyWith(_LocalQuiz value, $Res Function(_LocalQuiz) _then) = __$LocalQuizCopyWithImpl;
@override @useResult
$Res call({
 String localId, QuizDocument quiz, String? publishedId, DateTime? updatedAt, String? archiveData, QuizSubmission? submission
});


@override $QuizDocumentCopyWith<$Res> get quiz;@override $QuizSubmissionCopyWith<$Res>? get submission;

}
/// @nodoc
class __$LocalQuizCopyWithImpl<$Res>
    implements _$LocalQuizCopyWith<$Res> {
  __$LocalQuizCopyWithImpl(this._self, this._then);

  final _LocalQuiz _self;
  final $Res Function(_LocalQuiz) _then;

/// Create a copy of LocalQuiz
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? localId = null,Object? quiz = null,Object? publishedId = freezed,Object? updatedAt = freezed,Object? archiveData = freezed,Object? submission = freezed,}) {
  return _then(_LocalQuiz(
localId: null == localId ? _self.localId : localId // ignore: cast_nullable_to_non_nullable
as String,quiz: null == quiz ? _self.quiz : quiz // ignore: cast_nullable_to_non_nullable
as QuizDocument,publishedId: freezed == publishedId ? _self.publishedId : publishedId // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,archiveData: freezed == archiveData ? _self.archiveData : archiveData // ignore: cast_nullable_to_non_nullable
as String?,submission: freezed == submission ? _self.submission : submission // ignore: cast_nullable_to_non_nullable
as QuizSubmission?,
  ));
}

/// Create a copy of LocalQuiz
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizDocumentCopyWith<$Res> get quiz {
  
  return $QuizDocumentCopyWith<$Res>(_self.quiz, (value) {
    return _then(_self.copyWith(quiz: value));
  });
}/// Create a copy of LocalQuiz
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizSubmissionCopyWith<$Res>? get submission {
    if (_self.submission == null) {
    return null;
  }

  return $QuizSubmissionCopyWith<$Res>(_self.submission!, (value) {
    return _then(_self.copyWith(submission: value));
  });
}
}

// dart format on
