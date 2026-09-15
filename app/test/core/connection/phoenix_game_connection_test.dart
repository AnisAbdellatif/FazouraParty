import 'package:fazoura_party/core/connection/phoenix_game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoenixGameConnection.socketUri', () {
    test('maps http to ws and appends the socket path with vsn 2.0.0', () {
      expect(
        PhoenixGameConnection.socketUri('http://localhost:4000').toString(),
        'ws://localhost:4000/socket/websocket?vsn=2.0.0',
      );
    });

    test('maps https to wss and tolerates a trailing slash', () {
      expect(
        PhoenixGameConnection.socketUri('https://party.example.com/')
            .toString(),
        'wss://party.example.com/socket/websocket?vsn=2.0.0',
      );
    });
  });

  group('join payloads (PROTOCOL.md §4.1, v2)', () {
    test('host join sends display_name when playing along', () {
      expect(
        PhoenixGameConnection.joinPayload(
          displayName: 'Hana',
          hostToken: 'host-tok',
        ),
        {
          'protocol_version': 2,
          'display_name': 'Hana',
          'player_token': null,
          'host_token': 'host-tok',
        },
      );
    });

    test('non-playing host join sends a null display_name', () {
      expect(PhoenixGameConnection.joinPayload(hostToken: 'host-tok'), {
        'protocol_version': 2,
        'display_name': null,
        'player_token': null,
        'host_token': 'host-tok',
      });
    });

    test('host rejoins with host_token only', () {
      final join = PhoenixGameConnection.joinPayload(
        displayName: 'Hana',
        hostToken: 'host-tok',
      );
      expect(
        PhoenixGameConnection.rejoinPayload(
          join,
          const JoinResult(role: Role.host, playerId: 'p_host'),
        ),
        {
          'protocol_version': 2,
          'display_name': null,
          'player_token': null,
          'host_token': 'host-tok',
        },
      );
    });

    test('player rejoins with the issued player_token only', () {
      final join = PhoenixGameConnection.joinPayload(displayName: 'Sam');
      expect(
        PhoenixGameConnection.rejoinPayload(
          join,
          const JoinResult(
            role: Role.player,
            playerId: 'p_3f9a',
            playerToken: 'player-tok',
          ),
        ),
        {
          'protocol_version': 2,
          'display_name': null,
          'player_token': 'player-tok',
          'host_token': null,
        },
      );
    });
  });

  test('intents before joining throw not_joined', () async {
    final connection = PhoenixGameConnection(baseUrl: 'http://localhost:4000');
    await expectLater(
      connection.submit('x', 1),
      throwsA(
        isA<GameError>().having((e) => e.code, 'code', GameError.notJoined),
      ),
    );
    await connection.leave();
  });
}
