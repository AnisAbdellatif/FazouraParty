import 'package:freezed_annotation/freezed_annotation.dart';

part 'game_error.freezed.dart';
part 'game_error.g.dart';

/// Error returned by the host for a join or intent (PROTOCOL.md §2, §4).
///
/// Client-side failures that never reach the host use codes defined in
/// [GameError] static constants (not part of the wire protocol).
@freezed
abstract class GameError with _$GameError implements Exception {
  const factory GameError({required String code, String? message}) = _GameError;

  factory GameError.fromJson(Map<String, dynamic> json) =>
      _$GameErrorFromJson(json);

  /// Client-local: the server could not be reached or did not answer.
  static const connectionFailed = 'connection_failed';

  /// Client-local: an intent was sent without a joined room.
  static const notJoined = 'not_joined';

  /// Client-local: the reply to an intent timed out.
  static const timeout = 'timeout';
}
