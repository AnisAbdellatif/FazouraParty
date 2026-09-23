/// The protocol's fixed numbers, held to `protocol/fixtures/constants.json` —
/// the file the server's are held to as well (`Fazoura.ProtocolConstantsTest`).
@TestOn('vm')
library;

import 'package:fazoura_party/core/game/game.dart';
import 'package:fazoura_party/core/game/lan_room.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/protocol_fixtures.dart';

void main() {
  test("the LAN host's constants are exactly the shared ones", () {
    final shared = Map.of(ProtocolFixtures.load('constants.json'))
      ..removeWhere((key, _) => key.startsWith('_'));

    final ours = <String, Object>{
      'protocol_major': protocolMajor,
      'protocol_minor': protocolMinor,
      'waiting_grace_ms': waitingGraceMs,
      'closing_window_ms': closingWindowMs,
      'skip_points': skipPoints,
      'min_time_limit_ms': minTimeLimitMs,
      'max_time_limit_ms': maxTimeLimitMs,
      'default_time_limit_ms': defaultTimeLimitMs,
      'max_players': maxPlayers,
      'max_name_length': maxNameLength,
      'max_answer_length': maxAnswerLength,
      'difficulties': supportedDifficulties,
      'max_quizzes': maxQuizzes,
      'room_code_alphabet': roomCodeAlphabet,
      'room_code_length': roomCodeLength,
      'empty_room_ttl_ms': emptyTtl.inMilliseconds,
      'finished_room_ttl_ms': finishedTtl.inMilliseconds,
      'broadcast_interval_ms': broadcastInterval.inMilliseconds,
    };

    expect(ours, shared);
  });
}
