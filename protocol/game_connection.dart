// Reference copy of the frozen client abstraction (PROTOCOL.md §10).
// The Flutter app implements this in lib/core/connection/; keep the two in sync.
// Any change here is a protocol change.

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
  Future<JoinResult> join(String roomCode, String displayName, {String? playerToken});

  /// Joins as the host of a room previously created with [hostToken].
  /// Pass [displayName] for the host to also play (PROTOCOL.md §4.1).
  Future<JoinResult> joinAsHost(String roomCode, String hostToken, {String? displayName});

  Future<void> submit(String answer);

  Future<void> hostNext();
  Future<void> hostPause();
  Future<void> hostResume();
  Future<void> hostOverride(String playerId, bool correct);

  /// Lobby only (PROTOCOL.md §6.2).
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

  /// Hands the host role to a connected player (§3.4). The room issues them a
  /// new `host_token`; this client becomes an ordinary player.
  Future<void> hostTransfer(String playerId);

  /// Ends the room for everyone (§3.4). Without this a host who simply leaves
  /// passes the role on instead.
  Future<void> hostClose();

  /// Lobby only: puts the room on the public list, or takes it off (§3.5).
  Future<void> hostSetListed(bool listed);

  /// Takes a player out of the room (§4.2).
  Future<void> hostRemovePlayer(String playerId);

  /// Any phase: how many players the room lets in, from the players already
  /// here up to `room_size_limit` (§6.5). Refused with `invalid_room_size`.
  Future<void> hostSetRoomSize(int roomSize);

  /// Raises the room's limit with a room size code an admin handed out, and
  /// grows the room to it (§6.5). Refused with `invalid_code`, `code_expired`
  /// or `code_used_up`, and with `cloud_only` by a LAN host.
  Future<void> hostRedeemSizeCode(String code);

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

  final Object quiz;
}

enum ConnectionStatus { connecting, connected, reconnecting, disconnected }

enum RoomClosedReason { empty, closed, finished, shutdown, notFound }

/// Placeholders — the real, freezed models live in the app.
abstract class RoomState {}

abstract class JoinResult {}

abstract class GameError implements Exception {
  String get code;
}
