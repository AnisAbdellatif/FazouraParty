import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('createRoom posts pack_id and parses the 201 reply', () async {
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
    expect(jsonDecode(captured.body), {'pack_id': 'general-knowledge'});
    expect(created, const CreatedRoom(roomCode: 'K7QX2M', hostToken: 'signed'));
  });

  test('createRoom maps a 404 error body to GameError', () async {
    final api = RoomApi(
      baseUrl: 'http://localhost:4000/',
      client: MockClient(
        (_) async => http.Response(jsonEncode({'code': 'pack_not_found'}), 404),
      ),
    );

    await expectLater(
      api.createRoom(packId: 'missing'),
      throwsA(isA<GameError>().having((e) => e.code, 'code', 'pack_not_found')),
    );
  });
}
