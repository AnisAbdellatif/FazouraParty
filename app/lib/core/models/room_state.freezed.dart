// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'room_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoomState {

 int get protocolVersion; String get roomCode; Mode get mode; Phase get phase;/// Host clock (ms since epoch) when the snapshot was built.
 int get serverTime; String? get packTitle; int? get questionIndex; int get questionCount;/// 1 for the first game in the room, +1 per rematch (protocol v3).
 int get gameNumber; GameSettings? get settings; Question? get question;/// Absolute server timestamp (ms since epoch); set only in `question`
/// while not paused.
 int? get deadline; int? get pausedRemainingMs; List<String>? get acceptedAnswers; List<PlayerSummary> get players; You get you; List<SubmissionView>? get submissions;
/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomStateCopyWith<RoomState> get copyWith => _$RoomStateCopyWithImpl<RoomState>(this as RoomState, _$identity);

  /// Serializes this RoomState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RoomState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomState&&(identical(other.protocolVersion, _this.protocolVersion) || other.protocolVersion == _this.protocolVersion)&&(identical(other.roomCode, _this.roomCode) || other.roomCode == _this.roomCode)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.serverTime, _this.serverTime) || other.serverTime == _this.serverTime)&&(identical(other.packTitle, _this.packTitle) || other.packTitle == _this.packTitle)&&(identical(other.questionIndex, _this.questionIndex) || other.questionIndex == _this.questionIndex)&&(identical(other.questionCount, _this.questionCount) || other.questionCount == _this.questionCount)&&(identical(other.gameNumber, _this.gameNumber) || other.gameNumber == _this.gameNumber)&&(identical(other.settings, _this.settings) || other.settings == _this.settings)&&(identical(other.question, _this.question) || other.question == _this.question)&&(identical(other.deadline, _this.deadline) || other.deadline == _this.deadline)&&(identical(other.pausedRemainingMs, _this.pausedRemainingMs) || other.pausedRemainingMs == _this.pausedRemainingMs)&&const DeepCollectionEquality().equals(other.acceptedAnswers, _this.acceptedAnswers)&&const DeepCollectionEquality().equals(other.players, _this.players)&&(identical(other.you, _this.you) || other.you == _this.you)&&const DeepCollectionEquality().equals(other.submissions, _this.submissions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RoomState;
  return Object.hash(runtimeType,_this.protocolVersion,_this.roomCode,_this.mode,_this.phase,_this.serverTime,_this.packTitle,_this.questionIndex,_this.questionCount,_this.gameNumber,_this.settings,_this.question,_this.deadline,_this.pausedRemainingMs,const DeepCollectionEquality().hash(_this.acceptedAnswers),const DeepCollectionEquality().hash(_this.players),_this.you,const DeepCollectionEquality().hash(_this.submissions));
}

@override
String toString() {
  final _this = this as RoomState;
  return 'RoomState(protocolVersion: ${_this.protocolVersion}, roomCode: ${_this.roomCode}, mode: ${_this.mode}, phase: ${_this.phase}, serverTime: ${_this.serverTime}, packTitle: ${_this.packTitle}, questionIndex: ${_this.questionIndex}, questionCount: ${_this.questionCount}, gameNumber: ${_this.gameNumber}, settings: ${_this.settings}, question: ${_this.question}, deadline: ${_this.deadline}, pausedRemainingMs: ${_this.pausedRemainingMs}, acceptedAnswers: ${_this.acceptedAnswers}, players: ${_this.players}, you: ${_this.you}, submissions: ${_this.submissions})';
}


}

/// @nodoc
abstract mixin class $RoomStateCopyWith<$Res>  {
  factory $RoomStateCopyWith(RoomState value, $Res Function(RoomState) _then) = _$RoomStateCopyWithImpl;
@useResult
$Res call({
 int protocolVersion, String roomCode, Mode mode, Phase phase, int serverTime, String? packTitle, int? questionIndex, int questionCount, int gameNumber, GameSettings? settings, Question? question, int? deadline, int? pausedRemainingMs, List<String>? acceptedAnswers, List<PlayerSummary> players, You you, List<SubmissionView>? submissions
});


$GameSettingsCopyWith<$Res>? get settings;$QuestionCopyWith<$Res>? get question;$YouCopyWith<$Res> get you;

}
/// @nodoc
class _$RoomStateCopyWithImpl<$Res>
    implements $RoomStateCopyWith<$Res> {
  _$RoomStateCopyWithImpl(this._self, this._then);

  final RoomState _self;
  final $Res Function(RoomState) _then;

/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? protocolVersion = null,Object? roomCode = null,Object? mode = null,Object? phase = null,Object? serverTime = null,Object? packTitle = freezed,Object? questionIndex = freezed,Object? questionCount = null,Object? gameNumber = null,Object? settings = freezed,Object? question = freezed,Object? deadline = freezed,Object? pausedRemainingMs = freezed,Object? acceptedAnswers = freezed,Object? players = null,Object? you = null,Object? submissions = freezed,}) {
  return _then(RoomState(
protocolVersion: null == protocolVersion ? _self.protocolVersion : protocolVersion // ignore: cast_nullable_to_non_nullable
as int,roomCode: null == roomCode ? _self.roomCode : roomCode // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as Mode,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as Phase,serverTime: null == serverTime ? _self.serverTime : serverTime // ignore: cast_nullable_to_non_nullable
as int,packTitle: freezed == packTitle ? _self.packTitle : packTitle // ignore: cast_nullable_to_non_nullable
as String?,questionIndex: freezed == questionIndex ? _self.questionIndex : questionIndex // ignore: cast_nullable_to_non_nullable
as int?,questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,gameNumber: null == gameNumber ? _self.gameNumber : gameNumber // ignore: cast_nullable_to_non_nullable
as int,settings: freezed == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as GameSettings?,question: freezed == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as Question?,deadline: freezed == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as int?,pausedRemainingMs: freezed == pausedRemainingMs ? _self.pausedRemainingMs : pausedRemainingMs // ignore: cast_nullable_to_non_nullable
as int?,acceptedAnswers: freezed == acceptedAnswers ? _self.acceptedAnswers : acceptedAnswers // ignore: cast_nullable_to_non_nullable
as List<String>?,players: null == players ? _self.players : players // ignore: cast_nullable_to_non_nullable
as List<PlayerSummary>,you: null == you ? _self.you : you // ignore: cast_nullable_to_non_nullable
as You,submissions: freezed == submissions ? _self.submissions : submissions // ignore: cast_nullable_to_non_nullable
as List<SubmissionView>?,
  ));
}
/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameSettingsCopyWith<$Res>? get settings {
    if (_self.settings == null) {
    return null;
  }

  return $GameSettingsCopyWith<$Res>(_self.settings!, (value) {
    return _then(_self.copyWith(settings: value));
  });
}/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuestionCopyWith<$Res>? get question {
    if (_self.question == null) {
    return null;
  }

  return $QuestionCopyWith<$Res>(_self.question!, (value) {
    return _then(_self.copyWith(question: value));
  });
}/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$YouCopyWith<$Res> get you {
  
  return $YouCopyWith<$Res>(_self.you, (value) {
    return _then(_self.copyWith(you: value));
  });
}
}


