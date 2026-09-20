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
  packTitles:
      (json['pack_titles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  questionIndex: (json['question_index'] as num?)?.toInt(),
  questionCount: (json['question_count'] as num).toInt(),
  gameNumber: (json['game_number'] as num?)?.toInt() ?? 1,
  settings: json['settings'] == null
      ? null
      : GameSettings.fromJson(json['settings'] as Map<String, dynamic>),
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
      'pack_titles': instance.packTitles,
      'question_index': instance.questionIndex,
      'question_count': instance.questionCount,
      'game_number': instance.gameNumber,
      'settings': instance.settings?.toJson(),
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

_GameSettings _$GameSettingsFromJson(Map<String, dynamic> json) =>
    _GameSettings(
      questionCount: (json['question_count'] as num).toInt(),
      timeLimitMs: (json['time_limit_ms'] as num).toInt(),
      maxQuestionCount: (json['max_question_count'] as num).toInt(),
      difficultyMultiplier: json['difficulty_multiplier'] as bool? ?? false,
      difficulties:
          (json['difficulties'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>['easy', 'medium', 'hard'],
      availableDifficulties:
          (json['available_difficulties'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>['easy', 'medium', 'hard'],
      minTimeLimitMs: (json['min_time_limit_ms'] as num?)?.toInt() ?? 10000,
      maxTimeLimitMs: (json['max_time_limit_ms'] as num?)?.toInt() ?? 120000,
    );

Map<String, dynamic> _$GameSettingsToJson(_GameSettings instance) =>
    <String, dynamic>{
      'question_count': instance.questionCount,
      'time_limit_ms': instance.timeLimitMs,
      'max_question_count': instance.maxQuestionCount,
      'difficulty_multiplier': instance.difficultyMultiplier,
      'difficulties': instance.difficulties,
      'available_difficulties': instance.availableDifficulties,
      'min_time_limit_ms': instance.minTimeLimitMs,
      'max_time_limit_ms': instance.maxTimeLimitMs,
    };

_Question _$QuestionFromJson(Map<String, dynamic> json) => _Question(
  id: json['id'] as String,
  type: $enumDecode(_$QuestionTypeEnumMap, json['type']),
  prompt: json['prompt'] as String,
  imageUrl: json['image_url'] as String?,
  timeLimitMs: (json['time_limit_ms'] as num).toInt(),
  difficulty: json['difficulty'] as String? ?? 'easy',
  multiplier: (json['multiplier'] as num?)?.toInt() ?? 1,
);

Map<String, dynamic> _$QuestionToJson(_Question instance) => <String, dynamic>{
  'id': instance.id,
  'type': _$QuestionTypeEnumMap[instance.type]!,
  'prompt': instance.prompt,
  'image_url': instance.imageUrl,
  'time_limit_ms': instance.timeLimitMs,
  'difficulty': instance.difficulty,
  'multiplier': instance.multiplier,
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
      isHost: json['is_host'] as bool? ?? false,
      avatarHue: (json['avatar_hue'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PlayerSummaryToJson(_PlayerSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'score': instance.score,
      'connected': instance.connected,
      'has_submitted': instance.hasSubmitted,
      'is_host': instance.isHost,
      'avatar_hue': instance.avatarHue,
    };

_You _$YouFromJson(Map<String, dynamic> json) => _You(
  role: $enumDecode(_$RoleEnumMap, json['role']),
  playerId: json['player_id'] as String?,
  hostToken: json['host_token'] as String?,
  submission: json['submission'] == null
      ? null
      : OwnSubmission.fromJson(json['submission'] as Map<String, dynamic>),
);

Map<String, dynamic> _$YouToJson(_You instance) => <String, dynamic>{
  'role': _$RoleEnumMap[instance.role]!,
  'player_id': instance.playerId,
  'host_token': instance.hostToken,
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
      multiplier: (json['multiplier'] as num?)?.toInt() ?? 1,
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
      'multiplier': instance.multiplier,
      'delta': instance.delta,
    };
