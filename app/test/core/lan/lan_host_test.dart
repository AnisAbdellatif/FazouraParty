/// The LAN host as a guest meets it: a real socket speaking Phoenix Channels
/// V2, and a real HTTP request for a question photo.
///
/// `lan_room_test.dart` and `protocol_scenarios_test.dart` cover the rules
/// underneath. What is left here is the transport — framing, topics, the one
/// HTTP route — which is the half a fake connection cannot exercise, and the
/// half the `phoenix_socket` client actually talks to (PROTOCOL.md §2).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fazoura_party/core/game/game.dart';
import 'package:fazoura_party/core/lan/lan_host_io.dart';
import 'package:fazoura_party/core/game/pack.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List pngBytes() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

Map<String, dynamic> photoQuiz(Uint8List photo) => {
  'format_version': 1,
  'title': 'Photo Quiz',
  'tags': ['fixture'],
  'questions': [
    {
      'id': 'q1',
      'type': 'text_photo',
      'prompt': 'What is this?',
      'accepted_answers': ['Right'],
      'time_limit_ms': 30000,
      'image': {'data': base64Encode(photo), 'alt': 'a photo'},
    },
  ],
};

/// A guest socket, framing V2 messages the way `phoenix_socket` does.
class _Guest {
  _Guest(this._socket) {
    _socket.listen((raw) {
      final frame = jsonDecode(raw as String) as List;
      final event = frame[3] as String;
      final payload = frame[4];
      switch (event) {
        case 'phx_reply':
          _replies
              .remove(frame[1] as String)
              ?.complete(payload as Map<String, dynamic>);
        case 'state':
          latestState = payload as Map<String, dynamic>;
          stateCount += 1;
        case 'room_closed':
          closedReason = (payload as Map)['reason'] as String?;
      }
    });
  }

  static Future<_Guest> connect(int port) async =>
      _Guest(await WebSocket.connect('ws://127.0.0.1:$port/socket/websocket'));

  final WebSocket _socket;
  final Map<String, Completer<Map<String, dynamic>>> _replies = {};

  Map<String, dynamic>? latestState;
  String? closedReason;

  /// How many snapshots have arrived. A reply and the snapshot it causes are
  /// two frames, and nothing orders them for the reader, so tests wait for the
  /// count to move rather than for a stream event they may have missed.
  int stateCount = 0;
  int _ref = 0;

  Future<Map<String, dynamic>> nextState(int since) async {
    await _until(() => stateCount > since);
    expect(stateCount, greaterThan(since), reason: 'no snapshot arrived');
    return latestState!;
  }

  Future<Map<String, dynamic>> send(
    String topic,
    String event,
    Map<String, dynamic> payload,
  ) {
    final ref = '${_ref++}';
    final completer = Completer<Map<String, dynamic>>();
    _replies[ref] = completer;
    _socket.add(jsonEncode(['1', ref, topic, event, payload]));
    return completer.future.timeout(const Duration(seconds: 5));
  }

  Future<Map<String, dynamic>> join(String code, Map<String, dynamic> params) =>
      send('room:$code', 'phx_join', {
        'protocol_version': protocolMajor,
        ...params,
      });

  Future<void> close() => _socket.close();
}

Future<HttpClientResponse> get(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    return await request.close();
  } finally {
    client.close(force: false);
  }
}

