// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoomState _$RoomStateFromJson(Map<String, dynamic> json) => _RoomState(
  protocolVersion: (json['protocol_version'] as num).toInt(),
  roomCode: json['room_code'] as String,
  mode: $enumDecode(_$ModeEnumMap, json['mode']),
  phase: $enumDecode(_$PhaseEnumMap, json['phase']),
  serverTime: (json['server_time'] as num).toInt(),
  packTitle: json['pack_title'] as String?,
  questionIndex: (json['question_index'] as num?)?.toInt(),
  questionCount: (json['question_count'] as num).toInt(),
  question: json['question'] == null
      ? null
      : Question.fromJson(json['question'] as Map<String, dynamic>),
  deadline: (json['deadline'] as num?)?.toInt(),
  pausedRemainingMs: (json['paused_remaining_ms'] as num?)?.toInt(),
  acceptedAnswers: (json['accepted_answers'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  players:
      (json['players'] as List<dynamic>?)
          ?.map((e) => PlayerSummary.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PlayerSummary>[],
  you: You.fromJson(json['you'] as Map<String, dynamic>),
  submissions: (json['submissions'] as List<dynamic>?)
      ?.map((e) => SubmissionView.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$RoomStateToJson(_RoomState instance) =>
    <String, dynamic>{
      'protocol_version': instance.protocolVersion,
      'room_code': instance.roomCode,
      'mode': _$ModeEnumMap[instance.mode]!,
      'phase': _$PhaseEnumMap[instance.phase]!,
      'server_time': instance.serverTime,
      'pack_title': instance.packTitle,
      'question_index': instance.questionIndex,
      'question_count': instance.questionCount,
      'question': instance.question?.toJson(),
      'deadline': instance.deadline,
      'paused_remaining_ms': instance.pausedRemainingMs,
      'accepted_answers': instance.acceptedAnswers,
      'players': instance.players.map((e) => e.toJson()).toList(),
      'you': instance.you.toJson(),
      'submissions': instance.submissions?.map((e) => e.toJson()).toList(),
    };

const _$ModeEnumMap = {Mode.cloud: 'cloud', Mode.lan: 'lan'};

const _$PhaseEnumMap = {
  Phase.lobby: 'lobby',
  Phase.question: 'question',
  Phase.scoring: 'scoring',
  Phase.leaderboard: 'leaderboard',
  Phase.finished: 'finished',
};

_Question _$QuestionFromJson(Map<String, dynamic> json) => _Question(
  id: json['id'] as String,
  type: $enumDecode(_$QuestionTypeEnumMap, json['type']),
  prompt: json['prompt'] as String,
  imageUrl: json['image_url'] as String?,
  timeLimitMs: (json['time_limit_ms'] as num).toInt(),
);

Map<String, dynamic> _$QuestionToJson(_Question instance) => <String, dynamic>{
  'id': instance.id,
  'type': _$QuestionTypeEnumMap[instance.type]!,
  'prompt': instance.prompt,
  'image_url': instance.imageUrl,
  'time_limit_ms': instance.timeLimitMs,
};

const _$QuestionTypeEnumMap = {
  QuestionType.text: 'text',
  QuestionType.textPhoto: 'text_photo',
};

_PlayerSummary _$PlayerSummaryFromJson(Map<String, dynamic> json) =>
    _PlayerSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      score: (json['score'] as num).toInt(),
      connected: json['connected'] as bool,
      hasSubmitted: json['has_submitted'] as bool,
    );

Map<String, dynamic> _$PlayerSummaryToJson(_PlayerSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'score': instance.score,
      'connected': instance.connected,
      'has_submitted': instance.hasSubmitted,
    };

_You _$YouFromJson(Map<String, dynamic> json) => _You(
  role: $enumDecode(_$RoleEnumMap, json['role']),
  playerId: json['player_id'] as String?,
  submission: json['submission'] == null
      ? null
      : OwnSubmission.fromJson(json['submission'] as Map<String, dynamic>),
);

Map<String, dynamic> _$YouToJson(_You instance) => <String, dynamic>{
  'role': _$RoleEnumMap[instance.role]!,
  'player_id': instance.playerId,
  'submission': instance.submission?.toJson(),
};

const _$RoleEnumMap = {Role.host: 'host', Role.player: 'player'};

_OwnSubmission _$OwnSubmissionFromJson(Map<String, dynamic> json) =>
    _OwnSubmission(
      answer: json['answer'] as String,
      wager: (json['wager'] as num).toInt(),
      correct: json['correct'] as bool?,
      delta: (json['delta'] as num?)?.toInt(),
    );

Map<String, dynamic> _$OwnSubmissionToJson(_OwnSubmission instance) =>
    <String, dynamic>{
      'answer': instance.answer,
      'wager': instance.wager,
      'correct': instance.correct,
      'delta': instance.delta,
    };

_SubmissionView _$SubmissionViewFromJson(Map<String, dynamic> json) =>
    _SubmissionView(
      playerId: json['player_id'] as String,
      answer: json['answer'] as String,
      wager: (json['wager'] as num).toInt(),
      autoCorrect: json['auto_correct'] as bool?,
      overrideVerdict: json['override'] as bool?,
      correct: json['correct'] as bool?,
      delta: (json['delta'] as num?)?.toInt(),
    );

Map<String, dynamic> _$SubmissionViewToJson(_SubmissionView instance) =>
    <String, dynamic>{
      'player_id': instance.playerId,
      'answer': instance.answer,
      'wager': instance.wager,
      'auto_correct': instance.autoCorrect,
      'override': instance.overrideVerdict,
      'correct': instance.correct,
      'delta': instance.delta,
    };
