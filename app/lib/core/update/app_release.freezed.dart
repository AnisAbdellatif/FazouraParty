// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_release.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AppRelease {

 String get version; int get versionCode; String get url;/// Size of the APK in bytes, shown before the download starts.
 int? get size;/// SHA-256 of the APK, so a download can be checked by hand. Nothing in
/// the app verifies it — the browser does the downloading.
 String? get sha256;/// The tag's message, when it had one.
 String? get notes;
/// Create a copy of AppRelease
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppReleaseCopyWith<AppRelease> get copyWith => _$AppReleaseCopyWithImpl<AppRelease>(this as AppRelease, _$identity);

  /// Serializes this AppRelease to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AppRelease;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRelease&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.versionCode, _this.versionCode) || other.versionCode == _this.versionCode)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.sha256, _this.sha256) || other.sha256 == _this.sha256)&&(identical(other.notes, _this.notes) || other.notes == _this.notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AppRelease;
  return Object.hash(runtimeType,_this.version,_this.versionCode,_this.url,_this.size,_this.sha256,_this.notes);
}

@override
String toString() {
  final _this = this as AppRelease;
  return 'AppRelease(version: ${_this.version}, versionCode: ${_this.versionCode}, url: ${_this.url}, size: ${_this.size}, sha256: ${_this.sha256}, notes: ${_this.notes})';
}


}

/// @nodoc
abstract mixin class $AppReleaseCopyWith<$Res>  {
  factory $AppReleaseCopyWith(AppRelease value, $Res Function(AppRelease) _then) = _$AppReleaseCopyWithImpl;
@useResult
$Res call({
 String version, int versionCode, String url, int? size, String? sha256, String? notes
});




}
/// @nodoc
class _$AppReleaseCopyWithImpl<$Res>
    implements $AppReleaseCopyWith<$Res> {
  _$AppReleaseCopyWithImpl(this._self, this._then);

  final AppRelease _self;
  final $Res Function(AppRelease) _then;

/// Create a copy of AppRelease
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? versionCode = null,Object? url = null,Object? size = freezed,Object? sha256 = freezed,Object? notes = freezed,}) {
  return _then(AppRelease(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,versionCode: null == versionCode ? _self.versionCode : versionCode // ignore: cast_nullable_to_non_nullable
as int,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,size: freezed == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AppRelease].
extension AppReleasePatterns on AppRelease {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppRelease value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppRelease() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppRelease value)  $default,){
final _that = this;
switch (_that) {
case _AppRelease():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppRelease value)?  $default,){
final _that = this;
switch (_that) {
case _AppRelease() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String version,  int versionCode,  String url,  int? size,  String? sha256,  String? notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppRelease() when $default != null:
return $default(_that.version,_that.versionCode,_that.url,_that.size,_that.sha256,_that.notes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String version,  int versionCode,  String url,  int? size,  String? sha256,  String? notes)  $default,) {final _that = this;
switch (_that) {
case _AppRelease():
return $default(_that.version,_that.versionCode,_that.url,_that.size,_that.sha256,_that.notes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String version,  int versionCode,  String url,  int? size,  String? sha256,  String? notes)?  $default,) {final _that = this;
switch (_that) {
case _AppRelease() when $default != null:
return $default(_that.version,_that.versionCode,_that.url,_that.size,_that.sha256,_that.notes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppRelease extends AppRelease {
  const _AppRelease({required this.version, required this.versionCode, required this.url, this.size, this.sha256, this.notes}): super._();
  factory _AppRelease.fromJson(Map<String, dynamic> json) => _$AppReleaseFromJson(json);

@override final  String version;
@override final  int versionCode;
@override final  String url;
/// Size of the APK in bytes, shown before the download starts.
@override final  int? size;
/// SHA-256 of the APK, so a download can be checked by hand. Nothing in
/// the app verifies it — the browser does the downloading.
@override final  String? sha256;
/// The tag's message, when it had one.
@override final  String? notes;

/// Create a copy of AppRelease
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppReleaseCopyWith<_AppRelease> get copyWith => __$AppReleaseCopyWithImpl<_AppRelease>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AppReleaseToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppRelease&&(identical(other.version, version) || other.version == version)&&(identical(other.versionCode, versionCode) || other.versionCode == versionCode)&&(identical(other.url, url) || other.url == url)&&(identical(other.size, size) || other.size == size)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,version,versionCode,url,size,sha256,notes);
}

@override
String toString() {
    return 'AppRelease(version: $version, versionCode: $versionCode, url: $url, size: $size, sha256: $sha256, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$AppReleaseCopyWith<$Res> implements $AppReleaseCopyWith<$Res> {
  factory _$AppReleaseCopyWith(_AppRelease value, $Res Function(_AppRelease) _then) = __$AppReleaseCopyWithImpl;
@override @useResult
$Res call({
 String version, int versionCode, String url, int? size, String? sha256, String? notes
});




}
/// @nodoc
class __$AppReleaseCopyWithImpl<$Res>
    implements _$AppReleaseCopyWith<$Res> {
  __$AppReleaseCopyWithImpl(this._self, this._then);

  final _AppRelease _self;
  final $Res Function(_AppRelease) _then;

/// Create a copy of AppRelease
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? versionCode = null,Object? url = null,Object? size = freezed,Object? sha256 = freezed,Object? notes = freezed,}) {
  return _then(_AppRelease(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,versionCode: null == versionCode ? _self.versionCode : versionCode // ignore: cast_nullable_to_non_nullable
as int,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,size: freezed == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
