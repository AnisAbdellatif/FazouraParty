import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('createRoom creates an empty room before quiz selection', () async {
    late http.Request captured;
    final api = RoomApi(
      baseUrl: 'http://localhost:4000',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'room_code': 'K7QX2M', 'host_token': 'signed'}),
          201,
        );
      }),
    );

    final created = await api.createRoom();

    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'http://localhost:4000/api/rooms');
    expect(jsonDecode(captured.body), isEmpty);
    expect(created, const CreatedRoom(roomCode: 'K7QX2M', hostToken: 'signed'));
  });

  test('createRoom sends a private quiz inline with photo data', () async {
    late http.Request captured;
    final api = RoomApi(
      baseUrl: 'http://localhost:4000',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'room_code': 'K7QX2M', 'host_token': 'signed'}),
          201,
        );
      }),
    );

    await api.createRoom(
      inlineQuiz: const QuizDocument(
        title: 'Secret',
        questions: [
          QuizQuestion(
            type: QuizQuestion.typePhoto,
            prompt: 'Which?',
            acceptedAnswers: ['This'],
            image: QuizImage(key: 'k.jpg', url: 'http://x/k.jpg', data: 'AAAA'),
          ),
        ],
      ),
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body.keys, ['quiz']);
    final quiz = body['quiz'] as Map<String, dynamic>;
    expect(quiz['title'], 'Secret');
    expect((quiz['questions'] as List).single['image'], {
      'key': null,
      'url': null,
      'alt': null,
      'data': 'AAAA',
    });
  });

  test('createRoom maps a 404 error body to GameError', () async {
    final api = RoomApi(
      baseUrl: 'http://localhost:4000/',
      client: MockClient(
        (_) async => http.Response(jsonEncode({'code': 'pack_not_found'}), 404),
      ),
    );

    await expectLater(
      api.createRoom(quizId: 'missing'),
      throwsA(isA<GameError>().having((e) => e.code, 'code', 'pack_not_found')),
    );
  });

  group('hostRoomAlive', () {
    Future<bool?> ask(
      Future<http.Response> Function(http.Request) handler, {
      void Function(http.Request)? onRequest,
    }) {
      final api = RoomApi(
        baseUrl: 'http://localhost:4000',
        client: MockClient((request) async {
          onRequest?.call(request);
          return handler(request);
        }),
      );
      return api.hostRoomAlive('K7QX2M', 'signed');
    }

    test('the token goes in a header, never the path', () async {
      late http.Request captured;
      await ask(
        (_) async => http.Response(jsonEncode({'room_code': 'K7QX2M'}), 200),
        onRequest: (request) => captured = request,
      );

      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'http://localhost:4000/api/rooms/K7QX2M');
      expect(captured.headers['x-host-token'], 'signed');
    });

    test('200 means the party is still going', () async {
      expect(
        await ask(
          (_) async => http.Response(
            jsonEncode({
              'room_code': 'K7QX2M',
              'phase': 'question',
              'players': 4,
            }),
            200,
          ),
        ),
        isTrue,
      );
    });

    test('404 is the one answer that means forget it', () async {
      expect(
        await ask(
          (_) async =>
              http.Response(jsonEncode({'code': 'room_not_found'}), 404),
        ),
        isFalse,
      );
    });

    group('says it does not know rather than guessing', () {
      test('when the network is gone', () async {
        expect(await ask((_) async => throw Exception('offline')), isNull);
      });

      test('when the server broke', () async {
        expect(await ask((_) async => http.Response('boom', 500)), isNull);
      });

      // The exact shape of a deploy in progress: the app updated before the
      // server did, and Phoenix answers 404 to a route it has never heard of.
      test('when a 404 did not come from the room itself', () async {
        expect(
          await ask(
            (_) async =>
                http.Response('{"errors":{"detail":"Not Found"}}', 404),
          ),
          isNull,
        );
      });

      test('when something in between answered', () async {
        expect(
          await ask((_) async => http.Response('<html>bad gateway', 502)),
          isNull,
        );
      });
    });
  });
}
