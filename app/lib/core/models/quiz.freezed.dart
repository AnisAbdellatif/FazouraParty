// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'quiz.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$QuizDocument {

 int get formatVersion;@JsonKey(fromJson: quizVersionFromJson) String get version; String? get id; String? get slug; String get title; String? get description; String get language; List<String> get tags; String get source; String get visibility; bool get isOwner; QuizDefaultSettings get defaultSettings; int get questionCount; bool get hasPhotos; DateTime? get createdAt; DateTime? get updatedAt; List<QuizQuestion>? get questions;
/// Create a copy of QuizDocument
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizDocumentCopyWith<QuizDocument> get copyWith => _$QuizDocumentCopyWithImpl<QuizDocument>(this as QuizDocument, _$identity);

  /// Serializes this QuizDocument to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuizDocument;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizDocument&&(identical(other.formatVersion, _this.formatVersion) || other.formatVersion == _this.formatVersion)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.slug, _this.slug) || other.slug == _this.slug)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.language, _this.language) || other.language == _this.language)&&const DeepCollectionEquality().equals(other.tags, _this.tags)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.visibility, _this.visibility) || other.visibility == _this.visibility)&&(identical(other.isOwner, _this.isOwner) || other.isOwner == _this.isOwner)&&(identical(other.defaultSettings, _this.defaultSettings) || other.defaultSettings == _this.defaultSettings)&&(identical(other.questionCount, _this.questionCount) || other.questionCount == _this.questionCount)&&(identical(other.hasPhotos, _this.hasPhotos) || other.hasPhotos == _this.hasPhotos)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&const DeepCollectionEquality().equals(other.questions, _this.questions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizDocument;
  return Object.hash(runtimeType,_this.formatVersion,_this.version,_this.id,_this.slug,_this.title,_this.description,_this.language,const DeepCollectionEquality().hash(_this.tags),_this.source,_this.visibility,_this.isOwner,_this.defaultSettings,_this.questionCount,_this.hasPhotos,_this.createdAt,_this.updatedAt,const DeepCollectionEquality().hash(_this.questions));
}

@override
String toString() {
  final _this = this as QuizDocument;
  return 'QuizDocument(formatVersion: ${_this.formatVersion}, version: ${_this.version}, id: ${_this.id}, slug: ${_this.slug}, title: ${_this.title}, description: ${_this.description}, language: ${_this.language}, tags: ${_this.tags}, source: ${_this.source}, visibility: ${_this.visibility}, isOwner: ${_this.isOwner}, defaultSettings: ${_this.defaultSettings}, questionCount: ${_this.questionCount}, hasPhotos: ${_this.hasPhotos}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, questions: ${_this.questions})';
}


}