/// Adds pattern-matching-related methods to [RoomState].
extension RoomStatePatterns on RoomState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomState value)  $default,){
final _that = this;
switch (_that) {
case _RoomState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomState value)?  $default,){
final _that = this;
switch (_that) {
case _RoomState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int protocolVersion,  String roomCode,  Mode mode,  Phase phase,  int serverTime,  String? packTitle,  int? questionIndex,  int questionCount,  int gameNumber,  GameSettings? settings,  Question? question,  int? deadline,  int? pausedRemainingMs,  List<String>? acceptedAnswers,  List<PlayerSummary> players,  You you,  List<SubmissionView>? submissions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomState() when $default != null:
return $default(_that.protocolVersion,_that.roomCode,_that.mode,_that.phase,_that.serverTime,_that.packTitle,_that.questionIndex,_that.questionCount,_that.gameNumber,_that.settings,_that.question,_that.deadline,_that.pausedRemainingMs,_that.acceptedAnswers,_that.players,_that.you,_that.submissions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int protocolVersion,  String roomCode,  Mode mode,  Phase phase,  int serverTime,  String? packTitle,  int? questionIndex,  int questionCount,  int gameNumber,  GameSettings? settings,  Question? question,  int? deadline,  int? pausedRemainingMs,  List<String>? acceptedAnswers,  List<PlayerSummary> players,  You you,  List<SubmissionView>? submissions)  $default,) {final _that = this;
switch (_that) {
case _RoomState():
return $default(_that.protocolVersion,_that.roomCode,_that.mode,_that.phase,_that.serverTime,_that.packTitle,_that.questionIndex,_that.questionCount,_that.gameNumber,_that.settings,_that.question,_that.deadline,_that.pausedRemainingMs,_that.acceptedAnswers,_that.players,_that.you,_that.submissions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int protocolVersion,  String roomCode,  Mode mode,  Phase phase,  int serverTime,  String? packTitle,  int? questionIndex,  int questionCount,  int gameNumber,  GameSettings? settings,  Question? question,  int? deadline,  int? pausedRemainingMs,  List<String>? acceptedAnswers,  List<PlayerSummary> players,  You you,  List<SubmissionView>? submissions)?  $default,) {final _that = this;
switch (_that) {
case _RoomState() when $default != null:
return $default(_that.protocolVersion,_that.roomCode,_that.mode,_that.phase,_that.serverTime,_that.packTitle,_that.questionIndex,_that.questionCount,_that.gameNumber,_that.settings,_that.question,_that.deadline,_that.pausedRemainingMs,_that.acceptedAnswers,_that.players,_that.you,_that.submissions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoomState implements RoomState {
  const _RoomState({required this.protocolVersion, required this.roomCode, required this.mode, required this.phase, required this.serverTime, this.packTitle, this.questionIndex, required this.questionCount, this.gameNumber = 1, this.settings, this.question, this.deadline, this.pausedRemainingMs,  List<String>? acceptedAnswers,  List<PlayerSummary> players = const <PlayerSummary>[], required this.you,  List<SubmissionView>? submissions}): _acceptedAnswers = acceptedAnswers,_players = players,_submissions = submissions;
  factory _RoomState.fromJson(Map<String, dynamic> json) => _$RoomStateFromJson(json);

@override final  int protocolVersion;
@override final  String roomCode;
@override final  Mode mode;
@override final  Phase phase;
/// Host clock (ms since epoch) when the snapshot was built.
@override final  int serverTime;
@override final  String? packTitle;
@override final  int? questionIndex;
@override final  int questionCount;
/// 1 for the first game in the room, +1 per rematch (protocol v3).
@override@JsonKey() final  int gameNumber;
@override final  GameSettings? settings;
@override final  Question? question;
/// Absolute server timestamp (ms since epoch); set only in `question`
/// while not paused.
@override final  int? deadline;
@override final  int? pausedRemainingMs;
 final  List<String>? _acceptedAnswers;
@override List<String>? get acceptedAnswers {
  final value = _acceptedAnswers;
  if (value == null) return null;
  if (_acceptedAnswers is EqualUnmodifiableListView) return _acceptedAnswers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<PlayerSummary> _players;
@override@JsonKey() List<PlayerSummary> get players {
  if (_players is EqualUnmodifiableListView) return _players;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_players);
}

@override final  You you;
 final  List<SubmissionView>? _submissions;
@override List<SubmissionView>? get submissions {
  final value = _submissions;
  if (value == null) return null;
  if (_submissions is EqualUnmodifiableListView) return _submissions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomStateCopyWith<_RoomState> get copyWith => __$RoomStateCopyWithImpl<_RoomState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoomStateToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomState&&(identical(other.protocolVersion, protocolVersion) || other.protocolVersion == protocolVersion)&&(identical(other.roomCode, roomCode) || other.roomCode == roomCode)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.serverTime, serverTime) || other.serverTime == serverTime)&&(identical(other.packTitle, packTitle) || other.packTitle == packTitle)&&(identical(other.questionIndex, questionIndex) || other.questionIndex == questionIndex)&&(identical(other.questionCount, questionCount) || other.questionCount == questionCount)&&(identical(other.gameNumber, gameNumber) || other.gameNumber == gameNumber)&&(identical(other.settings, settings) || other.settings == settings)&&(identical(other.question, question) || other.question == question)&&(identical(other.deadline, deadline) || other.deadline == deadline)&&(identical(other.pausedRemainingMs, pausedRemainingMs) || other.pausedRemainingMs == pausedRemainingMs)&&const DeepCollectionEquality().equals(other.acceptedAnswers, _acceptedAnswers)&&const DeepCollectionEquality().equals(other.players, _players)&&(identical(other.you, you) || other.you == you)&&const DeepCollectionEquality().equals(other.submissions, _submissions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,protocolVersion,roomCode,mode,phase,serverTime,packTitle,questionIndex,questionCount,gameNumber,settings,question,deadline,pausedRemainingMs,const DeepCollectionEquality().hash(_acceptedAnswers),const DeepCollectionEquality().hash(_players),you,const DeepCollectionEquality().hash(_submissions));
}

@override
String toString() {
    return 'RoomState(protocolVersion: $protocolVersion, roomCode: $roomCode, mode: $mode, phase: $phase, serverTime: $serverTime, packTitle: $packTitle, questionIndex: $questionIndex, questionCount: $questionCount, gameNumber: $gameNumber, settings: $settings, question: $question, deadline: $deadline, pausedRemainingMs: $pausedRemainingMs, acceptedAnswers: $acceptedAnswers, players: $players, you: $you, submissions: $submissions)';
}


}

/// @nodoc
abstract mixin class _$RoomStateCopyWith<$Res> implements $RoomStateCopyWith<$Res> {
  factory _$RoomStateCopyWith(_RoomState value, $Res Function(_RoomState) _then) = __$RoomStateCopyWithImpl;
@override @useResult
$Res call({
 int protocolVersion, String roomCode, Mode mode, Phase phase, int serverTime, String? packTitle, int? questionIndex, int questionCount, int gameNumber, GameSettings? settings, Question? question, int? deadline, int? pausedRemainingMs, List<String>? acceptedAnswers, List<PlayerSummary> players, You you, List<SubmissionView>? submissions
});


@override $GameSettingsCopyWith<$Res>? get settings;@override $QuestionCopyWith<$Res>? get question;@override $YouCopyWith<$Res> get you;

}
/// @nodoc
class __$RoomStateCopyWithImpl<$Res>
    implements _$RoomStateCopyWith<$Res> {
  __$RoomStateCopyWithImpl(this._self, this._then);

  final _RoomState _self;
  final $Res Function(_RoomState) _then;

/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? protocolVersion = null,Object? roomCode = null,Object? mode = null,Object? phase = null,Object? serverTime = null,Object? packTitle = freezed,Object? questionIndex = freezed,Object? questionCount = null,Object? gameNumber = null,Object? settings = freezed,Object? question = freezed,Object? deadline = freezed,Object? pausedRemainingMs = freezed,Object? acceptedAnswers = freezed,Object? players = null,Object? you = null,Object? submissions = freezed,}) {
  return _then(_RoomState(
protocolVersion: null == protocolVersion ? _self.protocolVersion : protocolVersion // ignore: cast_nullable_to_non_nullable
as int,roomCode: null == roomCode ? _self.roomCode : roomCode // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as Mode,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as Phase,serverTime: null == serverTime ? _self.serverTime : serverTime // ignore: cast_nullable_to_non_nullable
as int,packTitle: freezed == packTitle ? _self.packTitle : packTitle // ignore: cast_nullable_to_non_nullable
as String?,questionIndex: freezed == questionIndex ? _self.questionIndex : questionIndex // ignore: cast_nullable_to_non_nullable
as int?,questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,gameNumber: null == gameNumber ? _self.gameNumber : gameNumber // ignore: cast_nullable_to_non_nullable
as int,settings: freezed == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as GameSettings?,question: freezed == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as Question?,deadline: freezed == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as int?,pausedRemainingMs: freezed == pausedRemainingMs ? _self.pausedRemainingMs : pausedRemainingMs // ignore: cast_nullable_to_non_nullable
as int?,acceptedAnswers: freezed == acceptedAnswers ? _self._acceptedAnswers : acceptedAnswers // ignore: cast_nullable_to_non_nullable
as List<String>?,players: null == players ? _self._players : players // ignore: cast_nullable_to_non_nullable
as List<PlayerSummary>,you: null == you ? _self.you : you // ignore: cast_nullable_to_non_nullable
as You,submissions: freezed == submissions ? _self._submissions : submissions // ignore: cast_nullable_to_non_nullable
as List<SubmissionView>?,
  ));
}

/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameSettingsCopyWith<$Res>? get settings {
    if (_self.settings == null) {
    return null;
  }

  return $GameSettingsCopyWith<$Res>(_self.settings!, (value) {
    return _then(_self.copyWith(settings: value));
  });
}/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuestionCopyWith<$Res>? get question {
    if (_self.question == null) {
    return null;
  }

  return $QuestionCopyWith<$Res>(_self.question!, (value) {
    return _then(_self.copyWith(question: value));
  });
}/// Create a copy of RoomState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$YouCopyWith<$Res> get you {
  
  return $YouCopyWith<$Res>(_self.you, (value) {
    return _then(_self.copyWith(you: value));
  });
}
}


