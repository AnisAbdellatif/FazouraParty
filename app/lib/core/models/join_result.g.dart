// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'join_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_JoinResult _$JoinResultFromJson(Map<String, dynamic> json) => _JoinResult(
  role: $enumDecode(_$RoleEnumMap, json['role']),
  playerId: json['player_id'] as String?,
  playerToken: json['player_token'] as String?,
);

Map<String, dynamic> _$JoinResultToJson(_JoinResult instance) =>
    <String, dynamic>{
      'role': _$RoleEnumMap[instance.role]!,
      'player_id': instance.playerId,
      'player_token': instance.playerToken,
    };

const _$RoleEnumMap = {Role.host: 'host', Role.player: 'player'};

_CreatedRoom _$CreatedRoomFromJson(Map<String, dynamic> json) => _CreatedRoom(
  roomCode: json['room_code'] as String,
  hostToken: json['host_token'] as String,
);

Map<String, dynamic> _$CreatedRoomToJson(_CreatedRoom instance) =>
    <String, dynamic>{
      'room_code': instance.roomCode,
      'host_token': instance.hostToken,
    };