/// @nodoc
abstract mixin class $QuizDocumentCopyWith<$Res>  {
  factory $QuizDocumentCopyWith(QuizDocument value, $Res Function(QuizDocument) _then) = _$QuizDocumentCopyWithImpl;
@useResult
$Res call({
 int formatVersion,@JsonKey(fromJson: quizVersionFromJson) String version, String? id, String? slug, String title, String? description, String language, List<String> tags, String source, String visibility, bool isOwner, QuizDefaultSettings defaultSettings, int questionCount, bool hasPhotos, DateTime? createdAt, DateTime? updatedAt, List<QuizQuestion>? questions
});


$QuizDefaultSettingsCopyWith<$Res> get defaultSettings;

}
/// @nodoc
class _$QuizDocumentCopyWithImpl<$Res>
    implements $QuizDocumentCopyWith<$Res> {
  _$QuizDocumentCopyWithImpl(this._self, this._then);

  final QuizDocument _self;
  final $Res Function(QuizDocument) _then;

/// Create a copy of QuizDocument
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? formatVersion = null,Object? version = null,Object? id = freezed,Object? slug = freezed,Object? title = null,Object? description = freezed,Object? language = null,Object? tags = null,Object? source = null,Object? visibility = null,Object? isOwner = null,Object? defaultSettings = null,Object? questionCount = null,Object? hasPhotos = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? questions = freezed,}) {
  return _then(QuizDocument(
formatVersion: null == formatVersion ? _self.formatVersion : formatVersion // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,slug: freezed == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,visibility: null == visibility ? _self.visibility : visibility // ignore: cast_nullable_to_non_nullable
as String,isOwner: null == isOwner ? _self.isOwner : isOwner // ignore: cast_nullable_to_non_nullable
as bool,defaultSettings: null == defaultSettings ? _self.defaultSettings : defaultSettings // ignore: cast_nullable_to_non_nullable
as QuizDefaultSettings,questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,hasPhotos: null == hasPhotos ? _self.hasPhotos : hasPhotos // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,questions: freezed == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<QuizQuestion>?,
  ));
}
/// Create a copy of QuizDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizDefaultSettingsCopyWith<$Res> get defaultSettings {
  
  return $QuizDefaultSettingsCopyWith<$Res>(_self.defaultSettings, (value) {
    return _then(_self.copyWith(defaultSettings: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuizDocument].
extension QuizDocumentPatterns on QuizDocument {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizDocument value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizDocument() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizDocument value)  $default,){
final _that = this;
switch (_that) {
case _QuizDocument():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizDocument value)?  $default,){
final _that = this;
switch (_that) {
case _QuizDocument() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int formatVersion, @JsonKey(fromJson: quizVersionFromJson)  String version,  String? id,  String? slug,  String title,  String? description,  String language,  List<String> tags,  String source,  String visibility,  bool isOwner,  QuizDefaultSettings defaultSettings,  int questionCount,  bool hasPhotos,  DateTime? createdAt,  DateTime? updatedAt,  List<QuizQuestion>? questions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizDocument() when $default != null:
return $default(_that.formatVersion,_that.version,_that.id,_that.slug,_that.title,_that.description,_that.language,_that.tags,_that.source,_that.visibility,_that.isOwner,_that.defaultSettings,_that.questionCount,_that.hasPhotos,_that.createdAt,_that.updatedAt,_that.questions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int formatVersion, @JsonKey(fromJson: quizVersionFromJson)  String version,  String? id,  String? slug,  String title,  String? description,  String language,  List<String> tags,  String source,  String visibility,  bool isOwner,  QuizDefaultSettings defaultSettings,  int questionCount,  bool hasPhotos,  DateTime? createdAt,  DateTime? updatedAt,  List<QuizQuestion>? questions)  $default,) {final _that = this;
switch (_that) {
case _QuizDocument():
return $default(_that.formatVersion,_that.version,_that.id,_that.slug,_that.title,_that.description,_that.language,_that.tags,_that.source,_that.visibility,_that.isOwner,_that.defaultSettings,_that.questionCount,_that.hasPhotos,_that.createdAt,_that.updatedAt,_that.questions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int formatVersion, @JsonKey(fromJson: quizVersionFromJson)  String version,  String? id,  String? slug,  String title,  String? description,  String language,  List<String> tags,  String source,  String visibility,  bool isOwner,  QuizDefaultSettings defaultSettings,  int questionCount,  bool hasPhotos,  DateTime? createdAt,  DateTime? updatedAt,  List<QuizQuestion>? questions)?  $default,) {final _that = this;
switch (_that) {
case _QuizDocument() when $default != null:
return $default(_that.formatVersion,_that.version,_that.id,_that.slug,_that.title,_that.description,_that.language,_that.tags,_that.source,_that.visibility,_that.isOwner,_that.defaultSettings,_that.questionCount,_that.hasPhotos,_that.createdAt,_that.updatedAt,_that.questions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizDocument extends QuizDocument {
  const _QuizDocument({this.formatVersion = 1, @JsonKey(fromJson: quizVersionFromJson) this.version = '1.0', this.id, this.slug, required this.title, this.description, this.language = 'en',  List<String> tags = const <String>[], this.source = 'custom', this.visibility = 'private', this.isOwner = false, this.defaultSettings = const QuizDefaultSettings(), this.questionCount = 0, this.hasPhotos = false, this.createdAt, this.updatedAt,  List<QuizQuestion>? questions}): _tags = tags,_questions = questions,super._();
  factory _QuizDocument.fromJson(Map<String, dynamic> json) => _$QuizDocumentFromJson(json);

@override@JsonKey() final  int formatVersion;
@override@JsonKey(fromJson: quizVersionFromJson) final  String version;
@override final  String? id;
@override final  String? slug;
@override final  String title;
@override final  String? description;
@override@JsonKey() final  String language;
 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override@JsonKey() final  String source;
@override@JsonKey() final  String visibility;
@override@JsonKey() final  bool isOwner;
@override@JsonKey() final  QuizDefaultSettings defaultSettings;
@override@JsonKey() final  int questionCount;
@override@JsonKey() final  bool hasPhotos;
@override final  DateTime? createdAt;
@override final  DateTime? updatedAt;
 final  List<QuizQuestion>? _questions;
@override List<QuizQuestion>? get questions {
  final value = _questions;
  if (value == null) return null;
  if (_questions is EqualUnmodifiableListView) return _questions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of QuizDocument
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizDocumentCopyWith<_QuizDocument> get copyWith => __$QuizDocumentCopyWithImpl<_QuizDocument>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizDocumentToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizDocument&&(identical(other.formatVersion, formatVersion) || other.formatVersion == formatVersion)&&(identical(other.version, version) || other.version == version)&&(identical(other.id, id) || other.id == id)&&(identical(other.slug, slug) || other.slug == slug)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.language, language) || other.language == language)&&const DeepCollectionEquality().equals(other.tags, _tags)&&(identical(other.source, source) || other.source == source)&&(identical(other.visibility, visibility) || other.visibility == visibility)&&(identical(other.isOwner, isOwner) || other.isOwner == isOwner)&&(identical(other.defaultSettings, defaultSettings) || other.defaultSettings == defaultSettings)&&(identical(other.questionCount, questionCount) || other.questionCount == questionCount)&&(identical(other.hasPhotos, hasPhotos) || other.hasPhotos == hasPhotos)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.questions, _questions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,formatVersion,version,id,slug,title,description,language,const DeepCollectionEquality().hash(_tags),source,visibility,isOwner,defaultSettings,questionCount,hasPhotos,createdAt,updatedAt,const DeepCollectionEquality().hash(_questions));
}

@override
String toString() {
    return 'QuizDocument(formatVersion: $formatVersion, version: $version, id: $id, slug: $slug, title: $title, description: $description, language: $language, tags: $tags, source: $source, visibility: $visibility, isOwner: $isOwner, defaultSettings: $defaultSettings, questionCount: $questionCount, hasPhotos: $hasPhotos, createdAt: $createdAt, updatedAt: $updatedAt, questions: $questions)';
}


}

/// @nodoc
abstract mixin class _$QuizDocumentCopyWith<$Res> implements $QuizDocumentCopyWith<$Res> {
  factory _$QuizDocumentCopyWith(_QuizDocument value, $Res Function(_QuizDocument) _then) = __$QuizDocumentCopyWithImpl;
@override @useResult
$Res call({
 int formatVersion,@JsonKey(fromJson: quizVersionFromJson) String version, String? id, String? slug, String title, String? description, String language, List<String> tags, String source, String visibility, bool isOwner, QuizDefaultSettings defaultSettings, int questionCount, bool hasPhotos, DateTime? createdAt, DateTime? updatedAt, List<QuizQuestion>? questions
});


@override $QuizDefaultSettingsCopyWith<$Res> get defaultSettings;

}
/// @nodoc
class __$QuizDocumentCopyWithImpl<$Res>
    implements _$QuizDocumentCopyWith<$Res> {
  __$QuizDocumentCopyWithImpl(this._self, this._then);

  final _QuizDocument _self;
  final $Res Function(_QuizDocument) _then;

/// Create a copy of QuizDocument
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? formatVersion = null,Object? version = null,Object? id = freezed,Object? slug = freezed,Object? title = null,Object? description = freezed,Object? language = null,Object? tags = null,Object? source = null,Object? visibility = null,Object? isOwner = null,Object? defaultSettings = null,Object? questionCount = null,Object? hasPhotos = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? questions = freezed,}) {
  return _then(_QuizDocument(
formatVersion: null == formatVersion ? _self.formatVersion : formatVersion // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,slug: freezed == slug ? _self.slug : slug // ignore: cast_nullable_to_non_nullable
as String?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,language: null == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,visibility: null == visibility ? _self.visibility : visibility // ignore: cast_nullable_to_non_nullable
as String,isOwner: null == isOwner ? _self.isOwner : isOwner // ignore: cast_nullable_to_non_nullable
as bool,defaultSettings: null == defaultSettings ? _self.defaultSettings : defaultSettings // ignore: cast_nullable_to_non_nullable
as QuizDefaultSettings,questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,hasPhotos: null == hasPhotos ? _self.hasPhotos : hasPhotos // ignore: cast_nullable_to_non_nullable
as bool,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,questions: freezed == questions ? _self._questions : questions // ignore: cast_nullable_to_non_nullable
as List<QuizQuestion>?,
  ));
}

/// Create a copy of QuizDocument
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizDefaultSettingsCopyWith<$Res> get defaultSettings {
  
  return $QuizDefaultSettingsCopyWith<$Res>(_self.defaultSettings, (value) {
    return _then(_self.copyWith(defaultSettings: value));
  });
}
}


/// @nodoc
mixin _$QuizDefaultSettings {

 int get timeLimitMs; bool get difficultyMultiplier;
/// Create a copy of QuizDefaultSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizDefaultSettingsCopyWith<QuizDefaultSettings> get copyWith => _$QuizDefaultSettingsCopyWithImpl<QuizDefaultSettings>(this as QuizDefaultSettings, _$identity);

  /// Serializes this QuizDefaultSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuizDefaultSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizDefaultSettings&&(identical(other.timeLimitMs, _this.timeLimitMs) || other.timeLimitMs == _this.timeLimitMs)&&(identical(other.difficultyMultiplier, _this.difficultyMultiplier) || other.difficultyMultiplier == _this.difficultyMultiplier));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizDefaultSettings;
  return Object.hash(runtimeType,_this.timeLimitMs,_this.difficultyMultiplier);
}

@override
String toString() {
  final _this = this as QuizDefaultSettings;
  return 'QuizDefaultSettings(timeLimitMs: ${_this.timeLimitMs}, difficultyMultiplier: ${_this.difficultyMultiplier})';
}


}

/// @nodoc
abstract mixin class $QuizDefaultSettingsCopyWith<$Res>  {
  factory $QuizDefaultSettingsCopyWith(QuizDefaultSettings value, $Res Function(QuizDefaultSettings) _then) = _$QuizDefaultSettingsCopyWithImpl;
@useResult
$Res call({
 int timeLimitMs, bool difficultyMultiplier
});




}
/// @nodoc
class _$QuizDefaultSettingsCopyWithImpl<$Res>
    implements $QuizDefaultSettingsCopyWith<$Res> {
  _$QuizDefaultSettingsCopyWithImpl(this._self, this._then);

  final QuizDefaultSettings _self;
  final $Res Function(QuizDefaultSettings) _then;

/// Create a copy of QuizDefaultSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? timeLimitMs = null,Object? difficultyMultiplier = null,}) {
  return _then(QuizDefaultSettings(
timeLimitMs: null == timeLimitMs ? _self.timeLimitMs : timeLimitMs // ignore: cast_nullable_to_non_nullable
as int,difficultyMultiplier: null == difficultyMultiplier ? _self.difficultyMultiplier : difficultyMultiplier // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [QuizDefaultSettings].
extension QuizDefaultSettingsPatterns on QuizDefaultSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizDefaultSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizDefaultSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizDefaultSettings value)  $default,){
final _that = this;
switch (_that) {
case _QuizDefaultSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizDefaultSettings value)?  $default,){
final _that = this;
switch (_that) {
case _QuizDefaultSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int timeLimitMs,  bool difficultyMultiplier)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizDefaultSettings() when $default != null:
return $default(_that.timeLimitMs,_that.difficultyMultiplier);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int timeLimitMs,  bool difficultyMultiplier)  $default,) {final _that = this;
switch (_that) {
case _QuizDefaultSettings():
return $default(_that.timeLimitMs,_that.difficultyMultiplier);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int timeLimitMs,  bool difficultyMultiplier)?  $default,) {final _that = this;
switch (_that) {
case _QuizDefaultSettings() when $default != null:
return $default(_that.timeLimitMs,_that.difficultyMultiplier);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizDefaultSettings implements QuizDefaultSettings {
  const _QuizDefaultSettings({this.timeLimitMs = 30000, this.difficultyMultiplier = false});
  factory _QuizDefaultSettings.fromJson(Map<String, dynamic> json) => _$QuizDefaultSettingsFromJson(json);

@override@JsonKey() final  int timeLimitMs;
@override@JsonKey() final  bool difficultyMultiplier;

/// Create a copy of QuizDefaultSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizDefaultSettingsCopyWith<_QuizDefaultSettings> get copyWith => __$QuizDefaultSettingsCopyWithImpl<_QuizDefaultSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizDefaultSettingsToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizDefaultSettings&&(identical(other.timeLimitMs, timeLimitMs) || other.timeLimitMs == timeLimitMs)&&(identical(other.difficultyMultiplier, difficultyMultiplier) || other.difficultyMultiplier == difficultyMultiplier));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,timeLimitMs,difficultyMultiplier);
}

@override
String toString() {
    return 'QuizDefaultSettings(timeLimitMs: $timeLimitMs, difficultyMultiplier: $difficultyMultiplier)';
}


}

/// @nodoc
abstract mixin class _$QuizDefaultSettingsCopyWith<$Res> implements $QuizDefaultSettingsCopyWith<$Res> {
  factory _$QuizDefaultSettingsCopyWith(_QuizDefaultSettings value, $Res Function(_QuizDefaultSettings) _then) = __$QuizDefaultSettingsCopyWithImpl;
@override @useResult
$Res call({
 int timeLimitMs, bool difficultyMultiplier
});




}
/// @nodoc
class __$QuizDefaultSettingsCopyWithImpl<$Res>
    implements _$QuizDefaultSettingsCopyWith<$Res> {
  __$QuizDefaultSettingsCopyWithImpl(this._self, this._then);

  final _QuizDefaultSettings _self;
  final $Res Function(_QuizDefaultSettings) _then;

/// Create a copy of QuizDefaultSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? timeLimitMs = null,Object? difficultyMultiplier = null,}) {
  return _then(_QuizDefaultSettings(
timeLimitMs: null == timeLimitMs ? _self.timeLimitMs : timeLimitMs // ignore: cast_nullable_to_non_nullable
as int,difficultyMultiplier: null == difficultyMultiplier ? _self.difficultyMultiplier : difficultyMultiplier // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$QuizQuestion {

 String? get id; String get type; String get prompt; List<String> get acceptedAnswers; String get difficulty; int? get timeLimitMs; QuizImage? get image; String? get explanation;
/// Create a copy of QuizQuestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizQuestionCopyWith<QuizQuestion> get copyWith => _$QuizQuestionCopyWithImpl<QuizQuestion>(this as QuizQuestion, _$identity);

  /// Serializes this QuizQuestion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuizQuestion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizQuestion&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.prompt, _this.prompt) || other.prompt == _this.prompt)&&const DeepCollectionEquality().equals(other.acceptedAnswers, _this.acceptedAnswers)&&(identical(other.difficulty, _this.difficulty) || other.difficulty == _this.difficulty)&&(identical(other.timeLimitMs, _this.timeLimitMs) || other.timeLimitMs == _this.timeLimitMs)&&(identical(other.image, _this.image) || other.image == _this.image)&&(identical(other.explanation, _this.explanation) || other.explanation == _this.explanation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizQuestion;
  return Object.hash(runtimeType,_this.id,_this.type,_this.prompt,const DeepCollectionEquality().hash(_this.acceptedAnswers),_this.difficulty,_this.timeLimitMs,_this.image,_this.explanation);
}

@override
String toString() {
  final _this = this as QuizQuestion;
  return 'QuizQuestion(id: ${_this.id}, type: ${_this.type}, prompt: ${_this.prompt}, acceptedAnswers: ${_this.acceptedAnswers}, difficulty: ${_this.difficulty}, timeLimitMs: ${_this.timeLimitMs}, image: ${_this.image}, explanation: ${_this.explanation})';
}


}

/// @nodoc
abstract mixin class $QuizQuestionCopyWith<$Res>  {
  factory $QuizQuestionCopyWith(QuizQuestion value, $Res Function(QuizQuestion) _then) = _$QuizQuestionCopyWithImpl;
@useResult
$Res call({
 String? id, String type, String prompt, List<String> acceptedAnswers, String difficulty, int? timeLimitMs, QuizImage? image, String? explanation
});


$QuizImageCopyWith<$Res>? get image;

}
/// @nodoc
class _$QuizQuestionCopyWithImpl<$Res>
    implements $QuizQuestionCopyWith<$Res> {
  _$QuizQuestionCopyWithImpl(this._self, this._then);

  final QuizQuestion _self;
  final $Res Function(QuizQuestion) _then;

/// Create a copy of QuizQuestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? type = null,Object? prompt = null,Object? acceptedAnswers = null,Object? difficulty = null,Object? timeLimitMs = freezed,Object? image = freezed,Object? explanation = freezed,}) {
  return _then(QuizQuestion(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,acceptedAnswers: null == acceptedAnswers ? _self.acceptedAnswers : acceptedAnswers // ignore: cast_nullable_to_non_nullable
as List<String>,difficulty: null == difficulty ? _self.difficulty : difficulty // ignore: cast_nullable_to_non_nullable
as String,timeLimitMs: freezed == timeLimitMs ? _self.timeLimitMs : timeLimitMs // ignore: cast_nullable_to_non_nullable
as int?,image: freezed == image ? _self.image : image // ignore: cast_nullable_to_non_nullable
as QuizImage?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of QuizQuestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizImageCopyWith<$Res>? get image {
    if (_self.image == null) {
    return null;
  }

  return $QuizImageCopyWith<$Res>(_self.image!, (value) {
    return _then(_self.copyWith(image: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuizQuestion].
extension QuizQuestionPatterns on QuizQuestion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizQuestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizQuestion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizQuestion value)  $default,){
final _that = this;
switch (_that) {
case _QuizQuestion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizQuestion value)?  $default,){
final _that = this;
switch (_that) {
case _QuizQuestion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? id,  String type,  String prompt,  List<String> acceptedAnswers,  String difficulty,  int? timeLimitMs,  QuizImage? image,  String? explanation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizQuestion() when $default != null:
return $default(_that.id,_that.type,_that.prompt,_that.acceptedAnswers,_that.difficulty,_that.timeLimitMs,_that.image,_that.explanation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? id,  String type,  String prompt,  List<String> acceptedAnswers,  String difficulty,  int? timeLimitMs,  QuizImage? image,  String? explanation)  $default,) {final _that = this;
switch (_that) {
case _QuizQuestion():
return $default(_that.id,_that.type,_that.prompt,_that.acceptedAnswers,_that.difficulty,_that.timeLimitMs,_that.image,_that.explanation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? id,  String type,  String prompt,  List<String> acceptedAnswers,  String difficulty,  int? timeLimitMs,  QuizImage? image,  String? explanation)?  $default,) {final _that = this;
switch (_that) {
case _QuizQuestion() when $default != null:
return $default(_that.id,_that.type,_that.prompt,_that.acceptedAnswers,_that.difficulty,_that.timeLimitMs,_that.image,_that.explanation);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizQuestion extends QuizQuestion {
  const _QuizQuestion({this.id, this.type = QuizQuestion.typeText, required this.prompt,  List<String> acceptedAnswers = const <String>[], this.difficulty = 'easy', this.timeLimitMs, this.image, this.explanation}): _acceptedAnswers = acceptedAnswers,super._();
  factory _QuizQuestion.fromJson(Map<String, dynamic> json) => _$QuizQuestionFromJson(json);

@override final  String? id;
@override@JsonKey() final  String type;
@override final  String prompt;
 final  List<String> _acceptedAnswers;
@override@JsonKey() List<String> get acceptedAnswers {
  if (_acceptedAnswers is EqualUnmodifiableListView) return _acceptedAnswers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_acceptedAnswers);
}

@override@JsonKey() final  String difficulty;
@override final  int? timeLimitMs;
@override final  QuizImage? image;
@override final  String? explanation;

/// Create a copy of QuizQuestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizQuestionCopyWith<_QuizQuestion> get copyWith => __$QuizQuestionCopyWithImpl<_QuizQuestion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizQuestionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizQuestion&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&const DeepCollectionEquality().equals(other.acceptedAnswers, _acceptedAnswers)&&(identical(other.difficulty, difficulty) || other.difficulty == difficulty)&&(identical(other.timeLimitMs, timeLimitMs) || other.timeLimitMs == timeLimitMs)&&(identical(other.image, image) || other.image == image)&&(identical(other.explanation, explanation) || other.explanation == explanation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,type,prompt,const DeepCollectionEquality().hash(_acceptedAnswers),difficulty,timeLimitMs,image,explanation);
}

@override
String toString() {
    return 'QuizQuestion(id: $id, type: $type, prompt: $prompt, acceptedAnswers: $acceptedAnswers, difficulty: $difficulty, timeLimitMs: $timeLimitMs, image: $image, explanation: $explanation)';
}


}

/// @nodoc
abstract mixin class _$QuizQuestionCopyWith<$Res> implements $QuizQuestionCopyWith<$Res> {
  factory _$QuizQuestionCopyWith(_QuizQuestion value, $Res Function(_QuizQuestion) _then) = __$QuizQuestionCopyWithImpl;
@override @useResult
$Res call({
 String? id, String type, String prompt, List<String> acceptedAnswers, String difficulty, int? timeLimitMs, QuizImage? image, String? explanation
});


@override $QuizImageCopyWith<$Res>? get image;

}
/// @nodoc
class __$QuizQuestionCopyWithImpl<$Res>
    implements _$QuizQuestionCopyWith<$Res> {
  __$QuizQuestionCopyWithImpl(this._self, this._then);

  final _QuizQuestion _self;
  final $Res Function(_QuizQuestion) _then;

/// Create a copy of QuizQuestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? type = null,Object? prompt = null,Object? acceptedAnswers = null,Object? difficulty = null,Object? timeLimitMs = freezed,Object? image = freezed,Object? explanation = freezed,}) {
  return _then(_QuizQuestion(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,acceptedAnswers: null == acceptedAnswers ? _self._acceptedAnswers : acceptedAnswers // ignore: cast_nullable_to_non_nullable
as List<String>,difficulty: null == difficulty ? _self.difficulty : difficulty // ignore: cast_nullable_to_non_nullable
as String,timeLimitMs: freezed == timeLimitMs ? _self.timeLimitMs : timeLimitMs // ignore: cast_nullable_to_non_nullable
as int?,image: freezed == image ? _self.image : image // ignore: cast_nullable_to_non_nullable
as QuizImage?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of QuizQuestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuizImageCopyWith<$Res>? get image {
    if (_self.image == null) {
    return null;
  }

  return $QuizImageCopyWith<$Res>(_self.image!, (value) {
    return _then(_self.copyWith(image: value));
  });
}
}


/// @nodoc
mixin _$QuizImage {

 String? get key; String? get url; String? get alt; String? get data;
/// Create a copy of QuizImage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuizImageCopyWith<QuizImage> get copyWith => _$QuizImageCopyWithImpl<QuizImage>(this as QuizImage, _$identity);

  /// Serializes this QuizImage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QuizImage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuizImage&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.alt, _this.alt) || other.alt == _this.alt)&&(identical(other.data, _this.data) || other.data == _this.data));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QuizImage;
  return Object.hash(runtimeType,_this.key,_this.url,_this.alt,_this.data);
}

@override
String toString() {
  final _this = this as QuizImage;
  return 'QuizImage(key: ${_this.key}, url: ${_this.url}, alt: ${_this.alt}, data: ${_this.data})';
}


}

/// @nodoc
abstract mixin class $QuizImageCopyWith<$Res>  {
  factory $QuizImageCopyWith(QuizImage value, $Res Function(QuizImage) _then) = _$QuizImageCopyWithImpl;
@useResult
$Res call({
 String? key, String? url, String? alt, String? data
});




}
/// @nodoc
class _$QuizImageCopyWithImpl<$Res>
    implements $QuizImageCopyWith<$Res> {
  _$QuizImageCopyWithImpl(this._self, this._then);

  final QuizImage _self;
  final $Res Function(QuizImage) _then;

/// Create a copy of QuizImage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = freezed,Object? url = freezed,Object? alt = freezed,Object? data = freezed,}) {
  return _then(QuizImage(
key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,alt: freezed == alt ? _self.alt : alt // ignore: cast_nullable_to_non_nullable
as String?,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [QuizImage].
extension QuizImagePatterns on QuizImage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuizImage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuizImage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuizImage value)  $default,){
final _that = this;
switch (_that) {
case _QuizImage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuizImage value)?  $default,){
final _that = this;
switch (_that) {
case _QuizImage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? key,  String? url,  String? alt,  String? data)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuizImage() when $default != null:
return $default(_that.key,_that.url,_that.alt,_that.data);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? key,  String? url,  String? alt,  String? data)  $default,) {final _that = this;
switch (_that) {
case _QuizImage():
return $default(_that.key,_that.url,_that.alt,_that.data);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? key,  String? url,  String? alt,  String? data)?  $default,) {final _that = this;
switch (_that) {
case _QuizImage() when $default != null:
return $default(_that.key,_that.url,_that.alt,_that.data);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QuizImage implements QuizImage {
  const _QuizImage({this.key, this.url, this.alt, this.data});
  factory _QuizImage.fromJson(Map<String, dynamic> json) => _$QuizImageFromJson(json);

@override final  String? key;
@override final  String? url;
@override final  String? alt;
@override final  String? data;

/// Create a copy of QuizImage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuizImageCopyWith<_QuizImage> get copyWith => __$QuizImageCopyWithImpl<_QuizImage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuizImageToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuizImage&&(identical(other.key, key) || other.key == key)&&(identical(other.url, url) || other.url == url)&&(identical(other.alt, alt) || other.alt == alt)&&(identical(other.data, data) || other.data == data));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,key,url,alt,data);
}

@override
String toString() {
    return 'QuizImage(key: $key, url: $url, alt: $alt, data: $data)';
}


}

/// @nodoc
abstract mixin class _$QuizImageCopyWith<$Res> implements $QuizImageCopyWith<$Res> {
  factory _$QuizImageCopyWith(_QuizImage value, $Res Function(_QuizImage) _then) = __$QuizImageCopyWithImpl;
@override @useResult
$Res call({
 String? key, String? url, String? alt, String? data
});




}
/// @nodoc
class __$QuizImageCopyWithImpl<$Res>
    implements _$QuizImageCopyWith<$Res> {
  __$QuizImageCopyWithImpl(this._self, this._then);

  final _QuizImage _self;
  final $Res Function(_QuizImage) _then;

/// Create a copy of QuizImage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = freezed,Object? url = freezed,Object? alt = freezed,Object? data = freezed,}) {
  return _then(_QuizImage(
key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,alt: freezed == alt ? _self.alt : alt // ignore: cast_nullable_to_non_nullable
as String?,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
