import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_game_connection.dart';

void main() {
  test('a fresh session does not inherit the last game ending', () async {
    final first = FakeGameConnection();
    final second = FakeGameConnection();
    final connections = [first, second];
    var built = 0;

    final container = ProviderContainer.test(
      overrides: [
        gameConnectionProvider.overrideWith((ref) => connections[built++]),
      ],
    );
    addTearDown(container.dispose);

    // Host a game, then end it. The screen learns why.
    expect(container.read(roomClosedProvider), isNull);
    first.closedCompleter.complete(RoomClosedReason.closed);
    await pumpEventQueue();
    expect(container.read(roomClosedProvider), RoomClosedReason.closed);

    // Host another. `_hostGame` builds a new connection for every session.
    container.invalidate(gameConnectionProvider);
    container.read(gameConnectionProvider);

    expect(
      container.read(roomClosedProvider),
      isNull,
      reason: 'the new room has not ended; the old one has nothing to say here',
    );
  });

  test('a late ending from a replaced connection is ignored', () async {
    final first = FakeGameConnection();
    final second = FakeGameConnection();
    final connections = [first, second];
    var built = 0;

    final container = ProviderContainer.test(
      overrides: [
        gameConnectionProvider.overrideWith((ref) => connections[built++]),
      ],
    );
    addTearDown(container.dispose);

    container.read(roomClosedProvider);
    container.invalidate(gameConnectionProvider);
    container.read(gameConnectionProvider);

    // The room the host walked out of closes half a minute later, long after
    // they started another one.
    first.closedCompleter.complete(RoomClosedReason.empty);
    await pumpEventQueue();

    expect(container.read(roomClosedProvider), isNull);

    // The session actually on screen still reports its own ending.
    second.closedCompleter.complete(RoomClosedReason.closed);
    await pumpEventQueue();
    expect(container.read(roomClosedProvider), RoomClosedReason.closed);
  });
}
