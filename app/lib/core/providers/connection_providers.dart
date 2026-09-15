import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/room_api.dart';
import '../connection/game_connection.dart';
import '../connection/phoenix_game_connection.dart';
import '../models/models.dart';
import '../time/server_clock.dart';
import 'config_providers.dart';

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
/// Invalidate it to start a fresh session (disposal leaves the room).
@Riverpod(keepAlive: true)
GameConnection gameConnection(Ref ref) {
  final connection = PhoenixGameConnection(
    baseUrl: ref.watch(serverBaseUrlProvider),
  );
  ref.onDispose(() => unawaited(connection.leave()));
  return connection;
}

@Riverpod(keepAlive: true)
Stream<RoomState> roomState(Ref ref) => ref.watch(gameConnectionProvider).state;

@Riverpod(keepAlive: true)
Stream<ConnectionStatus> connectionStatus(Ref ref) =>
    ref.watch(gameConnectionProvider).status;

@Riverpod(keepAlive: true)
Future<RoomClosedReason> roomClosed(Ref ref) =>
    ref.watch(gameConnectionProvider).closed;

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
