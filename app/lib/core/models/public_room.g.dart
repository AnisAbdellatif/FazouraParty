// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'public_room.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PublicRoom _$PublicRoomFromJson(Map<String, dynamic> json) => _PublicRoom(
  roomCode: json['room_code'] as String,
  phase: $enumDecode(_$PhaseEnumMap, json['phase']),
  packTitles:
      (json['pack_titles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  playerCount: (json['player_count'] as num).toInt(),
  roomSize: (json['room_size'] as num?)?.toInt(),
  questionIndex: (json['question_index'] as num?)?.toInt(),
  questionCount: (json['question_count'] as num).toInt(),
);

Map<String, dynamic> _$PublicRoomToJson(_PublicRoom instance) =>
    <String, dynamic>{
      'room_code': instance.roomCode,
      'phase': _$PhaseEnumMap[instance.phase]!,
      'pack_titles': instance.packTitles,
      'player_count': instance.playerCount,
      'room_size': instance.roomSize,
      'question_index': instance.questionIndex,
      'question_count': instance.questionCount,
    };

const _$PhaseEnumMap = {
  Phase.lobby: 'lobby',
  Phase.question: 'question',
  Phase.scoring: 'scoring',
  Phase.leaderboard: 'leaderboard',
  Phase.finished: 'finished',
};