void main() {
  late LanHost host;

  setUp(() async {
    // Port 0: the OS picks a free one, so tests never collide.
    host = await LanHost.start(pack: const Pack.empty(), port: 0);
  });

  tearDown(() => host.stop());

  group('sockets', () {
    test('a guest joins, plays and is pushed snapshots', () async {
      final hostGuest = await _Guest.connect(host.port);
      final sam = await _Guest.connect(host.port);

      final hostReply = await hostGuest.join(host.roomCode, {
        'host_token': host.hostToken,
      });
      expect(hostReply['status'], 'ok');
      expect((hostReply['response'] as Map<String, dynamic>)['role'], 'host');

      final samReply = await sam.join(host.roomCode, {'display_name': 'Sam'});
      expect(samReply['status'], 'ok');
      final samResponse = samReply['response'] as Map<String, dynamic>;
      expect(samResponse['role'], 'player');
      expect(samResponse['player_token'], isNotNull);

      // Every joiner is sent its own snapshot straight away (§4.1).
      final snapshot = await sam.nextState(0);
      expect(snapshot['room_code'], host.roomCode);
      expect(snapshot['mode'], 'lan');

      final selected = await hostGuest.send(
        'room:${host.roomCode}',
        'host_select_quiz',
        {
          'quizzes': [
            {'quiz': photoQuiz(pngBytes())},
          ],
        },
      );
      expect(selected['status'], 'ok');

      final before = hostGuest.stateCount;
      await hostGuest.send('room:${host.roomCode}', 'host_next', {});
      expect((await hostGuest.nextState(before))['phase'], 'question');

      await hostGuest.close();
      await sam.close();
    });

    test('joining the wrong topic is room_not_found', () async {
      final guest = await _Guest.connect(host.port);
      final reply = await guest.join('NOPE42', {'display_name': 'Sam'});

      expect(reply['status'], 'error');
      expect((reply['response'] as Map)['code'], 'room_not_found');
      await guest.close();
    });

    test('an error reply carries a human message beside the code', () async {
      final guest = await _Guest.connect(host.port);
      final reply = await guest.join(host.roomCode, {'display_name': ''});

      expect((reply['response'] as Map)['code'], 'invalid_name');
      expect((reply['response'] as Map)['message'], isNotEmpty);
      await guest.close();
    });

    test('a push before joining is refused rather than acted on', () async {
      final guest = await _Guest.connect(host.port);
      final reply = await guest.send('room:${host.roomCode}', 'host_next', {});

      expect(reply['status'], 'error');
      expect((reply['response'] as Map)['code'], 'invalid_token');
      expect(host.room.game.phase, GamePhase.lobby);
      await guest.close();
    });

    test('heartbeats are answered so the socket is kept alive', () async {
      final guest = await _Guest.connect(host.port);
      final reply = await guest.send('phoenix', 'heartbeat', {});

      expect(reply['status'], 'ok');
      await guest.close();
    });

    test(
      'stopping the host tells every client before the socket dies',
      () async {
        final guest = await _Guest.connect(host.port);
        await guest.join(host.roomCode, {'display_name': 'Sam'});

        await host.stop();
        await _until(() => guest.closedReason != null);

        expect(guest.closedReason, 'shutdown');
      },
    );

    test('a guest who drops is noticed', () async {
      final guest = await _Guest.connect(host.port);
      final reply = await guest.join(host.roomCode, {'display_name': 'Sam'});
      final id =
          (reply['response'] as Map<String, dynamic>)['player_id'] as String;
      expect(host.room.game.players[id]!.connected, isTrue);

      await guest.close();
      await _until(() => host.room.game.players[id]!.connected == false);
      expect(host.room.game.players[id]!.connected, isFalse);
    });
  });

  group('question photos', () {
    late String imageUrl;
    late Uint8List photo;

    setUp(() async {
      photo = pngBytes();
      final guest = await _Guest.connect(host.port);
      await guest.join(host.roomCode, {'host_token': host.hostToken});
      await guest.send('room:${host.roomCode}', 'host_select_quiz', {
        'quizzes': [
          {'quiz': photoQuiz(photo)},
        ],
      });
      final before = guest.stateCount;
      await guest.send('room:${host.roomCode}', 'host_next', {});
      final state = await guest.nextState(before);

      imageUrl =
          (state['question'] as Map<String, dynamic>)['image_url'] as String;
      await guest.close();
    });

    test(
      'the URL in the snapshot points at this host and serves the bytes',
      () async {
        // The snapshot gives guests a LAN address; the test reaches the same
        // server over loopback, which is the same socket.
        expect(
          imageUrl,
          endsWith('/api/room-images/${imageUrl.split('/').last}'),
        );
        final key = imageUrl.split('/').last;

        final response = await get(
          'http://127.0.0.1:${host.port}/api/room-images/$key',
        );
        expect(response.statusCode, 200);
        expect(
          response.headers.contentType.toString(),
          startsWith('image/png'),
        );

        final bytes = await _collect(response);
        expect(bytes, photo);
      },
    );

    test(
      'photos are served with the headers user content gets on Cloud',
      () async {
        final key = imageUrl.split('/').last;
        final response = await get(
          'http://127.0.0.1:${host.port}/api/room-images/$key',
        );
        await _collect(response);

        // Matches `FazouraWeb.Plugs.UserContent`: believe the declared type,
        // never a download, opaque origin if navigated to directly.
        expect(response.headers.value('x-content-type-options'), 'nosniff');
        expect(response.headers.value('content-disposition'), 'inline');
        expect(
          response.headers.value('content-security-policy'),
          "sandbox; default-src 'none'",
        );
        expect(
          response.headers.value('cache-control'),
          'private, max-age=3600',
        );
      },
    );

    test('an unknown key is a 404, not a hint', () async {
      for (final path in [
        '/api/room-images/nope.png',
        '/api/room-images/',
        '/api/room-images/../../etc/passwd',
        '/uploads/anything.png',
        '/',
      ]) {
        final response = await get('http://127.0.0.1:${host.port}$path');
        await _collect(response);
        expect(response.statusCode, 404, reason: path);
      }
    });

    test('a photo is gone once the room is', () async {
      final key = imageUrl.split('/').last;
      final port = host.port;
      await host.stop();

      await expectLater(
        get('http://127.0.0.1:$port/api/room-images/$key'),
        throwsA(isA<SocketException>()),
      );
    });
  });
}

Future<Uint8List> _collect(HttpClientResponse response) async {
  final builder = BytesBuilder();
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Waits for a condition the host reaches on its own, e.g. a socket teardown
/// that arrives a microtask or two after the client hangs up.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
