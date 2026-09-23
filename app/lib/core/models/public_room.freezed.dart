// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'public_room.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PublicRoom {

 String get roomCode; Phase get phase;/// Empty while the host is still choosing.
 List<String> get packTitles; int get playerCount;/// How many the room lets in (PROTOCOL.md §6.5). Absent before 9.9.
 int? get roomSize; int? get questionIndex; int get questionCount;
/// Create a copy of PublicRoom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PublicRoomCopyWith<PublicRoom> get copyWith => _$PublicRoomCopyWithImpl<PublicRoom>(this as PublicRoom, _$identity);

  /// Serializes this PublicRoom to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PublicRoom;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PublicRoom&&(identical(other.roomCode, _this.roomCode) || other.roomCode == _this.roomCode)&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&const DeepCollectionEquality().equals(other.packTitles, _this.packTitles)&&(identical(other.playerCount, _this.playerCount) || other.playerCount == _this.playerCount)&&(identical(other.roomSize, _this.roomSize) || other.roomSize == _this.roomSize)&&(identical(other.questionIndex, _this.questionIndex) || other.questionIndex == _this.questionIndex)&&(identical(other.questionCount, _this.questionCount) || other.questionCount == _this.questionCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PublicRoom;
  return Object.hash(runtimeType,_this.roomCode,_this.phase,const DeepCollectionEquality().hash(_this.packTitles),_this.playerCount,_this.roomSize,_this.questionIndex,_this.questionCount);
}

@override
String toString() {
  final _this = this as PublicRoom;
  return 'PublicRoom(roomCode: ${_this.roomCode}, phase: ${_this.phase}, packTitles: ${_this.packTitles}, playerCount: ${_this.playerCount}, roomSize: ${_this.roomSize}, questionIndex: ${_this.questionIndex}, questionCount: ${_this.questionCount})';
}


}

