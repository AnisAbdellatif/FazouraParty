// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'join_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$JoinResult {

 Role get role; String? get playerId; String? get playerToken;
/// Create a copy of JoinResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JoinResultCopyWith<JoinResult> get copyWith => _$JoinResultCopyWithImpl<JoinResult>(this as JoinResult, _$identity);

  /// Serializes this JoinResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as JoinResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JoinResult&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.playerId, _this.playerId) || other.playerId == _this.playerId)&&(identical(other.playerToken, _this.playerToken) || other.playerToken == _this.playerToken));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as JoinResult;
  return Object.hash(runtimeType,_this.role,_this.playerId,_this.playerToken);
}

@override
String toString() {
  final _this = this as JoinResult;
  return 'JoinResult(role: ${_this.role}, playerId: ${_this.playerId}, playerToken: ${_this.playerToken})';
}


}

/// @nodoc
abstract mixin class $JoinResultCopyWith<$Res>  {
  factory $JoinResultCopyWith(JoinResult value, $Res Function(JoinResult) _then) = _$JoinResultCopyWithImpl;
@useResult
$Res call({
 Role role, String? playerId, String? playerToken
});




}
/// @nodoc
class _$JoinResultCopyWithImpl<$Res>
    implements $JoinResultCopyWith<$Res> {
  _$JoinResultCopyWithImpl(this._self, this._then);

  final JoinResult _self;
  final $Res Function(JoinResult) _then;

/// Create a copy of JoinResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? role = null,Object? playerId = freezed,Object? playerToken = freezed,}) {
  return _then(JoinResult(
role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as Role,playerId: freezed == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as String?,playerToken: freezed == playerToken ? _self.playerToken : playerToken // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [JoinResult].
extension JoinResultPatterns on JoinResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JoinResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JoinResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JoinResult value)  $default,){
final _that = this;
switch (_that) {
case _JoinResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JoinResult value)?  $default,){
final _that = this;
switch (_that) {
case _JoinResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Role role,  String? playerId,  String? playerToken)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JoinResult() when $default != null:
return $default(_that.role,_that.playerId,_that.playerToken);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Role role,  String? playerId,  String? playerToken)  $default,) {final _that = this;
switch (_that) {
case _JoinResult():
return $default(_that.role,_that.playerId,_that.playerToken);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Role role,  String? playerId,  String? playerToken)?  $default,) {final _that = this;
switch (_that) {
case _JoinResult() when $default != null:
return $default(_that.role,_that.playerId,_that.playerToken);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JoinResult implements JoinResult {
  const _JoinResult({required this.role, this.playerId, this.playerToken});
  factory _JoinResult.fromJson(Map<String, dynamic> json) => _$JoinResultFromJson(json);

@override final  Role role;
@override final  String? playerId;
@override final  String? playerToken;

/// Create a copy of JoinResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JoinResultCopyWith<_JoinResult> get copyWith => __$JoinResultCopyWithImpl<_JoinResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JoinResultToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _JoinResult&&(identical(other.role, role) || other.role == role)&&(identical(other.playerId, playerId) || other.playerId == playerId)&&(identical(other.playerToken, playerToken) || other.playerToken == playerToken));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,role,playerId,playerToken);
}

@override
String toString() {
    return 'JoinResult(role: $role, playerId: $playerId, playerToken: $playerToken)';
}


}

/// @nodoc
abstract mixin class _$JoinResultCopyWith<$Res> implements $JoinResultCopyWith<$Res> {
  factory _$JoinResultCopyWith(_JoinResult value, $Res Function(_JoinResult) _then) = __$JoinResultCopyWithImpl;
@override @useResult
$Res call({
 Role role, String? playerId, String? playerToken
});




}
/// @nodoc
class __$JoinResultCopyWithImpl<$Res>
    implements _$JoinResultCopyWith<$Res> {
  __$JoinResultCopyWithImpl(this._self, this._then);

  final _JoinResult _self;
  final $Res Function(_JoinResult) _then;

/// Create a copy of JoinResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? role = null,Object? playerId = freezed,Object? playerToken = freezed,}) {
  return _then(_JoinResult(
role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as Role,playerId: freezed == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as String?,playerToken: freezed == playerToken ? _self.playerToken : playerToken // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$CreatedRoom {

 String get roomCode; String get hostToken;
/// Create a copy of CreatedRoom
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CreatedRoomCopyWith<CreatedRoom> get copyWith => _$CreatedRoomCopyWithImpl<CreatedRoom>(this as CreatedRoom, _$identity);

  /// Serializes this CreatedRoom to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CreatedRoom;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CreatedRoom&&(identical(other.roomCode, _this.roomCode) || other.roomCode == _this.roomCode)&&(identical(other.hostToken, _this.hostToken) || other.hostToken == _this.hostToken));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CreatedRoom;
  return Object.hash(runtimeType,_this.roomCode,_this.hostToken);
}

@override
String toString() {
  final _this = this as CreatedRoom;
  return 'CreatedRoom(roomCode: ${_this.roomCode}, hostToken: ${_this.hostToken})';
}


}

/// @nodoc
abstract mixin class $CreatedRoomCopyWith<$Res>  {
  factory $CreatedRoomCopyWith(CreatedRoom value, $Res Function(CreatedRoom) _then) = _$CreatedRoomCopyWithImpl;
@useResult
$Res call({
 String roomCode, String hostToken
});




}
/// @nodoc
class _$CreatedRoomCopyWithImpl<$Res>
    implements $CreatedRoomCopyWith<$Res> {
  _$CreatedRoomCopyWithImpl(this._self, this._then);

  final CreatedRoom _self;
  final $Res Function(CreatedRoom) _then;

/// Create a copy of CreatedRoom
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roomCode = null,Object? hostToken = null,}) {
  return _then(CreatedRoom(
roomCode: null == roomCode ? _self.roomCode : roomCode // ignore: cast_nullable_to_non_nullable
as String,hostToken: null == hostToken ? _self.hostToken : hostToken // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CreatedRoom].
extension CreatedRoomPatterns on CreatedRoom {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CreatedRoom value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CreatedRoom() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CreatedRoom value)  $default,){
final _that = this;
switch (_that) {
case _CreatedRoom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CreatedRoom value)?  $default,){
final _that = this;
switch (_that) {
case _CreatedRoom() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String roomCode,  String hostToken)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CreatedRoom() when $default != null:
return $default(_that.roomCode,_that.hostToken);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String roomCode,  String hostToken)  $default,) {final _that = this;
switch (_that) {
case _CreatedRoom():
return $default(_that.roomCode,_that.hostToken);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String roomCode,  String hostToken)?  $default,) {final _that = this;
switch (_that) {
case _CreatedRoom() when $default != null:
return $default(_that.roomCode,_that.hostToken);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CreatedRoom implements CreatedRoom {
  const _CreatedRoom({required this.roomCode, required this.hostToken});
  factory _CreatedRoom.fromJson(Map<String, dynamic> json) => _$CreatedRoomFromJson(json);

@override final  String roomCode;
@override final  String hostToken;

/// Create a copy of CreatedRoom
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CreatedRoomCopyWith<_CreatedRoom> get copyWith => __$CreatedRoomCopyWithImpl<_CreatedRoom>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CreatedRoomToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CreatedRoom&&(identical(other.roomCode, roomCode) || other.roomCode == roomCode)&&(identical(other.hostToken, hostToken) || other.hostToken == hostToken));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,roomCode,hostToken);
}

@override
String toString() {
    return 'CreatedRoom(roomCode: $roomCode, hostToken: $hostToken)';
}


}

/// @nodoc
abstract mixin class _$CreatedRoomCopyWith<$Res> implements $CreatedRoomCopyWith<$Res> {
  factory _$CreatedRoomCopyWith(_CreatedRoom value, $Res Function(_CreatedRoom) _then) = __$CreatedRoomCopyWithImpl;
@override @useResult
$Res call({
 String roomCode, String hostToken
});




}
/// @nodoc
class __$CreatedRoomCopyWithImpl<$Res>
    implements _$CreatedRoomCopyWith<$Res> {
  __$CreatedRoomCopyWithImpl(this._self, this._then);

  final _CreatedRoom _self;
  final $Res Function(_CreatedRoom) _then;

/// Create a copy of CreatedRoom
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roomCode = null,Object? hostToken = null,}) {
  return _then(_CreatedRoom(
roomCode: null == roomCode ? _self.roomCode : roomCode // ignore: cast_nullable_to_non_nullable
as String,hostToken: null == hostToken ? _self.hostToken : hostToken // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
