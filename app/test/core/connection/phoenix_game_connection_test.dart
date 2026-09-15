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