/// @nodoc
mixin _$GameSettings {

 int get questionCount; int get timeLimitMs; int get maxQuestionCount;/// Harder questions score wager × 2 (medium) or × 3 (hard) (protocol v4).
 bool get difficultyMultiplier; int get minTimeLimitMs; int get maxTimeLimitMs;
/// Create a copy of GameSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameSettingsCopyWith<GameSettings> get copyWith => _$GameSettingsCopyWithImpl<GameSettings>(this as GameSettings, _$identity);

  /// Serializes this GameSettings to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as GameSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameSettings&&(identical(other.questionCount, _this.questionCount) || other.questionCount == _this.questionCount)&&(identical(other.timeLimitMs, _this.timeLimitMs) || other.timeLimitMs == _this.timeLimitMs)&&(identical(other.maxQuestionCount, _this.maxQuestionCount) || other.maxQuestionCount == _this.maxQuestionCount)&&(identical(other.difficultyMultiplier, _this.difficultyMultiplier) || other.difficultyMultiplier == _this.difficultyMultiplier)&&(identical(other.minTimeLimitMs, _this.minTimeLimitMs) || other.minTimeLimitMs == _this.minTimeLimitMs)&&(identical(other.maxTimeLimitMs, _this.maxTimeLimitMs) || other.maxTimeLimitMs == _this.maxTimeLimitMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as GameSettings;
  return Object.hash(runtimeType,_this.questionCount,_this.timeLimitMs,_this.maxQuestionCount,_this.difficultyMultiplier,_this.minTimeLimitMs,_this.maxTimeLimitMs);
}

@override
String toString() {
  final _this = this as GameSettings;
  return 'GameSettings(questionCount: ${_this.questionCount}, timeLimitMs: ${_this.timeLimitMs}, maxQuestionCount: ${_this.maxQuestionCount}, difficultyMultiplier: ${_this.difficultyMultiplier}, minTimeLimitMs: ${_this.minTimeLimitMs}, maxTimeLimitMs: ${_this.maxTimeLimitMs})';
}


}

