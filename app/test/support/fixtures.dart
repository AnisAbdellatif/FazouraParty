import 'dart:convert';

import 'package:fazoura_party/core/models/models.dart';

/// The `state` example from PROTOCOL.md §5.1, verbatim.
const roomStateExampleJson = '''
{
  "protocol_version": 1,
  "room_code": "K7QX2M",
  "mode": "cloud",
  "phase": "question",
  "server_time": 1789502400000,

  "pack_title": "General Knowledge",
  "question_index": 2,
  "question_count": 10,

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
    {"id": "p_3f9a", "name": "Sam", "score": 12, "connected": true, "has_submitted": true}
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

/// A far-future deadline so countdowns never reach zero during tests.
RoomState questionStateForPlayer({OwnSubmission? submission}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return exampleRoomState().copyWith(
    serverTime: now,
    deadline: now + const Duration(minutes: 10).inMilliseconds,
    you: You(role: Role.player, playerId: 'p_3f9a', submission: submission),
  );
}

RoomState scoringStateForHost() {
  final base = exampleRoomState();
  return base.copyWith(
    phase: Phase.scoring,
    deadline: null,
    acceptedAnswers: const ['Canberra'],
    players: const [
      PlayerSummary(
        id: 'p_3f9a',
        name: 'Sam',
        score: -7,
        connected: true,
        hasSubmitted: true,
      ),
      PlayerSummary(
        id: 'p_b2c1',
        name: 'Alex',
        score: 4,
        connected: false,
        hasSubmitted: true,
      ),
    ],
    you: const You(role: Role.host),
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
    ],
  );
}
