import 'dart:convert';

import 'package:fazoura_party/core/models/models.dart';

/// The `state` example from PROTOCOL.md §5.1.
const roomStateExampleJson = '''
{
  "protocol_version": 9,
  "protocol_minor": 9,
  "listed": false,
  "room_size": 32,
  "room_size_limit": 32,
  "room_code": "K7QX2M",
  "mode": "cloud",
  "phase": "question",
  "server_time": 1789502400000,

  "pack_titles": ["General Knowledge"],
  "question_index": 2,
  "question_count": 10,
  "game_number": 1,
  "settings": {
    "question_count": 10,
    "time_limit_ms": 30000,
    "difficulty_multiplier": false,
    "difficulties": ["easy", "medium", "hard"],
    "available_difficulties": ["easy", "medium", "hard"],
    "max_question_count": 10,
    "min_time_limit_ms": 10000,
    "max_time_limit_ms": 120000
  },

  "question": {
    "id": "q_03",
    "type": "text",
    "prompt": "What is the capital of Australia?",
    "image_url": null,
    "time_limit_ms": 30000,
    "difficulty": "easy",
    "points": {"right": 10, "wrong": -10, "skipped": -10}
  },
  "deadline": 1789502430000,
  "paused_remaining_ms": null,
  "accepted_answers": null,

  "players": [
    {"id": "p_3f9a", "name": "Sam", "score": 12, "connected": true, "has_submitted": true, "is_host": false, "avatar_hue": 212}
  ],

  "you": {
    "role": "player",
    "player_id": "p_3f9a",
    "host_token": null,
    "submission": {"answer": "Canberra", "correct": null, "delta": null}
  },

  "submissions": null
}
''';

/// The `submissions` entry example from PROTOCOL.md §5.1.
const submissionExampleJson = '''
{"player_id": "p_3f9a", "answer": "canbera",
 "auto_correct": false, "override": true, "correct": true, "delta": 25}
''';

RoomState exampleRoomState() => RoomState.fromJson(
  jsonDecode(roomStateExampleJson) as Map<String, dynamic>,
);

const hostPlayerId = 'p_host';

const _sam = PlayerSummary(
  id: 'p_3f9a',
  name: 'Sam',
  score: 12,
  connected: true,
  hasSubmitted: true,
);

const _hana = PlayerSummary(
  id: hostPlayerId,
  name: 'Hana',
  score: 3,
  connected: true,
  hasSubmitted: false,
  isHost: true,
);

/// A far-future deadline so countdowns never reach zero during tests.
RoomState questionStateForPlayer({OwnSubmission? submission}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return exampleRoomState().copyWith(
    serverTime: now,
    deadline: now + const Duration(minutes: 10).inMilliseconds,
    you: You(role: Role.player, playerId: 'p_3f9a', submission: submission),
  );
}

/// Host view during `question` (v2: no answers or submissions revealed).
RoomState questionStateForHost({required bool playing}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return exampleRoomState().copyWith(
    serverTime: now,
    deadline: now + const Duration(minutes: 10).inMilliseconds,
    players: playing ? const [_sam, _hana] : const [_sam],
    you: You(role: Role.host, playerId: playing ? hostPlayerId : null),
  );
}

RoomState lobbyStateWithQuiz() {
  return exampleRoomState().copyWith(
    phase: Phase.lobby,
    questionIndex: null,
    question: null,
    deadline: null,
    acceptedAnswers: null,
    submissions: null,
  );
}

/// Playing host during `scoring`, with their own submission.
RoomState scoringStateForHost() {
  return exampleRoomState().copyWith(
    phase: Phase.scoring,
    deadline: null,
    acceptedAnswers: const ['Canberra'],
    players: const [
      PlayerSummary(
        id: 'p_b2c1',
        name: 'Alex',
        score: 10,
        connected: false,
        hasSubmitted: true,
      ),
      PlayerSummary(
        id: hostPlayerId,
        name: 'Hana',
        score: -10,
        connected: true,
        hasSubmitted: true,
        isHost: true,
      ),
      PlayerSummary(
        id: 'p_3f9a',
        name: 'Sam',
        score: -10,
        connected: true,
        hasSubmitted: true,
      ),
    ],
    you: const You(
      role: Role.host,
      playerId: hostPlayerId,
      submission: OwnSubmission(answer: 'Canbra', correct: false, delta: -10),
    ),
    submissions: const [
      SubmissionView(
        playerId: 'p_3f9a',
        answer: 'canbera',
        autoCorrect: false,
        correct: false,
        delta: -10,
      ),
      SubmissionView(
        playerId: 'p_b2c1',
        answer: 'Canberra',
        autoCorrect: true,
        correct: true,
        delta: 10,
      ),
      SubmissionView(
        playerId: hostPlayerId,
        answer: 'Canbra',
        autoCorrect: false,
        correct: false,
        delta: -10,
      ),
    ],
  );
}