/// @nodoc
abstract mixin class $GameSettingsCopyWith<$Res>  {
  factory $GameSettingsCopyWith(GameSettings value, $Res Function(GameSettings) _then) = _$GameSettingsCopyWithImpl;
@useResult
$Res call({
 int questionCount, int timeLimitMs, int maxQuestionCount, bool difficultyMultiplier, int minTimeLimitMs, int maxTimeLimitMs
});




}
/// @nodoc
class _$GameSettingsCopyWithImpl<$Res>
    implements $GameSettingsCopyWith<$Res> {
  _$GameSettingsCopyWithImpl(this._self, this._then);

  final GameSettings _self;
  final $Res Function(GameSettings) _then;

/// Create a copy of GameSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? questionCount = null,Object? timeLimitMs = null,Object? maxQuestionCount = null,Object? difficultyMultiplier = null,Object? minTimeLimitMs = null,Object? maxTimeLimitMs = null,}) {
  return _then(GameSettings(
questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,timeLimitMs: null == timeLimitMs ? _self.timeLimitMs : timeLimitMs // ignore: cast_nullable_to_non_nullable
as int,maxQuestionCount: null == maxQuestionCount ? _self.maxQuestionCount : maxQuestionCount // ignore: cast_nullable_to_non_nullable
as int,difficultyMultiplier: null == difficultyMultiplier ? _self.difficultyMultiplier : difficultyMultiplier // ignore: cast_nullable_to_non_nullable
as bool,minTimeLimitMs: null == minTimeLimitMs ? _self.minTimeLimitMs : minTimeLimitMs // ignore: cast_nullable_to_non_nullable
as int,maxTimeLimitMs: null == maxTimeLimitMs ? _self.maxTimeLimitMs : maxTimeLimitMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GameSettings].
extension GameSettingsPatterns on GameSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameSettings value)  $default,){
final _that = this;
switch (_that) {
case _GameSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameSettings value)?  $default,){
final _that = this;
switch (_that) {
case _GameSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int questionCount,  int timeLimitMs,  int maxQuestionCount,  bool difficultyMultiplier,  int minTimeLimitMs,  int maxTimeLimitMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameSettings() when $default != null:
return $default(_that.questionCount,_that.timeLimitMs,_that.maxQuestionCount,_that.difficultyMultiplier,_that.minTimeLimitMs,_that.maxTimeLimitMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int questionCount,  int timeLimitMs,  int maxQuestionCount,  bool difficultyMultiplier,  int minTimeLimitMs,  int maxTimeLimitMs)  $default,) {final _that = this;
switch (_that) {
case _GameSettings():
return $default(_that.questionCount,_that.timeLimitMs,_that.maxQuestionCount,_that.difficultyMultiplier,_that.minTimeLimitMs,_that.maxTimeLimitMs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int questionCount,  int timeLimitMs,  int maxQuestionCount,  bool difficultyMultiplier,  int minTimeLimitMs,  int maxTimeLimitMs)?  $default,) {final _that = this;
switch (_that) {
case _GameSettings() when $default != null:
return $default(_that.questionCount,_that.timeLimitMs,_that.maxQuestionCount,_that.difficultyMultiplier,_that.minTimeLimitMs,_that.maxTimeLimitMs);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GameSettings implements GameSettings {
  const _GameSettings({required this.questionCount, required this.timeLimitMs, required this.maxQuestionCount, this.difficultyMultiplier = false, this.minTimeLimitMs = 10000, this.maxTimeLimitMs = 120000});
  factory _GameSettings.fromJson(Map<String, dynamic> json) => _$GameSettingsFromJson(json);

@override final  int questionCount;
@override final  int timeLimitMs;
@override final  int maxQuestionCount;
/// Harder questions score wager × 2 (medium) or × 3 (hard) (protocol v4).
@override@JsonKey() final  bool difficultyMultiplier;
@override@JsonKey() final  int minTimeLimitMs;
@override@JsonKey() final  int maxTimeLimitMs;

/// Create a copy of GameSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameSettingsCopyWith<_GameSettings> get copyWith => __$GameSettingsCopyWithImpl<_GameSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GameSettingsToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameSettings&&(identical(other.questionCount, questionCount) || other.questionCount == questionCount)&&(identical(other.timeLimitMs, timeLimitMs) || other.timeLimitMs == timeLimitMs)&&(identical(other.maxQuestionCount, maxQuestionCount) || other.maxQuestionCount == maxQuestionCount)&&(identical(other.difficultyMultiplier, difficultyMultiplier) || other.difficultyMultiplier == difficultyMultiplier)&&(identical(other.minTimeLimitMs, minTimeLimitMs) || other.minTimeLimitMs == minTimeLimitMs)&&(identical(other.maxTimeLimitMs, maxTimeLimitMs) || other.maxTimeLimitMs == maxTimeLimitMs));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,questionCount,timeLimitMs,maxQuestionCount,difficultyMultiplier,minTimeLimitMs,maxTimeLimitMs);
}

@override
String toString() {
    return 'GameSettings(questionCount: $questionCount, timeLimitMs: $timeLimitMs, maxQuestionCount: $maxQuestionCount, difficultyMultiplier: $difficultyMultiplier, minTimeLimitMs: $minTimeLimitMs, maxTimeLimitMs: $maxTimeLimitMs)';
}


}

/// @nodoc
abstract mixin class _$GameSettingsCopyWith<$Res> implements $GameSettingsCopyWith<$Res> {
  factory _$GameSettingsCopyWith(_GameSettings value, $Res Function(_GameSettings) _then) = __$GameSettingsCopyWithImpl;
@override @useResult
$Res call({
 int questionCount, int timeLimitMs, int maxQuestionCount, bool difficultyMultiplier, int minTimeLimitMs, int maxTimeLimitMs
});




}
/// @nodoc
class __$GameSettingsCopyWithImpl<$Res>
    implements _$GameSettingsCopyWith<$Res> {
  __$GameSettingsCopyWithImpl(this._self, this._then);

  final _GameSettings _self;
  final $Res Function(_GameSettings) _then;

/// Create a copy of GameSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? questionCount = null,Object? timeLimitMs = null,Object? maxQuestionCount = null,Object? difficultyMultiplier = null,Object? minTimeLimitMs = null,Object? maxTimeLimitMs = null,}) {
  return _then(_GameSettings(
questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,timeLimitMs: null == timeLimitMs ? _self.timeLimitMs : timeLimitMs // ignore: cast_nullable_to_non_nullable
as int,maxQuestionCount: null == maxQuestionCount ? _self.maxQuestionCount : maxQuestionCount // ignore: cast_nullable_to_non_nullable
as int,difficultyMultiplier: null == difficultyMultiplier ? _self.difficultyMultiplier : difficultyMultiplier // ignore: cast_nullable_to_non_nullable
as bool,minTimeLimitMs: null == minTimeLimitMs ? _self.minTimeLimitMs : minTimeLimitMs // ignore: cast_nullable_to_non_nullable
as int,maxTimeLimitMs: null == maxTimeLimitMs ? _self.maxTimeLimitMs : maxTimeLimitMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$Question {

 String get id; QuestionType get type; String get prompt; String? get imageUrl; int get timeLimitMs;/// "easy" | "medium" | "hard" (protocol v4).
 String get difficulty;/// Points multiplier: 1 unless the difficulty bonus is on (§9).
 int get multiplier;
/// Create a copy of Question
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionCopyWith<Question> get copyWith => _$QuestionCopyWithImpl<Question>(this as Question, _$identity);

  /// Serializes this Question to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Question;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Question&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.prompt, _this.prompt) || other.prompt == _this.prompt)&&(identical(other.imageUrl, _this.imageUrl) || other.imageUrl == _this.imageUrl)&&(identical(other.timeLimitMs, _this.timeLimitMs) || other.timeLimitMs == _this.timeLimitMs)&&(identical(other.difficulty, _this.difficulty) || other.difficulty == _this.difficulty)&&(identical(other.multiplier, _this.multiplier) || other.multiplier == _this.multiplier));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Question;
  return Object.hash(runtimeType,_this.id,_this.type,_this.prompt,_this.imageUrl,_this.timeLimitMs,_this.difficulty,_this.multiplier);
}

@override
String toString() {
  final _this = this as Question;
  return 'Question(id: ${_this.id}, type: ${_this.type}, prompt: ${_this.prompt}, imageUrl: ${_this.imageUrl}, timeLimitMs: ${_this.timeLimitMs}, difficulty: ${_this.difficulty}, multiplier: ${_this.multiplier})';
}


}

/// @nodoc
abstract mixin class $QuestionCopyWith<$Res>  {
  factory $QuestionCopyWith(Question value, $Res Function(Question) _then) = _$QuestionCopyWithImpl;
@useResult
$Res call({
 String id, QuestionType type, String prompt, String? imageUrl, int timeLimitMs, String difficulty, int multiplier
});




}
/// @nodoc
class _$QuestionCopyWithImpl<$Res>
    implements $QuestionCopyWith<$Res> {
  _$QuestionCopyWithImpl(this._self, this._then);

  final Question _self;
  final $Res Function(Question) _then;

/// Create a copy of Question
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? prompt = null,Object? imageUrl = freezed,Object? timeLimitMs = null,Object? difficulty = null,Object? multiplier = null,}) {
  return _then(Question(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as QuestionType,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,imageUrl: freezed == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String?,timeLimitMs: null == timeLimitMs ? _self.timeLimitMs : timeLimitMs // ignore: cast_nullable_to_non_nullable
as int,difficulty: null == difficulty ? _self.difficulty : difficulty // ignore: cast_nullable_to_non_nullable
as String,multiplier: null == multiplier ? _self.multiplier : multiplier // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Question].
extension QuestionPatterns on Question {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Question value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Question() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Question value)  $default,){
final _that = this;
switch (_that) {
case _Question():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Question value)?  $default,){
final _that = this;
switch (_that) {
case _Question() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  QuestionType type,  String prompt,  String? imageUrl,  int timeLimitMs,  String difficulty,  int multiplier)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Question() when $default != null:
return $default(_that.id,_that.type,_that.prompt,_that.imageUrl,_that.timeLimitMs,_that.difficulty,_that.multiplier);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  QuestionType type,  String prompt,  String? imageUrl,  int timeLimitMs,  String difficulty,  int multiplier)  $default,) {final _that = this;
switch (_that) {
case _Question():
return $default(_that.id,_that.type,_that.prompt,_that.imageUrl,_that.timeLimitMs,_that.difficulty,_that.multiplier);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  QuestionType type,  String prompt,  String? imageUrl,  int timeLimitMs,  String difficulty,  int multiplier)?  $default,) {final _that = this;
switch (_that) {
case _Question() when $default != null:
return $default(_that.id,_that.type,_that.prompt,_that.imageUrl,_that.timeLimitMs,_that.difficulty,_that.multiplier);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Question implements Question {
  const _Question({required this.id, required this.type, required this.prompt, this.imageUrl, required this.timeLimitMs, this.difficulty = 'easy', this.multiplier = 1});
  factory _Question.fromJson(Map<String, dynamic> json) => _$QuestionFromJson(json);

@override final  String id;
@override final  QuestionType type;
@override final  String prompt;
@override final  String? imageUrl;
@override final  int timeLimitMs;
/// "easy" | "medium" | "hard" (protocol v4).
@override@JsonKey() final  String difficulty;
/// Points multiplier: 1 unless the difficulty bonus is on (§9).
@override@JsonKey() final  int multiplier;

/// Create a copy of Question
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuestionCopyWith<_Question> get copyWith => __$QuestionCopyWithImpl<_Question>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QuestionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Question&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.prompt, prompt) || other.prompt == prompt)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.timeLimitMs, timeLimitMs) || other.timeLimitMs == timeLimitMs)&&(identical(other.difficulty, difficulty) || other.difficulty == difficulty)&&(identical(other.multiplier, multiplier) || other.multiplier == multiplier));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,type,prompt,imageUrl,timeLimitMs,difficulty,multiplier);
}

@override
String toString() {
    return 'Question(id: $id, type: $type, prompt: $prompt, imageUrl: $imageUrl, timeLimitMs: $timeLimitMs, difficulty: $difficulty, multiplier: $multiplier)';
}


}

