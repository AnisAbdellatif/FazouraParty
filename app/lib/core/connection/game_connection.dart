// Client abstraction from protocol/game_connection.dart (PROTOCOL.md §10),
// with the real model types. Any change here is a protocol change.

import '../models/models.dart';

/// Transport-agnostic connection to one game room.
///
/// Implemented by `PhoenixGameConnection` (Cloud) and `LanGameConnection` (LAN).
/// Riverpod providers must depend on this type only.
abstract interface class GameConnection {
  /// Latest complete `RoomState` snapshot pushed by the host (PROTOCOL.md §5.1).
  Stream<RoomState> get state;

  /// Socket status, for reconnect UI.
  Stream<ConnectionStatus> get status;

  /// Emits once if the room is closed or no longer exists (§5.2).
  Future<RoomClosedReason> get closed;

  /// Joins as a player. Pass [playerToken] to reclaim an earlier identity.
  /// Throws [GameError] with a join error code on failure.
  Future<JoinResult> join(
    String roomCode,
    String displayName, {
    String? playerToken,
  });

  /// Joins as the host of a room previously created with [hostToken].
  Future<JoinResult> joinAsHost(String roomCode, String hostToken);

  Future<void> submit(String answer, int wager);

  Future<void> hostNext();
  Future<void> hostPause();
  Future<void> hostResume();
  Future<void> hostOverride(String playerId, bool correct);

  Future<void> leave();
}

enum ConnectionStatus { connecting, connected, reconnecting, disconnected }

enum RoomClosedReason { hostTimeout, finished, shutdown, notFound }
