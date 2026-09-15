import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('createRoom posts quiz_id and parses the 201 reply', () async {
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
    expect(jsonDecode(captured.body), {'quiz_id': 'general-knowledge'});
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
}