/// @nodoc
abstract mixin class _$QuestionCopyWith<$Res> implements $QuestionCopyWith<$Res> {
  factory _$QuestionCopyWith(_Question value, $Res Function(_Question) _then) = __$QuestionCopyWithImpl;
@override @useResult
$Res call({
 String id, QuestionType type, String prompt, String? imageUrl, int timeLimitMs, String difficulty, int multiplier
});




}
/// @nodoc
class __$QuestionCopyWithImpl<$Res>
    implements _$QuestionCopyWith<$Res> {
  __$QuestionCopyWithImpl(this._self, this._then);

  final _Question _self;
  final $Res Function(_Question) _then;

/// Create a copy of Question
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? prompt = null,Object? imageUrl = freezed,Object? timeLimitMs = null,Object? difficulty = null,Object? multiplier = null,}) {
  return _then(_Question(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as QuestionType,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as String,imageUrl: freezed == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String?,timeLimitMs: null == timeLimitMs ? _self.timeLimitMs : timeLimitMs // ignore: cast_nullable_to_non_nullable
as int,difficulty: null == difficulty ? _self.difficulty : difficulty // ignore: cast_nullable_to_non_nullable
as String,multiplier: null == multiplier ? _self.multiplier : multiplier // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$PlayerSummary {

 String get id; String get name; int get score; bool get connected; bool get hasSubmitted;/// True for the playing host (protocol v2).
 bool get isHost;/// 0–359, assigned at random by the server (protocol v4). Every client
/// renders the same colour from it.
 int? get avatarHue;
/// Create a copy of PlayerSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerSummaryCopyWith<PlayerSummary> get copyWith => _$PlayerSummaryCopyWithImpl<PlayerSummary>(this as PlayerSummary, _$identity);

  /// Serializes this PlayerSummary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PlayerSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerSummary&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.score, _this.score) || other.score == _this.score)&&(identical(other.connected, _this.connected) || other.connected == _this.connected)&&(identical(other.hasSubmitted, _this.hasSubmitted) || other.hasSubmitted == _this.hasSubmitted)&&(identical(other.isHost, _this.isHost) || other.isHost == _this.isHost)&&(identical(other.avatarHue, _this.avatarHue) || other.avatarHue == _this.avatarHue));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PlayerSummary;
  return Object.hash(runtimeType,_this.id,_this.name,_this.score,_this.connected,_this.hasSubmitted,_this.isHost,_this.avatarHue);
}

@override
String toString() {
  final _this = this as PlayerSummary;
  return 'PlayerSummary(id: ${_this.id}, name: ${_this.name}, score: ${_this.score}, connected: ${_this.connected}, hasSubmitted: ${_this.hasSubmitted}, isHost: ${_this.isHost}, avatarHue: ${_this.avatarHue})';
}


}

/// @nodoc
abstract mixin class $PlayerSummaryCopyWith<$Res>  {
  factory $PlayerSummaryCopyWith(PlayerSummary value, $Res Function(PlayerSummary) _then) = _$PlayerSummaryCopyWithImpl;
@useResult
$Res call({
 String id, String name, int score, bool connected, bool hasSubmitted, bool isHost, int? avatarHue
});




}
/// @nodoc
class _$PlayerSummaryCopyWithImpl<$Res>
    implements $PlayerSummaryCopyWith<$Res> {
  _$PlayerSummaryCopyWithImpl(this._self, this._then);

  final PlayerSummary _self;
  final $Res Function(PlayerSummary) _then;

/// Create a copy of PlayerSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? score = null,Object? connected = null,Object? hasSubmitted = null,Object? isHost = null,Object? avatarHue = freezed,}) {
  return _then(PlayerSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as int,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,hasSubmitted: null == hasSubmitted ? _self.hasSubmitted : hasSubmitted // ignore: cast_nullable_to_non_nullable
as bool,isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,avatarHue: freezed == avatarHue ? _self.avatarHue : avatarHue // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PlayerSummary].
extension PlayerSummaryPatterns on PlayerSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlayerSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlayerSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlayerSummary value)  $default,){
final _that = this;
switch (_that) {
case _PlayerSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlayerSummary value)?  $default,){
final _that = this;
switch (_that) {
case _PlayerSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  int score,  bool connected,  bool hasSubmitted,  bool isHost,  int? avatarHue)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlayerSummary() when $default != null:
return $default(_that.id,_that.name,_that.score,_that.connected,_that.hasSubmitted,_that.isHost,_that.avatarHue);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  int score,  bool connected,  bool hasSubmitted,  bool isHost,  int? avatarHue)  $default,) {final _that = this;
switch (_that) {
case _PlayerSummary():
return $default(_that.id,_that.name,_that.score,_that.connected,_that.hasSubmitted,_that.isHost,_that.avatarHue);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  int score,  bool connected,  bool hasSubmitted,  bool isHost,  int? avatarHue)?  $default,) {final _that = this;
switch (_that) {
case _PlayerSummary() when $default != null:
return $default(_that.id,_that.name,_that.score,_that.connected,_that.hasSubmitted,_that.isHost,_that.avatarHue);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PlayerSummary implements PlayerSummary {
  const _PlayerSummary({required this.id, required this.name, required this.score, required this.connected, required this.hasSubmitted, this.isHost = false, this.avatarHue});
  factory _PlayerSummary.fromJson(Map<String, dynamic> json) => _$PlayerSummaryFromJson(json);

@override final  String id;
@override final  String name;
@override final  int score;
@override final  bool connected;
@override final  bool hasSubmitted;
/// True for the playing host (protocol v2).
@override@JsonKey() final  bool isHost;
/// 0–359, assigned at random by the server (protocol v4). Every client
/// renders the same colour from it.
@override final  int? avatarHue;

/// Create a copy of PlayerSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlayerSummaryCopyWith<_PlayerSummary> get copyWith => __$PlayerSummaryCopyWithImpl<_PlayerSummary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlayerSummaryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlayerSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.score, score) || other.score == score)&&(identical(other.connected, connected) || other.connected == connected)&&(identical(other.hasSubmitted, hasSubmitted) || other.hasSubmitted == hasSubmitted)&&(identical(other.isHost, isHost) || other.isHost == isHost)&&(identical(other.avatarHue, avatarHue) || other.avatarHue == avatarHue));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,score,connected,hasSubmitted,isHost,avatarHue);
}

@override
String toString() {
    return 'PlayerSummary(id: $id, name: $name, score: $score, connected: $connected, hasSubmitted: $hasSubmitted, isHost: $isHost, avatarHue: $avatarHue)';
}


}

/// @nodoc
abstract mixin class _$PlayerSummaryCopyWith<$Res> implements $PlayerSummaryCopyWith<$Res> {
  factory _$PlayerSummaryCopyWith(_PlayerSummary value, $Res Function(_PlayerSummary) _then) = __$PlayerSummaryCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, int score, bool connected, bool hasSubmitted, bool isHost, int? avatarHue
});




}
/// @nodoc
class __$PlayerSummaryCopyWithImpl<$Res>
    implements _$PlayerSummaryCopyWith<$Res> {
  __$PlayerSummaryCopyWithImpl(this._self, this._then);

  final _PlayerSummary _self;
  final $Res Function(_PlayerSummary) _then;

/// Create a copy of PlayerSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? score = null,Object? connected = null,Object? hasSubmitted = null,Object? isHost = null,Object? avatarHue = freezed,}) {
  return _then(_PlayerSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as int,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,hasSubmitted: null == hasSubmitted ? _self.hasSubmitted : hasSubmitted // ignore: cast_nullable_to_non_nullable
as bool,isHost: null == isHost ? _self.isHost : isHost // ignore: cast_nullable_to_non_nullable
as bool,avatarHue: freezed == avatarHue ? _self.avatarHue : avatarHue // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$You {

 Role get role; String? get playerId; OwnSubmission? get submission;
/// Create a copy of You
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$YouCopyWith<You> get copyWith => _$YouCopyWithImpl<You>(this as You, _$identity);

  /// Serializes this You to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as You;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is You&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.playerId, _this.playerId) || other.playerId == _this.playerId)&&(identical(other.submission, _this.submission) || other.submission == _this.submission));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as You;
  return Object.hash(runtimeType,_this.role,_this.playerId,_this.submission);
}

@override
String toString() {
  final _this = this as You;
  return 'You(role: ${_this.role}, playerId: ${_this.playerId}, submission: ${_this.submission})';
}


}

