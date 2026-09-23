/// The shell around the rules: tokens, connections, promotion and the two
/// ways a room ends.
///
/// The counterpart of `FazouraWeb.RoomChannelTest` and
/// `FazouraWeb.HostRoleTest`, which cover the same ground for Cloud. Anything
/// here that is only "how a LAN host happens to do it" is called out; the rest
/// is contract, and both hosts must answer the same way.
@TestOn('vm')
library;

import 'dart:math';

import 'package:fazoura_party/core/game/game.dart';
import 'package:fazoura_party/core/game/lan_room.dart';
import 'package:fazoura_party/core/game/pack.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/matchers.dart';

const _t0 = 1000000;

Pack _pack([int questions = 2]) => Pack.fromMap({
  'title': 'Test',
  'questions': [
    for (var i = 1; i <= questions; i++)
      {
        'id': 'q$i',
        'prompt': 'Question $i?',
        'accepted_answers': ['Right'],
        'time_limit_ms': 10000,
      },
  ],
});

/// One client, and everything the room pushed to it.
class _Client implements LanConnection {
  final List<Map<String, dynamic>> states = [];
  String? closedReason;

  Map<String, dynamic> get latest => states.last;
  Map<String, dynamic> get you => latest['you'] as Map<String, dynamic>;

  @override
  void pushState(Map<String, dynamic> state) => states.add(state);

  @override
  void pushClosed(String reason) => closedReason = reason;
}

