import 'dart:convert';

import 'package:fazoura_party/core/models/models.dart';

/// The `state` example from PROTOCOL.md §5.1, updated to protocol v2
/// (`protocol_version: 2`, `players[].is_host`).
const roomStateExampleJson = '''
{
  "protocol_version": 3,
  "room_code": "K7QX2M",
  "mode": "cloud",
  "phase": "question",
  "server_time": 1789502400000,

  "pack_title": "General Knowledge",
  "question_index": 2,
  "question_count": 10,
  "game_number": 1,
  "settings": {
    "question_count": 10,
    "time_limit_ms": 30000,
    "max_question_count": 10,
    "min_time_limit_ms": 10000,
    "max_time_limit_ms": 120000
  },

  "question": {
    "id": "q_03",
    "type": "text",
    "prompt": "What is the capital of Australia?",
    "image_url": null,
    "time_limit_ms": 30000
  },
  "deadline": 1789502430000,
  "paused_remaining_ms": null,
  "accepted_answers": null,

  "players": [
    {"id": "p_3f9a", "name": "Sam", "score": 12, "connected": true, "has_submitted": true, "is_host": false}
  ],

  "you": {
    "role": "player",
    "player_id": "p_3f9a",
    "submission": {"answer": "Canberra", "wager": 7, "correct": null, "delta": null}
  },

  "submissions": null
}
''';

/// The `submissions` entry example from PROTOCOL.md §5.1.
const submissionExampleJson = '''
{"player_id": "p_3f9a", "answer": "canbera", "wager": 7,
 "auto_correct": false, "override": true, "correct": true, "delta": 7}
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
        score: 4,
        connected: false,
        hasSubmitted: true,
      ),
      PlayerSummary(
        id: hostPlayerId,
        name: 'Hana',
        score: -2,
        connected: true,
        hasSubmitted: true,
        isHost: true,
      ),
      PlayerSummary(
        id: 'p_3f9a',
        name: 'Sam',
        score: -7,
        connected: true,
        hasSubmitted: true,
      ),
    ],
    you: const You(
      role: Role.host,
      playerId: hostPlayerId,
      submission: OwnSubmission(
        answer: 'Canbra',
        wager: 2,
        correct: false,
        delta: -2,
      ),
    ),
    submissions: const [
      SubmissionView(
        playerId: 'p_3f9a',
        answer: 'canbera',
        wager: 7,
        autoCorrect: false,
        correct: false,
        delta: -7,
      ),
      SubmissionView(
        playerId: 'p_b2c1',
        answer: 'Canberra',
        wager: 4,
        autoCorrect: true,
        correct: true,
        delta: 4,
      ),
      SubmissionView(
        playerId: hostPlayerId,
        answer: 'Canbra',
        wager: 2,
        autoCorrect: false,
        correct: false,
        delta: -2,
      ),
    ],
  );
}
