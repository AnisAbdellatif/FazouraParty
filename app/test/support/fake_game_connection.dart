import 'dart:async';

import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/connection/replay_latest.dart';
import 'package:fazoura_party/core/models/models.dart';

/// In-memory [GameConnection] that records every call.
class FakeGameConnection implements GameConnection {
  FakeGameConnection({RoomState? initialState}) {
    if (initialState != null) emitState(initialState);
  }

  final ReplayLatest<RoomState> _state = ReplayLatest<RoomState>();
  final ReplayLatest<ConnectionStatus> _status = ReplayLatest<ConnectionStatus>(
    ConnectionStatus.connected,
  );
  final Completer<RoomClosedReason> closedCompleter =
      Completer<RoomClosedReason>();

  final List<({String roomCode, String displayName, String? playerToken})>
  joins = [];
  final List<String> submissions = [];
  final List<({String playerId, bool correct})> overrides = [];
  int nextCalls = 0;
  final List<String> transfers = [];
  int closeCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int leaveCalls = 0;

  /// Result returned by [join]; set [joinError] to make it throw instead.
  JoinResult joinResult = const JoinResult(
    role: Role.player,
    playerId: 'p_1',
    playerToken: 'token-1',
  );
  GameError? joinError;
  GameError? intentError;

  void emitState(RoomState state) => _state.add(state);

  @override
  Stream<RoomState> get state => _state.stream;

  @override
  Stream<ConnectionStatus> get status => _status.stream;

  @override
  Future<RoomClosedReason> get closed => closedCompleter.future;

  @override
  Future<JoinResult> join(
    String roomCode,
    String displayName, {
    String? playerToken,
  }) async {
    joins.add((
      roomCode: roomCode,
      displayName: displayName,
      playerToken: playerToken,
    ));
    if (joinError != null) throw joinError!;
    return joinResult;
  }

  final List<({String roomCode, String hostToken, String? displayName})>
  hostJoins = [];

  @override
  Future<JoinResult> joinAsHost(
    String roomCode,
    String hostToken, {
    String? displayName,
  }) async {
    hostJoins.add((
      roomCode: roomCode,
      hostToken: hostToken,
      displayName: displayName,
    ));
    if (joinError != null) throw joinError!;
    return JoinResult(
      role: Role.host,
      playerId: displayName == null ? null : 'p_host',
    );
  }

  @override
  Future<void> submit(String answer) async {
    submissions.add(answer);
    if (intentError != null) throw intentError!;
  }

  @override
  Future<void> hostNext() async => nextCalls++;

  @override
  Future<void> hostPause() async => pauseCalls++;

  @override
  Future<void> hostResume() async => resumeCalls++;

  @override
  Future<void> hostOverride(String playerId, bool correct) async {
    overrides.add((playerId: playerId, correct: correct));
    if (intentError != null) throw intentError!;
  }

  final List<({int questionCount, int timeLimitMs, bool difficultyMultiplier})>
  configures = [];
  final List<List<QuizSelection>> quizSelections = [];
  int rematchCalls = 0;

  @override
  Future<void> hostConfigure({
    required int questionCount,
    required int timeLimitMs,
    required bool difficultyMultiplier,
    List<String> difficulties = const ['easy', 'medium', 'hard'],
  }) async {
    configures.add((
      questionCount: questionCount,
      timeLimitMs: timeLimitMs,
      difficultyMultiplier: difficultyMultiplier,
    ));
    if (intentError != null) throw intentError!;
  }

  @override
  Future<void> hostSelectQuiz(List<QuizSelection> quizzes) async {
    quizSelections.add(quizzes);
    if (intentError != null) throw intentError!;
  }

  @override
  Future<void> hostRematch() async => rematchCalls++;

  @override
  Future<void> hostTransfer(String playerId) async {
    if (intentError != null) throw intentError!;
    transfers.add(playerId);
  }

  @override
  Future<void> hostClose() async {
    if (intentError != null) throw intentError!;
    closeCalls += 1;
  }

  @override
  Future<void> leave() async => leaveCalls++;
}
