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

@freezed
abstract class Question with _$Question {
  const factory Question({
    required String id,
    required QuestionType type,
    required String prompt,
    String? imageUrl,
    required int timeLimitMs,
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
/// [autoCorrect], [correct] and [delta] are nullable because PROTOCOL.md does
/// not state their value in the host view during `question`, before
/// auto-matching has run.
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
    int? delta,
  }) = _SubmissionView;

  factory SubmissionView.fromJson(Map<String, dynamic> json) =>
      _$SubmissionViewFromJson(json);
}