/// @nodoc
abstract mixin class $YouCopyWith<$Res>  {
  factory $YouCopyWith(You value, $Res Function(You) _then) = _$YouCopyWithImpl;
@useResult
$Res call({
 Role role, String? playerId, OwnSubmission? submission
});


$OwnSubmissionCopyWith<$Res>? get submission;

}
/// @nodoc
class _$YouCopyWithImpl<$Res>
    implements $YouCopyWith<$Res> {
  _$YouCopyWithImpl(this._self, this._then);

  final You _self;
  final $Res Function(You) _then;

/// Create a copy of You
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? role = null,Object? playerId = freezed,Object? submission = freezed,}) {
  return _then(You(
role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as Role,playerId: freezed == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as String?,submission: freezed == submission ? _self.submission : submission // ignore: cast_nullable_to_non_nullable
as OwnSubmission?,
  ));
}
/// Create a copy of You
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OwnSubmissionCopyWith<$Res>? get submission {
    if (_self.submission == null) {
    return null;
  }

  return $OwnSubmissionCopyWith<$Res>(_self.submission!, (value) {
    return _then(_self.copyWith(submission: value));
  });
}
}


/// Adds pattern-matching-related methods to [You].
extension YouPatterns on You {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _You value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _You() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _You value)  $default,){
final _that = this;
switch (_that) {
case _You():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _You value)?  $default,){
final _that = this;
switch (_that) {
case _You() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Role role,  String? playerId,  OwnSubmission? submission)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _You() when $default != null:
return $default(_that.role,_that.playerId,_that.submission);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Role role,  String? playerId,  OwnSubmission? submission)  $default,) {final _that = this;
switch (_that) {
case _You():
return $default(_that.role,_that.playerId,_that.submission);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Role role,  String? playerId,  OwnSubmission? submission)?  $default,) {final _that = this;
switch (_that) {
case _You() when $default != null:
return $default(_that.role,_that.playerId,_that.submission);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _You implements You {
  const _You({required this.role, this.playerId, this.submission});
  factory _You.fromJson(Map<String, dynamic> json) => _$YouFromJson(json);

@override final  Role role;
@override final  String? playerId;
@override final  OwnSubmission? submission;

/// Create a copy of You
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$YouCopyWith<_You> get copyWith => __$YouCopyWithImpl<_You>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$YouToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _You&&(identical(other.role, role) || other.role == role)&&(identical(other.playerId, playerId) || other.playerId == playerId)&&(identical(other.submission, submission) || other.submission == submission));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,role,playerId,submission);
}

@override
String toString() {
    return 'You(role: $role, playerId: $playerId, submission: $submission)';
}


}

/// @nodoc
abstract mixin class _$YouCopyWith<$Res> implements $YouCopyWith<$Res> {
  factory _$YouCopyWith(_You value, $Res Function(_You) _then) = __$YouCopyWithImpl;
@override @useResult
$Res call({
 Role role, String? playerId, OwnSubmission? submission
});


@override $OwnSubmissionCopyWith<$Res>? get submission;

}
/// @nodoc
class __$YouCopyWithImpl<$Res>
    implements _$YouCopyWith<$Res> {
  __$YouCopyWithImpl(this._self, this._then);

  final _You _self;
  final $Res Function(_You) _then;

/// Create a copy of You
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? role = null,Object? playerId = freezed,Object? submission = freezed,}) {
  return _then(_You(
role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as Role,playerId: freezed == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as String?,submission: freezed == submission ? _self.submission : submission // ignore: cast_nullable_to_non_nullable
as OwnSubmission?,
  ));
}