/// @nodoc
abstract mixin class $PublicRoomCopyWith<$Res>  {
  factory $PublicRoomCopyWith(PublicRoom value, $Res Function(PublicRoom) _then) = _$PublicRoomCopyWithImpl;
@useResult
$Res call({
 String roomCode, Phase phase, List<String> packTitles, int playerCount, int? roomSize, int? questionIndex, int questionCount
});




}
/// @nodoc
class _$PublicRoomCopyWithImpl<$Res>
    implements $PublicRoomCopyWith<$Res> {
  _$PublicRoomCopyWithImpl(this._self, this._then);

  final PublicRoom _self;
  final $Res Function(PublicRoom) _then;

/// Create a copy of PublicRoom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roomCode = null,Object? phase = null,Object? packTitles = null,Object? playerCount = null,Object? roomSize = freezed,Object? questionIndex = freezed,Object? questionCount = null,}) {
  return _then(PublicRoom(
roomCode: null == roomCode ? _self.roomCode : roomCode // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as Phase,packTitles: null == packTitles ? _self.packTitles : packTitles // ignore: cast_nullable_to_non_nullable
as List<String>,playerCount: null == playerCount ? _self.playerCount : playerCount // ignore: cast_nullable_to_non_nullable
as int,roomSize: freezed == roomSize ? _self.roomSize : roomSize // ignore: cast_nullable_to_non_nullable
as int?,questionIndex: freezed == questionIndex ? _self.questionIndex : questionIndex // ignore: cast_nullable_to_non_nullable
as int?,questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PublicRoom].
extension PublicRoomPatterns on PublicRoom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PublicRoom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PublicRoom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PublicRoom value)  $default,){
final _that = this;
switch (_that) {
case _PublicRoom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PublicRoom value)?  $default,){
final _that = this;
switch (_that) {
case _PublicRoom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String roomCode,  Phase phase,  List<String> packTitles,  int playerCount,  int? roomSize,  int? questionIndex,  int questionCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PublicRoom() when $default != null:
return $default(_that.roomCode,_that.phase,_that.packTitles,_that.playerCount,_that.roomSize,_that.questionIndex,_that.questionCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String roomCode,  Phase phase,  List<String> packTitles,  int playerCount,  int? roomSize,  int? questionIndex,  int questionCount)  $default,) {final _that = this;
switch (_that) {
case _PublicRoom():
return $default(_that.roomCode,_that.phase,_that.packTitles,_that.playerCount,_that.roomSize,_that.questionIndex,_that.questionCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String roomCode,  Phase phase,  List<String> packTitles,  int playerCount,  int? roomSize,  int? questionIndex,  int questionCount)?  $default,) {final _that = this;
switch (_that) {
case _PublicRoom() when $default != null:
return $default(_that.roomCode,_that.phase,_that.packTitles,_that.playerCount,_that.roomSize,_that.questionIndex,_that.questionCount);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PublicRoom implements PublicRoom {
  const _PublicRoom({required this.roomCode, required this.phase,  List<String> packTitles = const <String>[], required this.playerCount, this.roomSize, this.questionIndex, required this.questionCount}): _packTitles = packTitles;
  factory _PublicRoom.fromJson(Map<String, dynamic> json) => _$PublicRoomFromJson(json);

@override final  String roomCode;
@override final  Phase phase;
/// Empty while the host is still choosing.
 final  List<String> _packTitles;
/// Empty while the host is still choosing.
@override@JsonKey() List<String> get packTitles {
  if (_packTitles is EqualUnmodifiableListView) return _packTitles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_packTitles);
}

@override final  int playerCount;
/// How many the room lets in (PROTOCOL.md §6.5). Absent before 9.9.
@override final  int? roomSize;
@override final  int? questionIndex;
@override final  int questionCount;

/// Create a copy of PublicRoom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PublicRoomCopyWith<_PublicRoom> get copyWith => __$PublicRoomCopyWithImpl<_PublicRoom>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PublicRoomToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PublicRoom&&(identical(other.roomCode, roomCode) || other.roomCode == roomCode)&&(identical(other.phase, phase) || other.phase == phase)&&const DeepCollectionEquality().equals(other.packTitles, _packTitles)&&(identical(other.playerCount, playerCount) || other.playerCount == playerCount)&&(identical(other.roomSize, roomSize) || other.roomSize == roomSize)&&(identical(other.questionIndex, questionIndex) || other.questionIndex == questionIndex)&&(identical(other.questionCount, questionCount) || other.questionCount == questionCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,roomCode,phase,const DeepCollectionEquality().hash(_packTitles),playerCount,roomSize,questionIndex,questionCount);
}

@override
String toString() {
    return 'PublicRoom(roomCode: $roomCode, phase: $phase, packTitles: $packTitles, playerCount: $playerCount, roomSize: $roomSize, questionIndex: $questionIndex, questionCount: $questionCount)';
}


}

/// @nodoc
abstract mixin class _$PublicRoomCopyWith<$Res> implements $PublicRoomCopyWith<$Res> {
  factory _$PublicRoomCopyWith(_PublicRoom value, $Res Function(_PublicRoom) _then) = __$PublicRoomCopyWithImpl;
@override @useResult
$Res call({
 String roomCode, Phase phase, List<String> packTitles, int playerCount, int? roomSize, int? questionIndex, int questionCount
});




}
/// @nodoc
class __$PublicRoomCopyWithImpl<$Res>
    implements _$PublicRoomCopyWith<$Res> {
  __$PublicRoomCopyWithImpl(this._self, this._then);

  final _PublicRoom _self;
  final $Res Function(_PublicRoom) _then;

/// Create a copy of PublicRoom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomCode = null,Object? phase = null,Object? packTitles = null,Object? playerCount = null,Object? roomSize = freezed,Object? questionIndex = freezed,Object? questionCount = null,}) {
  return _then(_PublicRoom(
roomCode: null == roomCode ? _self.roomCode : roomCode // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as Phase,packTitles: null == packTitles ? _self._packTitles : packTitles // ignore: cast_nullable_to_non_nullable
as List<String>,playerCount: null == playerCount ? _self.playerCount : playerCount // ignore: cast_nullable_to_non_nullable
as int,roomSize: freezed == roomSize ? _self.roomSize : roomSize // ignore: cast_nullable_to_non_nullable
as int?,questionIndex: freezed == questionIndex ? _self.questionIndex : questionIndex // ignore: cast_nullable_to_non_nullable
as int?,questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
