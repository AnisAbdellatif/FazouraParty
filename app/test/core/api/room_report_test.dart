import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request captured;

  RoomApi api(http.Response Function() respond) => RoomApi(
    baseUrl: 'http://localhost:4000',
    client: MockClient((request) async {
      captured = request;
      return respond();
    }),
  );

  Map<String, dynamic> body() =>
      jsonDecode(captured.body) as Map<String, dynamic>;

  test('names the room, the question and this device', () async {
    await api(() => http.Response('', 204)).reportRoom(
      'K7QX2M',
      reason: 'sexual',
      ownerKey: 'owner-key-1',
      playerToken: 'player-token-1',
      questionId: 'q7',
      note: 'The photo on this one.',
    );

    expect(captured.url.path, '/api/rooms/K7QX2M/report');
    expect(captured.headers['x-player-token'], 'player-token-1');
    expect(captured.headers['x-owner-key'], 'owner-key-1');
    expect(body(), {
      'reason': 'sexual',
      'question_id': 'q7',
      'note': 'The photo on this one.',
    });
  });

  test('a host has only a host token, and that counts too', () async {
    await api(() => http.Response('', 204)).reportRoom(
      'K7QX2M',
      reason: 'spam',
      ownerKey: 'owner-key-1',
      hostToken: 'host-token-1',
    );

    expect(captured.headers['x-host-token'], 'host-token-1');
    expect(captured.headers.containsKey('x-player-token'), isFalse);
  });

  test('an empty note is left out rather than sent blank', () async {
    await api(() => http.Response('', 204)).reportRoom(
      'K7QX2M',
      reason: 'spam',
      ownerKey: 'owner-key-1',
      playerToken: 'player-token-1',
      note: '   '.trim(),
    );

    expect(body().containsKey('note'), isFalse);
    expect(body().containsKey('question_id'), isFalse);
  });

  test('a private quiz has nothing published to take down', () async {
    final call =
        api(
          () => http.Response(
            jsonEncode({
              'code': 'quiz_not_public',
              'message': 'Nothing to remove.',
            }),
            422,
          ),
        ).reportRoom(
          'K7QX2M',
          reason: 'spam',
          ownerKey: 'owner-key-1',
          playerToken: 'player-token-1',
        );

    await expectLater(
      call,
      throwsA(
        isA<GameError>().having((e) => e.code, 'code', 'quiz_not_public'),
      ),
    );
  });

  test('a caller the room does not know is told nothing', () async {
    final call =
        api(() => http.Response(jsonEncode({'code': 'room_not_found'}), 404))
            .reportRoom(
              'K7QX2M',
              reason: 'spam',
              ownerKey: 'owner-key-1',
              playerToken: 'stale',
            );

    await expectLater(
      call,
      throwsA(isA<GameError>().having((e) => e.code, 'code', 'room_not_found')),
    );
  });

  test('an unreachable server is a connection failure, not a report', () async {
    final call =
        RoomApi(
          baseUrl: 'http://localhost:4000',
          client: MockClient((_) async => throw const _Offline()),
        ).reportRoom(
          'K7QX2M',
          reason: 'spam',
          ownerKey: 'owner-key-1',
          playerToken: 'player-token-1',
        );

    await expectLater(
      call,
      throwsA(
        isA<GameError>().having(
          (e) => e.code,
          'code',
          GameError.connectionFailed,
        ),
      ),
    );
  });
}

class _Offline implements Exception {
  const _Offline();
}