void main() {
  late int clock;
  late LanRoom room;

  setUp(() {
    clock = _t0;
    room = LanRoom.create(
      pack: _pack(),
      now: () => clock,
      random: Random(42),
      shuffleQuestions: false,
      broadcastGap: Duration.zero,
    );
  });

  tearDown(() => room.close(LanCloseReason.shutdown));

  Map<String, dynamic> joinParams([Map<String, dynamic> extra = const {}]) => {
    'protocol_version': protocolMajor,
    ...extra,
  };

  ({_Client client, LanJoinReply reply}) join([
    Map<String, dynamic> extra = const {},
  ]) {
    final client = _Client();
    return (client: client, reply: room.join(client, joinParams(extra)));
  }

  group('joining', () {
    test('a join is answered with a snapshot straight away', () {
      final sam = join({'display_name': 'Sam'});
      expect(sam.reply.role, 'player');
      expect(sam.reply.playerToken, isNotNull);
      expect(sam.client.states, hasLength(1));
      expect(sam.client.latest['room_code'], room.code);
      expect(sam.client.you['player_id'], sam.reply.playerId);
    });

    test('the version is checked before anything else', () {
      expect(
        () => room.join(_Client(), {
          'protocol_version': protocolMajor - 1,
          'display_name': 'Sam',
        }),
        throwsCode('unsupported_protocol_version'),
      );
      // A refused join leaves no trace: the name is still free.
      expect(room.game.players, isEmpty);
    });

    test('a forged or stale token is refused, never silently re-issued', () {
      expect(
        () => room.join(_Client(), joinParams({'player_token': 'forged'})),
        throwsCode('invalid_token'),
      );
      expect(
        () => room.join(_Client(), joinParams({'host_token': 'forged'})),
        throwsCode('invalid_token'),
      );
      expect(room.game.players, isEmpty);
    });

    test('a name is taken whether or not its owner is still connected', () {
      final sam = join({'display_name': 'Sam'});
      expect(
        () => room.join(_Client(), joinParams({'display_name': 'sam'})),
        throwsCode('name_taken'),
      );

      room.leave(sam.client);
      expect(
        () => room.join(_Client(), joinParams({'display_name': 'SAM'})),
        throwsCode('name_taken'),
      );
    });

    test('rejoining with the token reclaims the same player and score', () {
      final sam = join({'display_name': 'Sam'});
      // Kim never answers. Without somebody still owing an answer, Sam's
      // submission would end the question (§6) and the round trip below would
      // be through a scored question rather than a live one.
      join({'display_name': 'Kim'});
      final host = join({'host_token': room.hostToken});

      room.handle(host.client, 'host_next', {});
      room.handle(sam.client, 'submit', {'answer': 'Right'});
      room.leave(sam.client);

      expect(room.game.players[sam.reply.playerId]!.connected, isFalse);
      expect(room.game.players[sam.reply.playerId]!.score, 0);

      final back = join({'player_token': sam.reply.playerToken});
      expect(back.reply.playerId, sam.reply.playerId);
      expect(room.game.players[sam.reply.playerId]!.connected, isTrue);
      // The submission survived the round trip, which is the whole point of
      // rejoining rather than starting again (§4.1).
      expect(back.client.you['submission'], {
        'answer': 'Right',
        'correct': null,
        'delta': null,
      });
    });

    test('a host join with a name plays too, and later joins need no name', () {
      final first = join({
        'host_token': room.hostToken,
        'display_name': 'Hana',
      });
      expect(first.reply.role, 'host');
      expect(first.reply.playerId, isNotNull);

      room.leave(first.client);
      final again = join({'host_token': room.hostToken});
      expect(again.reply.playerId, first.reply.playerId);
      expect(room.game.players, hasLength(1));
    });

    test('a host join that fails leaves the host out, token still good', () {
      join({'display_name': 'Hana'});
      expect(
        () => room.join(
          _Client(),
          joinParams({'host_token': room.hostToken, 'display_name': 'hana'}),
        ),
        throwsCode('name_taken'),
      );
      expect(room.connectionCount, 1);
      expect(
        room.join(_Client(), joinParams({'host_token': room.hostToken})).role,
        'host',
      );
    });
  });

  group('leaving', () {
    test(
      'a player who leaves keeps their score and is marked disconnected',
      () {
        final host = join({'host_token': room.hostToken});
        final sam = join({'display_name': 'Sam'});

        room.handle(host.client, 'host_next', {});
        room.handle(sam.client, 'submit', {'answer': 'Right'});
        room.handle(host.client, 'host_next', {});
        room.leave(sam.client);

        final players = (host.client.latest['players'] as List)
            .cast<Map<String, dynamic>>();
        expect(players.single['score'], 10);
        expect(players.single['connected'], isFalse);
      },
    );

    test('a second socket for the same player keeps them connected', () {
      final sam = join({'display_name': 'Sam'});
      final same = join({'player_token': sam.reply.playerToken});

      room.leave(same.client);
      expect(room.game.players[sam.reply.playerId]!.connected, isTrue);
      room.leave(sam.client);
      expect(room.game.players[sam.reply.playerId]!.connected, isFalse);
    });
  });

  group('the host role', () {
    test('transfer hands the role over and issues one new token', () {
      final host = join({'host_token': room.hostToken, 'display_name': 'Hana'});
      final sam = join({'display_name': 'Sam'});

      room.handle(host.client, 'host_transfer', {
        'player_id': sam.reply.playerId,
      });

      // The token reaches exactly one recipient, once (§5.1).
      final token = sam.client.you['host_token'] as String?;
      expect(token, isNotNull);
      expect(host.client.you['host_token'], isNull);
      expect(sam.client.states.last['you'], isNotNull);

      room.handle(sam.client, 'host_next', {});
      expect(sam.client.you['host_token'], isNull);

      // The old token is dead; the new one works.
      expect(
        () => room.join(_Client(), joinParams({'host_token': room.hostToken})),
        throwsCode('invalid_token'),
      );
      expect(
        room.join(_Client(), joinParams({'host_token': token})).role,
        'host',
      );
    });

    test('the former host stays in the game as an ordinary player', () {
      final host = join({'host_token': room.hostToken, 'display_name': 'Hana'});
      final sam = join({'display_name': 'Sam'});

      room.handle(host.client, 'host_transfer', {
        'player_id': sam.reply.playerId,
      });

      expect(host.client.you['role'], 'player');
      expect(host.client.you['player_id'], isNotNull);
      expect(
        () => room.handle(host.client, 'host_next', {}),
        throwsCode('not_host'),
      );
      expect(
        () => room.handle(host.client, 'host_close', {}),
        throwsCode('not_host'),
      );
      // Still a player, and still able to play.
      room.handle(sam.client, 'host_next', {});
      room.handle(host.client, 'submit', {'answer': 'Right'});
      expect(room.game.submissions, hasLength(1));
    });

    test('the role can only go to someone who is connected', () {
      final host = join({'host_token': room.hostToken});
      final sam = join({'display_name': 'Sam'});
      room.leave(sam.client);

      expect(
        () => room.handle(host.client, 'host_transfer', {
          'player_id': sam.reply.playerId,
        }),
        throwsCode('not_connected'),
      );
      expect(
        () => room.handle(host.client, 'host_transfer', {'player_id': 'ghost'}),
        throwsCode('not_connected'),
      );
      expect(
        () => room.handle(host.client, 'host_transfer', {'player_id': 42}),
        throwsCode('invalid_payload'),
      );
    });

    test('a host who drops is replaced by a player who is still there', () {
      final host = join({'host_token': room.hostToken});
      final sam = join({'display_name': 'Sam'});

      room.leave(host.client);

      expect(sam.client.you['role'], 'host');
      expect(sam.client.you['host_token'], isNotNull);
      // And the room never sat hostless: the promotion is in the same snapshot
      // that reports the host leaving.
      room.handle(sam.client, 'host_next', {});
      expect(room.game.phase, GamePhase.question);
    });

    test('with nobody else there the room keeps its host and waits', () {
      final host = join({'host_token': room.hostToken});
      room.leave(host.client);

      expect(room.isClosed, isFalse);
      expect(
        room.join(_Client(), joinParams({'host_token': room.hostToken})).role,
        'host',
      );
    });

    test('only the host connection may close the room', () {
      final host = join({'host_token': room.hostToken});
      final sam = join({'display_name': 'Sam'});

      expect(
        () => room.handle(sam.client, 'host_close', {}),
        throwsCode('not_host'),
      );
      expect(room.isClosed, isFalse);

      room.handle(host.client, 'host_close', {});
      expect(room.isClosed, isTrue);
      expect(host.client.closedReason, 'closed');
      expect(sam.client.closedReason, 'closed');
    });

    test('a closed room refuses everything after it ends', () {
      final host = join({'host_token': room.hostToken});
      room.handle(host.client, 'host_close', {});

      expect(
        () => room.join(_Client(), joinParams({'display_name': 'Late'})),
        throwsCode('room_not_found'),
      );
      expect(
        () => room.handle(host.client, 'host_next', {}),
        throwsCode('room_not_found'),
      );
    });
  });

  group('pacing', () {
    // Real time, not the injected clock: pacing is delivery, not game time.
    test(
      'changes inside the gap share one snapshot, sent once it has passed',
      () async {
        final paced = LanRoom.create(
          pack: _pack(),
          now: () => clock,
          random: Random(7),
          broadcastGap: const Duration(milliseconds: 80),
        );
        addTearDown(() => paced.close(LanCloseReason.shutdown));
        final host = _Client();
        paced.join(host, {
          'protocol_version': protocolMajor,
          'host_token': paced.hostToken,
        });
        expect(host.states, hasLength(1), reason: 'a quiet room sends at once');

        for (final name in ['Sam', 'Kim', 'Lee']) {
          paced.join(_Client(), {
            'protocol_version': protocolMajor,
            'display_name': name,
          });
        }
        expect(host.states, hasLength(1), reason: 'inside the gap: held back');

        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(host.states, hasLength(2));
        expect(host.latest['players'], hasLength(3));
      },
    );

    test(
      'a room that closes with a snapshot pending sends nothing more',
      () async {
        final paced = LanRoom.create(
          pack: _pack(),
          now: () => clock,
          random: Random(7),
          broadcastGap: const Duration(milliseconds: 50),
        );
        final host = _Client();
        paced.join(host, {
          'protocol_version': protocolMajor,
          'host_token': paced.hostToken,
        });
        paced.join(_Client(), {
          'protocol_version': protocolMajor,
          'display_name': 'Sam',
        });
        paced.close(LanCloseReason.closed);

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(host.states, hasLength(1));
        expect(host.closedReason, 'closed');
      },
    );
  });

  group('lifetime', () {
    test('a room nobody is in closes after 30 seconds', () async {
      final host = join({'host_token': room.hostToken});
      room.leave(host.client);

      clock += emptyTtl.inMilliseconds - 1;
      room.tick();
      expect(room.isClosed, isFalse);

      clock += 1;
      room.tick();
      expect(room.isClosed, isTrue);
      expect(await room.closed, LanCloseReason.empty);
      expect(host.client.closedReason, isNull, reason: 'already gone');
    });

    test('a room that was never joined still gets its 30 seconds', () {
      clock += emptyTtl.inMilliseconds;
      room.tick();
      expect(room.isClosed, isTrue);
    });

    test('a finished room closes after ten minutes', () async {
      final host = join({'host_token': room.hostToken});
      for (var i = 0; i < 7; i++) {
        room.handle(host.client, 'host_next', {});
      }
      expect(room.game.phase, GamePhase.finished);

      clock += finishedTtl.inMilliseconds;
      room.tick();
      expect(await room.closed, LanCloseReason.finished);
      expect(host.client.closedReason, 'finished');
    });

    test('a rematch cancels the finished-room expiry', () {
      final host = join({'host_token': room.hostToken});
      for (var i = 0; i < 7; i++) {
        room.handle(host.client, 'host_next', {});
      }
      room.handle(host.client, 'host_rematch', {});

      clock += finishedTtl.inMilliseconds;
      room.tick();
      expect(room.isClosed, isFalse);
    });

    test('a question ends on its own when the deadline passes', () {
      final host = join({'host_token': room.hostToken});
      final sam = join({'display_name': 'Sam'});
      room.handle(host.client, 'host_next', {});
      room.handle(sam.client, 'submit', {'answer': 'Right'});

      clock += 10000;
      room.tick();

      expect(room.game.phase, GamePhase.scoring);
      expect(sam.client.latest['phase'], 'scoring');
      expect(room.game.players[sam.reply.playerId]!.score, 10);
    });
  });

  group('room codes', () {
    test('avoid the characters that get misread aloud', () {
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        final code = LanRoom.generateRoomCode(random);
        expect(code, hasLength(roomCodeLength));
        expect(code, matches(RegExp('^[$roomCodeAlphabet]+\$')));
        expect(code, isNot(matches(RegExp('[IO01]'))));
      }
    });
  });
}
