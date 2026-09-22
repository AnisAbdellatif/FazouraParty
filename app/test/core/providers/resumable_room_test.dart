import 'dart:convert';

import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/core/providers/room_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A container holding one remembered hosted room, talking to a server that
/// answers [reply] when asked whether it still exists.
({ProviderContainer container, int Function() asked}) _harness(
  Future<http.Response> Function() reply,
) {
  var asked = 0;
  final container = ProviderContainer.test(
    overrides: [
      roomApiProvider.overrideWithValue(
        RoomApi(
          baseUrl: 'http://localhost:4000',
          client: MockClient((_) async {
            asked++;
            return reply();
          }),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, asked: () => asked);
}

Future<void> _remember(ProviderContainer container) => container
    .read(roomTokensProvider.notifier)
    .saveHostToken('K7QX2M', 'signed');

http.Response _alive() => http.Response(
  jsonEncode({'room_code': 'K7QX2M', 'phase': 'lobby', 'players': 0}),
  200,
);

http.Response _gone() =>
    http.Response(jsonEncode({'code': 'room_not_found'}), 404);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('offers a room the server says is still running', () async {
    final h = _harness(() async => _alive());
    await _remember(h.container);

    final room = await h.container.read(resumableRoomProvider.future);

    expect(room?.code, 'K7QX2M');
    expect(h.asked(), 1);
  });

  test('forgets a room that has ended, rather than offering it', () async {
    final h = _harness(() async => _gone());
    await _remember(h.container);

    expect(await h.container.read(resumableRoomProvider.future), isNull);

    // Forgotten in storage, which is what the next launch reads — the button
    // never comes back.
    expect(await h.container.read(roomTokenStoreProvider).list(), isEmpty);
  });

  test('keeps the room when the server could not be reached', () async {
    // A host walking into the party with no signal yet must not lose the only
    // way back into their own room.
    final h = _harness(() async => throw Exception('offline'));
    await _remember(h.container);

    final room = await h.container.read(resumableRoomProvider.future);

    expect(room?.code, 'K7QX2M');
    expect(await h.container.read(roomTokenStoreProvider).list(), hasLength(1));
  });

  test('asks nothing when this device never hosted anything', () async {
    final h = _harness(() async => _alive());

    expect(await h.container.read(resumableRoomProvider.future), isNull);
    expect(h.asked(), 0);
  });

  test('a player token alone is not a room to take back', () async {
    final h = _harness(() async => _alive());
    await h.container
        .read(roomTokensProvider.notifier)
        .savePlayerToken('K7QX2M', 'player');

    expect(await h.container.read(resumableRoomProvider.future), isNull);
    expect(h.asked(), 0, reason: 'only a host is offered a way back');
  });
}