/// Create a copy of You
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OwnSubmissionCopyWith<$Res>? get submission {
    if (_self.submission == null) {
    return null;
  }

  return $OwnSubmissionCopyWith<$Res>(_self.submission!, (value) {
    return _then(_self.copyWith(submission: value));
  });
}
}


/// @nodoc
mixin _$OwnSubmission {

 String get answer; int get wager; bool? get correct; int? get delta;
/// Create a copy of OwnSubmission
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OwnSubmissionCopyWith<OwnSubmission> get copyWith => _$OwnSubmissionCopyWithImpl<OwnSubmission>(this as OwnSubmission, _$identity);

  /// Serializes this OwnSubmission to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as OwnSubmission;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OwnSubmission&&(identical(other.answer, _this.answer) || other.answer == _this.answer)&&(identical(other.wager, _this.wager) || other.wager == _this.wager)&&(identical(other.correct, _this.correct) || other.correct == _this.correct)&&(identical(other.delta, _this.delta) || other.delta == _this.delta));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as OwnSubmission;
  return Object.hash(runtimeType,_this.answer,_this.wager,_this.correct,_this.delta);
}

@override
String toString() {
  final _this = this as OwnSubmission;
  return 'OwnSubmission(answer: ${_this.answer}, wager: ${_this.wager}, correct: ${_this.correct}, delta: ${_this.delta})';
}


}

