import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'join_result.freezed.dart';
part 'join_result.g.dart';

/// `ok` response of a `phx_join` (PROTOCOL.md §4.1).
@freezed
abstract class JoinResult with _$JoinResult {
  const factory JoinResult({
    required Role role,
    String? playerId,
    String? playerToken,
  }) = _JoinResult;

  factory JoinResult.fromJson(Map<String, dynamic> json) =>
      _$JoinResultFromJson(json);
}

/// `201` response of `POST /api/rooms` (PROTOCOL.md §3.1).
@freezed
abstract class CreatedRoom with _$CreatedRoom {
  const factory CreatedRoom({
    required String roomCode,
    required String hostToken,
  }) = _CreatedRoom;

  factory CreatedRoom.fromJson(Map<String, dynamic> json) =>
      _$CreatedRoomFromJson(json);
}
