import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/room_api.dart';
import '../connection/game_connection.dart';
import '../connection/lan_game_connection.dart';
import '../connection/phoenix_game_connection.dart';
import '../models/models.dart';
import '../time/server_clock.dart';
import 'config_providers.dart';
import 'lan_providers.dart';

part 'connection_providers.g.dart';

@Riverpod(keepAlive: true)
RoomApi roomApi(Ref ref) {
  final api = RoomApi(baseUrl: ref.watch(serverBaseUrlProvider));
  ref.onDispose(api.close);
  return api;
}

/// The connection for the current room session. This is the only place that
/// names a concrete transport; everything else depends on [GameConnection].
///
/// Which one it builds follows [currentGameTargetProvider], so a LAN game and a
/// cloud game are the same code path above this line (PROTOCOL.md §10).
///
/// Invalidate it to start a fresh session (disposal leaves the room).
@Riverpod(keepAlive: true)
GameConnection gameConnection(Ref ref) {
  final connection = switch (ref.watch(currentGameTargetProvider)) {
    CloudTarget() => PhoenixGameConnection(
      baseUrl: ref.watch(serverBaseUrlProvider),
    ),
    LanTarget(:final baseUrl) => LanGameConnection(baseUrl: baseUrl),
  };
  ref.onDispose(() => unawaited(connection.leave()));
  return connection;
}

@Riverpod(keepAlive: true)
Stream<RoomState> roomState(Ref ref) => ref.watch(gameConnectionProvider).state;

@Riverpod(keepAlive: true)
Stream<ConnectionStatus> connectionStatus(Ref ref) =>
    ref.watch(gameConnectionProvider).status;

/// Why the current room ended, or null while it is still running.
///
/// A plain value rather than an `AsyncValue`, and that is the whole point: an
/// `AsyncValue` keeps its last data while it refreshes, so hosting a second
/// game handed the new session the *previous* game's ending on its first
/// frame. The room opened straight onto "the host ended the party", and the
/// listener that forgets a dead room threw away the new room's host token on
/// the way past. A restart cleared it, which is what made it look intermittent.
///
/// Building a new connection resets this to null synchronously, so there is no
/// frame in which the old answer is visible.
@Riverpod(keepAlive: true)
class RoomClosed extends _$RoomClosed {
  @override
  RoomClosedReason? build() {
    final connection = ref.watch(gameConnectionProvider);

    // `onDispose` runs before each rebuild as well as at the end, so a late
    // answer from a connection that has since been replaced cannot land on the
    // session that replaced it.
    var current = true;
    ref.onDispose(() => current = false);

    unawaited(
      connection.closed.then(
        (reason) {
          if (current) state = reason;
        },
        // A connection that never says why is the same as one still running:
        // the screens have nothing to show and nothing to forget.
        onError: (Object _) {},
      ),
    );

    return null;
  }
}

/// `server_time - local_now`, recomputed whenever a new snapshot arrives.
@Riverpod(keepAlive: true)
int serverClockOffset(Ref ref) {
  final snapshot = ref.watch(roomStateProvider).value;
  if (snapshot == null) return 0;
  final now = ref.watch(clockProvider)();
  return clockOffsetMs(
    serverTime: snapshot.serverTime,
    localNowMs: now.millisecondsSinceEpoch,
  );
}
