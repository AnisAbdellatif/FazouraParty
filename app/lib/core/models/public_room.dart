import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'public_room.freezed.dart';
part 'public_room.g.dart';

/// One entry of `GET /api/rooms`, the public room list (PROTOCOL.md §3.5).
///
/// No names on purpose: the list is read by strangers, and a quiz title is the
/// only text on it a person has reviewed.
@freezed
abstract class PublicRoom with _$PublicRoom {
  const factory PublicRoom({
    required String roomCode,
    required Phase phase,

    /// Empty while the host is still choosing.
    @Default(<String>[]) List<String> packTitles,
    required int playerCount,

    /// How many the room lets in (PROTOCOL.md §6.5). Absent before 9.9.
    int? roomSize,
    int? questionIndex,
    required int questionCount,
  }) = _PublicRoom;

  factory PublicRoom.fromJson(Map<String, dynamic> json) =>
      _$PublicRoomFromJson(json);
}
