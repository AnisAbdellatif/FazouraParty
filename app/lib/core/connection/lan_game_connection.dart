/// LAN-mode [GameConnection] (PROTOCOL.md §2, §10).
///
/// Cloud and LAN "differ only in the socket URL and how the room is created"
/// (§10), and the LAN host speaks the same Phoenix Channels V2 protocol on the
/// wire. So this is deliberately a thin wrapper over the same socket client
/// rather than a second implementation: a real second client would be a second
/// thing to keep in step with the contract, which is the drift AGENTS.md §3
/// exists to prevent.
///
/// What differs is *where* it points and *who* starts the room:
///   - guests dial `http://<host-lan-ip>:<port>` instead of the cloud origin;
///   - the host creates the room in-process with [LanHost], with no HTTP call,
///     and then joins its own server over the loopback like any other client.
library;

import '../models/models.dart';
import 'game_connection.dart';
import 'phoenix_game_connection.dart';

class LanGameConnection implements GameConnection {
  LanGameConnection({required this.baseUrl, Duration? timeout})
    : _inner = PhoenixGameConnection(
        baseUrl: baseUrl,
        // A LAN round trip is a switch away, not an internet away. A shorter
        // timeout means a guest who typed the wrong address finds out quickly
        // instead of watching a spinner for fifteen seconds.
        timeout: timeout ?? const Duration(seconds: 5),
      );

  /// `http://<host>:<port>` of the hosting device.
  final String baseUrl;

  final PhoenixGameConnection _inner;

  /// The URL a guest can be given for [baseUrl]; `lan://` is not a real scheme.
  static String baseUrlFor(String address, int port) => 'http://$address:$port';

  @override
  Stream<RoomState> get state => _inner.state;

  @override
  Stream<ConnectionStatus> get status => _inner.status;

  @override
  Future<RoomClosedReason> get closed => _inner.closed;

  @override
  Future<JoinResult> join(
    String roomCode,
    String displayName, {
    String? playerToken,
  }) => _inner.join(roomCode, displayName, playerToken: playerToken);

  @override
  Future<JoinResult> joinAsHost(
    String roomCode,
    String hostToken, {
    String? displayName,
  }) => _inner.joinAsHost(roomCode, hostToken, displayName: displayName);

  @override
  Future<void> submit(String answer) => _inner.submit(answer);

  @override
  Future<void> hostNext() => _inner.hostNext();

  @override
  Future<void> hostPause() => _inner.hostPause();

  @override
  Future<void> hostResume() => _inner.hostResume();

  @override
  Future<void> hostOverride(String playerId, bool correct) =>
      _inner.hostOverride(playerId, correct);

  @override
  Future<void> hostConfigure({
    required int questionCount,
    required int timeLimitMs,
    required bool difficultyMultiplier,
    List<String> difficulties = const ['easy', 'medium', 'hard'],
  }) => _inner.hostConfigure(
    questionCount: questionCount,
    timeLimitMs: timeLimitMs,
    difficultyMultiplier: difficultyMultiplier,
    difficulties: difficulties,
  );

  @override
  Future<void> hostSelectQuiz(List<QuizSelection> quizzes) =>
      _inner.hostSelectQuiz(quizzes);

  @override
  Future<void> hostRematch() => _inner.hostRematch();

  @override
  Future<void> hostTransfer(String playerId) => _inner.hostTransfer(playerId);

  @override
  Future<void> hostClose() => _inner.hostClose();

  @override
  Future<void> hostSetListed(bool listed) => _inner.hostSetListed(listed);

  @override
  Future<void> hostRemovePlayer(String playerId) =>
      _inner.hostRemovePlayer(playerId);

  @override
  Future<void> leave() => _inner.leave();
}