/// @nodoc
abstract mixin class $OwnSubmissionCopyWith<$Res>  {
  factory $OwnSubmissionCopyWith(OwnSubmission value, $Res Function(OwnSubmission) _then) = _$OwnSubmissionCopyWithImpl;
@useResult
$Res call({
 String answer, int wager, bool? correct, int? delta
});




}
/// @nodoc
class _$OwnSubmissionCopyWithImpl<$Res>
    implements $OwnSubmissionCopyWith<$Res> {
  _$OwnSubmissionCopyWithImpl(this._self, this._then);

  final OwnSubmission _self;
  final $Res Function(OwnSubmission) _then;

/// Create a copy of OwnSubmission
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? answer = null,Object? wager = null,Object? correct = freezed,Object? delta = freezed,}) {
  return _then(OwnSubmission(
answer: null == answer ? _self.answer : answer // ignore: cast_nullable_to_non_nullable
as String,wager: null == wager ? _self.wager : wager // ignore: cast_nullable_to_non_nullable
as int,correct: freezed == correct ? _self.correct : correct // ignore: cast_nullable_to_non_nullable
as bool?,delta: freezed == delta ? _self.delta : delta // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [OwnSubmission].
extension OwnSubmissionPatterns on OwnSubmission {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OwnSubmission value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OwnSubmission() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OwnSubmission value)  $default,){
final _that = this;
switch (_that) {
case _OwnSubmission():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OwnSubmission value)?  $default,){
final _that = this;
switch (_that) {
case _OwnSubmission() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String answer,  int wager,  bool? correct,  int? delta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OwnSubmission() when $default != null:
return $default(_that.answer,_that.wager,_that.correct,_that.delta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String answer,  int wager,  bool? correct,  int? delta)  $default,) {final _that = this;
switch (_that) {
case _OwnSubmission():
return $default(_that.answer,_that.wager,_that.correct,_that.delta);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String answer,  int wager,  bool? correct,  int? delta)?  $default,) {final _that = this;
switch (_that) {
case _OwnSubmission() when $default != null:
return $default(_that.answer,_that.wager,_that.correct,_that.delta);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _OwnSubmission implements OwnSubmission {
  const _OwnSubmission({required this.answer, required this.wager, this.correct, this.delta});
  factory _OwnSubmission.fromJson(Map<String, dynamic> json) => _$OwnSubmissionFromJson(json);

@override final  String answer;
@override final  int wager;
@override final  bool? correct;
@override final  int? delta;

/// Create a copy of OwnSubmission
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OwnSubmissionCopyWith<_OwnSubmission> get copyWith => __$OwnSubmissionCopyWithImpl<_OwnSubmission>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OwnSubmissionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _OwnSubmission&&(identical(other.answer, answer) || other.answer == answer)&&(identical(other.wager, wager) || other.wager == wager)&&(identical(other.correct, correct) || other.correct == correct)&&(identical(other.delta, delta) || other.delta == delta));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,answer,wager,correct,delta);
}

@override
String toString() {
    return 'OwnSubmission(answer: $answer, wager: $wager, correct: $correct, delta: $delta)';
}


}

/// @nodoc
abstract mixin class _$OwnSubmissionCopyWith<$Res> implements $OwnSubmissionCopyWith<$Res> {
  factory _$OwnSubmissionCopyWith(_OwnSubmission value, $Res Function(_OwnSubmission) _then) = __$OwnSubmissionCopyWithImpl;
@override @useResult
$Res call({
 String answer, int wager, bool? correct, int? delta
});




}
/// @nodoc
class __$OwnSubmissionCopyWithImpl<$Res>
    implements _$OwnSubmissionCopyWith<$Res> {
  __$OwnSubmissionCopyWithImpl(this._self, this._then);

  final _OwnSubmission _self;
  final $Res Function(_OwnSubmission) _then;

/// Create a copy of OwnSubmission
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? answer = null,Object? wager = null,Object? correct = freezed,Object? delta = freezed,}) {
  return _then(_OwnSubmission(
answer: null == answer ? _self.answer : answer // ignore: cast_nullable_to_non_nullable
as String,wager: null == wager ? _self.wager : wager // ignore: cast_nullable_to_non_nullable
as int,correct: freezed == correct ? _self.correct : correct // ignore: cast_nullable_to_non_nullable
as bool?,delta: freezed == delta ? _self.delta : delta // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$SubmissionView {

 String get playerId; String get answer; int get wager; bool? get autoCorrect;/// Wire key `override` (renamed in Dart: a field named `override` shadows
/// the `@override` annotation in generated code).
@JsonKey(name: 'override') bool? get overrideVerdict; bool? get correct; int get multiplier; int? get delta;
/// Create a copy of SubmissionView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubmissionViewCopyWith<SubmissionView> get copyWith => _$SubmissionViewCopyWithImpl<SubmissionView>(this as SubmissionView, _$identity);

  /// Serializes this SubmissionView to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SubmissionView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubmissionView&&(identical(other.playerId, _this.playerId) || other.playerId == _this.playerId)&&(identical(other.answer, _this.answer) || other.answer == _this.answer)&&(identical(other.wager, _this.wager) || other.wager == _this.wager)&&(identical(other.autoCorrect, _this.autoCorrect) || other.autoCorrect == _this.autoCorrect)&&(identical(other.overrideVerdict, _this.overrideVerdict) || other.overrideVerdict == _this.overrideVerdict)&&(identical(other.correct, _this.correct) || other.correct == _this.correct)&&(identical(other.multiplier, _this.multiplier) || other.multiplier == _this.multiplier)&&(identical(other.delta, _this.delta) || other.delta == _this.delta));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SubmissionView;
  return Object.hash(runtimeType,_this.playerId,_this.answer,_this.wager,_this.autoCorrect,_this.overrideVerdict,_this.correct,_this.multiplier,_this.delta);
}

@override
String toString() {
  final _this = this as SubmissionView;
  return 'SubmissionView(playerId: ${_this.playerId}, answer: ${_this.answer}, wager: ${_this.wager}, autoCorrect: ${_this.autoCorrect}, overrideVerdict: ${_this.overrideVerdict}, correct: ${_this.correct}, multiplier: ${_this.multiplier}, delta: ${_this.delta})';
}


}

/// @nodoc
abstract mixin class $SubmissionViewCopyWith<$Res>  {
  factory $SubmissionViewCopyWith(SubmissionView value, $Res Function(SubmissionView) _then) = _$SubmissionViewCopyWithImpl;
@useResult
$Res call({
 String playerId, String answer, int wager, bool? autoCorrect,@JsonKey(name: 'override') bool? overrideVerdict, bool? correct, int multiplier, int? delta
});




}
/// @nodoc
class _$SubmissionViewCopyWithImpl<$Res>
    implements $SubmissionViewCopyWith<$Res> {
  _$SubmissionViewCopyWithImpl(this._self, this._then);

  final SubmissionView _self;
  final $Res Function(SubmissionView) _then;

/// Create a copy of SubmissionView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? playerId = null,Object? answer = null,Object? wager = null,Object? autoCorrect = freezed,Object? overrideVerdict = freezed,Object? correct = freezed,Object? multiplier = null,Object? delta = freezed,}) {
  return _then(SubmissionView(
playerId: null == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as String,answer: null == answer ? _self.answer : answer // ignore: cast_nullable_to_non_nullable
as String,wager: null == wager ? _self.wager : wager // ignore: cast_nullable_to_non_nullable
as int,autoCorrect: freezed == autoCorrect ? _self.autoCorrect : autoCorrect // ignore: cast_nullable_to_non_nullable
as bool?,overrideVerdict: freezed == overrideVerdict ? _self.overrideVerdict : overrideVerdict // ignore: cast_nullable_to_non_nullable
as bool?,correct: freezed == correct ? _self.correct : correct // ignore: cast_nullable_to_non_nullable
as bool?,multiplier: null == multiplier ? _self.multiplier : multiplier // ignore: cast_nullable_to_non_nullable
as int,delta: freezed == delta ? _self.delta : delta // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [SubmissionView].
extension SubmissionViewPatterns on SubmissionView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubmissionView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubmissionView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubmissionView value)  $default,){
final _that = this;
switch (_that) {
case _SubmissionView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubmissionView value)?  $default,){
final _that = this;
switch (_that) {
case _SubmissionView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String playerId,  String answer,  int wager,  bool? autoCorrect, @JsonKey(name: 'override')  bool? overrideVerdict,  bool? correct,  int multiplier,  int? delta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubmissionView() when $default != null:
return $default(_that.playerId,_that.answer,_that.wager,_that.autoCorrect,_that.overrideVerdict,_that.correct,_that.multiplier,_that.delta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String playerId,  String answer,  int wager,  bool? autoCorrect, @JsonKey(name: 'override')  bool? overrideVerdict,  bool? correct,  int multiplier,  int? delta)  $default,) {final _that = this;
switch (_that) {
case _SubmissionView():
return $default(_that.playerId,_that.answer,_that.wager,_that.autoCorrect,_that.overrideVerdict,_that.correct,_that.multiplier,_that.delta);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String playerId,  String answer,  int wager,  bool? autoCorrect, @JsonKey(name: 'override')  bool? overrideVerdict,  bool? correct,  int multiplier,  int? delta)?  $default,) {final _that = this;
switch (_that) {
case _SubmissionView() when $default != null:
return $default(_that.playerId,_that.answer,_that.wager,_that.autoCorrect,_that.overrideVerdict,_that.correct,_that.multiplier,_that.delta);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SubmissionView implements SubmissionView {
  const _SubmissionView({required this.playerId, required this.answer, required this.wager, this.autoCorrect, @JsonKey(name: 'override') this.overrideVerdict, this.correct, this.multiplier = 1, this.delta});
  factory _SubmissionView.fromJson(Map<String, dynamic> json) => _$SubmissionViewFromJson(json);

@override final  String playerId;
@override final  String answer;
@override final  int wager;
@override final  bool? autoCorrect;
/// Wire key `override` (renamed in Dart: a field named `override` shadows
/// the `@override` annotation in generated code).
@override@JsonKey(name: 'override') final  bool? overrideVerdict;
@override final  bool? correct;
@override@JsonKey() final  int multiplier;
@override final  int? delta;

/// Create a copy of SubmissionView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubmissionViewCopyWith<_SubmissionView> get copyWith => __$SubmissionViewCopyWithImpl<_SubmissionView>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SubmissionViewToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubmissionView&&(identical(other.playerId, playerId) || other.playerId == playerId)&&(identical(other.answer, answer) || other.answer == answer)&&(identical(other.wager, wager) || other.wager == wager)&&(identical(other.autoCorrect, autoCorrect) || other.autoCorrect == autoCorrect)&&(identical(other.overrideVerdict, overrideVerdict) || other.overrideVerdict == overrideVerdict)&&(identical(other.correct, correct) || other.correct == correct)&&(identical(other.multiplier, multiplier) || other.multiplier == multiplier)&&(identical(other.delta, delta) || other.delta == delta));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,playerId,answer,wager,autoCorrect,overrideVerdict,correct,multiplier,delta);
}

@override
String toString() {
    return 'SubmissionView(playerId: $playerId, answer: $answer, wager: $wager, autoCorrect: $autoCorrect, overrideVerdict: $overrideVerdict, correct: $correct, multiplier: $multiplier, delta: $delta)';
}


}

/// @nodoc
abstract mixin class _$SubmissionViewCopyWith<$Res> implements $SubmissionViewCopyWith<$Res> {
  factory _$SubmissionViewCopyWith(_SubmissionView value, $Res Function(_SubmissionView) _then) = __$SubmissionViewCopyWithImpl;
@override @useResult
$Res call({
 String playerId, String answer, int wager, bool? autoCorrect,@JsonKey(name: 'override') bool? overrideVerdict, bool? correct, int multiplier, int? delta
});




}
/// @nodoc
class __$SubmissionViewCopyWithImpl<$Res>
    implements _$SubmissionViewCopyWith<$Res> {
  __$SubmissionViewCopyWithImpl(this._self, this._then);

  final _SubmissionView _self;
  final $Res Function(_SubmissionView) _then;

/// Create a copy of SubmissionView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? playerId = null,Object? answer = null,Object? wager = null,Object? autoCorrect = freezed,Object? overrideVerdict = freezed,Object? correct = freezed,Object? multiplier = null,Object? delta = freezed,}) {
  return _then(_SubmissionView(
playerId: null == playerId ? _self.playerId : playerId // ignore: cast_nullable_to_non_nullable
as String,answer: null == answer ? _self.answer : answer // ignore: cast_nullable_to_non_nullable
as String,wager: null == wager ? _self.wager : wager // ignore: cast_nullable_to_non_nullable
as int,autoCorrect: freezed == autoCorrect ? _self.autoCorrect : autoCorrect // ignore: cast_nullable_to_non_nullable
as bool?,overrideVerdict: freezed == overrideVerdict ? _self.overrideVerdict : overrideVerdict // ignore: cast_nullable_to_non_nullable
as bool?,correct: freezed == correct ? _self.correct : correct // ignore: cast_nullable_to_non_nullable
as bool?,multiplier: null == multiplier ? _self.multiplier : multiplier // ignore: cast_nullable_to_non_nullable
as int,delta: freezed == delta ? _self.delta : delta // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
