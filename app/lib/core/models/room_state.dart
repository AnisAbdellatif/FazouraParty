import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'room_state.freezed.dart';
part 'room_state.g.dart';

/// Complete, per-recipient room snapshot pushed as the `state` event
/// (PROTOCOL.md §5.1). Never a delta.
@freezed
abstract class RoomState with _$RoomState {
  const factory RoomState({
    required int protocolVersion,
    required String roomCode,
    required Mode mode,
    required Phase phase,

    /// Host clock (ms since epoch) when the snapshot was built.
    required int serverTime,
    String? packTitle,
    int? questionIndex,
    required int questionCount,

    /// 1 for the first game in the room, +1 per rematch (protocol v3).
    @Default(1) int gameNumber,
    GameSettings? settings,
    Question? question,

    /// Absolute server timestamp (ms since epoch); set only in `question`
    /// while not paused.
    int? deadline,
    int? pausedRemainingMs,
    List<String>? acceptedAnswers,
    @Default(<PlayerSummary>[]) List<PlayerSummary> players,
    required You you,
    List<SubmissionView>? submissions,
  }) = _RoomState;

  factory RoomState.fromJson(Map<String, dynamic> json) =>
      _$RoomStateFromJson(json);
}

/// Host-chosen game settings and their bounds (PROTOCOL.md §6.2).
@freezed
abstract class GameSettings with _$GameSettings {
  const factory GameSettings({
    required int questionCount,
    required int timeLimitMs,
    required int maxQuestionCount,

    /// Harder questions score wager × 2 (medium) or × 3 (hard) (protocol v4).
    @Default(false) bool difficultyMultiplier,
    @Default(<String>['easy', 'medium', 'hard']) List<String> difficulties,
    @Default(<String>['easy', 'medium', 'hard'])
    List<String> availableDifficulties,
    @Default(10000) int minTimeLimitMs,
    @Default(120000) int maxTimeLimitMs,
  }) = _GameSettings;

  factory GameSettings.fromJson(Map<String, dynamic> json) =>
      _$GameSettingsFromJson(json);
}

@freezed
abstract class Question with _$Question {
  const factory Question({
    required String id,
    required QuestionType type,
    required String prompt,
    String? imageUrl,
    required int timeLimitMs,

    /// "easy" | "medium" | "hard" (protocol v4).
    @Default('easy') String difficulty,

    /// Points multiplier: 1 unless the difficulty bonus is on (§9).
    @Default(1) int multiplier,
  }) = _Question;

  factory Question.fromJson(Map<String, dynamic> json) =>
      _$QuestionFromJson(json);
}

@freezed
abstract class PlayerSummary with _$PlayerSummary {
  const factory PlayerSummary({
    required String id,
    required String name,
    required int score,
    required bool connected,
    required bool hasSubmitted,

    /// True for the playing host (protocol v2).
    @Default(false) bool isHost,

    /// 0–359, assigned at random by the server (protocol v4). Every client
    /// renders the same colour from it.
    int? avatarHue,
  }) = _PlayerSummary;

  factory PlayerSummary.fromJson(Map<String, dynamic> json) =>
      _$PlayerSummaryFromJson(json);
}

/// The recipient's own view of the room.
@freezed
abstract class You with _$You {
  const factory You({
    required Role role,
    String? playerId,

    /// Present only in the snapshot right after this client was given the host
    /// role (PROTOCOL.md §5.1), and only to that client. Replace the stored
    /// token with it: the previous one has stopped working.
    String? hostToken,
    OwnSubmission? submission,
  }) = _You;

  factory You.fromJson(Map<String, dynamic> json) => _$YouFromJson(json);
}

/// The recipient's own submission for the current question.
/// [correct] and [delta] are `null` until `scoring`.
@freezed
abstract class OwnSubmission with _$OwnSubmission {
  const factory OwnSubmission({
    required String answer,
    required int wager,
    bool? correct,
    int? delta,
  }) = _OwnSubmission;

  factory OwnSubmission.fromJson(Map<String, dynamic> json) =>
      _$OwnSubmissionFromJson(json);
}

/// An entry of `submissions` (host view, and everyone after scoring).
///
/// PROTOCOL.md says only `override` may be null; [autoCorrect], [correct] and
/// [delta] stay nullable here purely for tolerance.
@freezed
abstract class SubmissionView with _$SubmissionView {
  const factory SubmissionView({
    required String playerId,
    required String answer,
    required int wager,
    bool? autoCorrect,

    /// Wire key `override` (renamed in Dart: a field named `override` shadows
    /// the `@override` annotation in generated code).
    @JsonKey(name: 'override') bool? overrideVerdict,
    bool? correct,
    @Default(1) int multiplier,
    int? delta,
  }) = _SubmissionView;

  factory SubmissionView.fromJson(Map<String, dynamic> json) =>
      _$SubmissionViewFromJson(json);
}
