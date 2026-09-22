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
  /// Pass [displayName] to also play (protocol v2, PROTOCOL.md §4.1).
  Future<JoinResult> joinAsHost(
    String roomCode,
    String hostToken, {
    String? displayName,
  });

  Future<void> submit(String answer);

  Future<void> hostNext();
  Future<void> hostPause();
  Future<void> hostResume();
  Future<void> hostOverride(String playerId, bool correct);

  /// Lobby only (protocol v3, PROTOCOL.md §6.2).
  Future<void> hostConfigure({
    required int questionCount,
    required int timeLimitMs,
    required bool difficultyMultiplier,
    List<String> difficulties = const ['easy', 'medium', 'hard'],
  });

  /// Lobby only: selects or replaces the quizzes this game draws from
  /// (PROTOCOL.md §6.4). One to ten, and a selection may mix stored quizzes
  /// with documents held on this device.
  Future<void> hostSelectQuiz(List<QuizSelection> quizzes);

  /// Finished only: new game in the same room (§6.3).
  Future<void> hostRematch();

  /// Hands the host role to a connected player (§3.4). They are issued a new
  /// token; this client becomes an ordinary player.
  Future<void> hostTransfer(String playerId);

  /// Ends the room for everyone (§3.4). A host who merely leaves passes the
  /// role on instead.
  Future<void> hostClose();

  Future<void> leave();
}

/// One quiz in a host's selection (PROTOCOL.md §6.4). Either a quiz the server
/// already stores, named by id, or a document this device holds and sends
/// whole. A single selection may contain both.
sealed class QuizSelection {
  const QuizSelection();
}

/// A quiz the server stores, hosted by id. Cloud only: a LAN host has no quiz
/// database to look one up in, so it is sent as a [InlineQuizSelection].
final class StoredQuizSelection extends QuizSelection {
  const StoredQuizSelection(this.quizId);

  final String quizId;
}

/// A full quiz document, sent with the intent and never stored by the host.
final class InlineQuizSelection extends QuizSelection {
  const InlineQuizSelection(this.quiz);

  final QuizDocument quiz;
}

enum ConnectionStatus { connecting, connected, reconnecting, disconnected }

enum RoomClosedReason { empty, closed, finished, shutdown, notFound }
