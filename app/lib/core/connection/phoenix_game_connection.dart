import 'dart:async';
import 'dart:developer' as developer;

import 'package:phoenix_socket/phoenix_socket.dart';

import '../models/models.dart';
import 'game_connection.dart';
import 'replay_latest.dart';

/// Cloud-mode [GameConnection] over Phoenix Channels (PROTOCOL.md §2).
///
/// One instance serves one room session: call [join] or [joinAsHost] once,
/// then [leave]. Reconnects and heartbeats are handled by `phoenix_socket`;
/// after a player's first join the channel's join params are switched to the
/// issued `player_token` so automatic rejoins reclaim the same identity.
class PhoenixGameConnection implements GameConnection {
  PhoenixGameConnection({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 15),
    PhoenixSocket Function(String endpoint)? socketFactory,
  }) : _socketFactory = socketFactory ?? PhoenixSocket.new;

  /// What this client sends as `protocol_version`: its major, which is the
  /// whole of the compatibility check (PROTOCOL.md §1.1). A server several
  /// minors ahead still takes it.
  ///
  /// Written out rather than imported from `core/game/game.dart`, so the cloud
  /// client carries no dependency on the LAN engine. A test asserts the two
  /// agree, which is what keeps them from drifting.
  static const int protocolMajor = 9;

  /// `phx_join` payload (PROTOCOL.md §4.1).
  static Map<String, dynamic> joinPayload({
    String? displayName,
    String? playerToken,
    String? hostToken,
  }) => {
    'protocol_version': protocolMajor,
    'display_name': displayName,
    'player_token': playerToken,
    'host_token': hostToken,
  };

  /// Intent payloads (PROTOCOL.md §4.2). Kept as statics so the contract test
  /// can hold them to `protocol/fixtures` without opening a socket; the intent
  /// methods below are their only production callers.
  static Map<String, dynamic> submitPayload(String answer) => {
    'answer': answer,
  };

  static Map<String, dynamic> overridePayload(String playerId, bool correct) =>
      {'player_id': playerId, 'correct': correct};

  static Map<String, dynamic> transferPayload(String playerId) => {
    'player_id': playerId,
  };

  static Map<String, dynamic> configurePayload({
    required int questionCount,
    required int timeLimitMs,
    required bool difficultyMultiplier,
    List<String> difficulties = const ['easy', 'medium', 'hard'],
  }) => {
    'question_count': questionCount,
    'time_limit_ms': timeLimitMs,
    'difficulty_multiplier': difficultyMultiplier,
    'difficulties': difficulties,
  };

  /// The whole selection, every time: `host_select_quiz` replaces what was
  /// selected before rather than adding to it (PROTOCOL.md §6.4).
  static Map<String, dynamic> selectQuizPayload(
    List<QuizSelection> quizzes,
  ) => {
    'quizzes': [
      for (final selection in quizzes)
        switch (selection) {
          StoredQuizSelection(:final quizId) => {'quiz_id': quizId},
          // `forInlineRoom` is what turns the device's stored photo bytes into
          // the base64 the host expects (QUIZ_FORMAT.md §5.7).
          InlineQuizSelection(:final quiz) => {
            'quiz': quiz.forInlineRoom().toJson(),
          },
        },
    ],
  };

  /// HTTP(S) base URL of the server, e.g. `http://localhost:4000`.
  final String baseUrl;

  /// Timeout for connecting and for the join reply.
  final Duration timeout;

  final PhoenixSocket Function(String endpoint) _socketFactory;

  final ReplayLatest<RoomState> _state = ReplayLatest<RoomState>();
  final ReplayLatest<ConnectionStatus> _status = ReplayLatest<ConnectionStatus>(
    ConnectionStatus.disconnected,
  );
  final Completer<RoomClosedReason> _closed = Completer<RoomClosedReason>();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  PhoenixSocket? _socket;
  PhoenixChannel? _channel;
  bool _joining = false;
  bool _joined = false;
  bool _left = false;

  /// `<base>/socket/websocket?vsn=2.0.0` with an http→ws / https→wss scheme.
  static Uri socketUri(String baseUrl) {
    final base = Uri.parse(baseUrl);
    final scheme = switch (base.scheme) {
      'https' || 'wss' => 'wss',
      _ => 'ws',
    };
    var path = base.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return base.replace(
      scheme: scheme,
      path: '$path/socket/websocket',
      queryParameters: const {'vsn': '2.0.0'},
    );
  }

  @override
  Stream<RoomState> get state => _state.stream;

  @override
  Stream<ConnectionStatus> get status => _status.stream;

  @override
  Future<RoomClosedReason> get closed => _closed.future;

  @override
  Future<JoinResult> join(
    String roomCode,
    String displayName, {
    String? playerToken,
  }) {
    return _join(
      roomCode,
      joinPayload(displayName: displayName, playerToken: playerToken),
    );
  }

  @override
  Future<JoinResult> joinAsHost(
    String roomCode,
    String hostToken, {
    String? displayName,
  }) {
    return _join(
      roomCode,
      joinPayload(displayName: displayName, hostToken: hostToken),
    );
  }

  /// Payload phoenix_socket re-sends on automatic rejoins (PROTOCOL.md §4.1):
  /// players rejoin with `player_token` only, hosts with `host_token` only.
  static Map<String, dynamic> rejoinPayload(
    Map<String, dynamic> joinParams,
    JoinResult result,
  ) {
    final hostToken = joinParams['host_token'] as String?;
    if (hostToken != null) return joinPayload(hostToken: hostToken);
    return joinPayload(
      playerToken: result.playerToken ?? joinParams['player_token'] as String?,
    );
  }

  @override
  Future<void> submit(String answer) => _push('submit', submitPayload(answer));

  @override
  Future<void> hostNext() => _push('host_next', const {});

  @override
  Future<void> hostPause() => _push('host_pause', const {});

  @override
  Future<void> hostResume() => _push('host_resume', const {});

  @override
  Future<void> hostOverride(String playerId, bool correct) =>
      _push('host_override', overridePayload(playerId, correct));

  @override
  Future<void> hostConfigure({
    required int questionCount,
    required int timeLimitMs,
    required bool difficultyMultiplier,
    List<String> difficulties = const ['easy', 'medium', 'hard'],
  }) => _push(
    'host_configure',
    configurePayload(
      questionCount: questionCount,
      timeLimitMs: timeLimitMs,
      difficultyMultiplier: difficultyMultiplier,
      difficulties: difficulties,
    ),
  );

  @override
  Future<void> hostSelectQuiz(List<QuizSelection> quizzes) {
    if (quizzes.isEmpty) {
      throw ArgumentError('at least one quiz is required');
    }
    return _push('host_select_quiz', selectQuizPayload(quizzes));
  }

  @override
  Future<void> hostRematch() => _push('host_rematch', const {});

  @override
  Future<void> hostTransfer(String playerId) =>
      _push('host_transfer', transferPayload(playerId));

  @override
  Future<void> hostClose() => _push('host_close', const {});

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    final channel = _channel;
    if (channel != null && _joined) {
      try {
        await channel.leave().future.timeout(const Duration(seconds: 2));
      } on Object {
        // Best effort: the socket is disposed below either way.
      }
    }
    _teardown();
    _status.add(ConnectionStatus.disconnected);
    await _state.close();
    await _status.close();
  }

  Future<JoinResult> _join(String roomCode, Map<String, dynamic> params) async {
    if (_left) {
      throw StateError('This connection has been left.');
    }
    if (_joining || _joined) {
      throw StateError('This connection is already joined to a room.');
    }
    _joining = true;
    _status.add(ConnectionStatus.connecting);

    final socket = _socketFactory(socketUri(baseUrl).toString());
    _socket = socket;
    _subscriptions
      ..add(socket.closeStream.listen((_) => _onSocketDown()))
      ..add(socket.errorStream.listen((_) => _onSocketDown()));

    try {
      try {
        await socket.connect().timeout(timeout);
      } on TimeoutException {
        throw const GameError(
          code: GameError.connectionFailed,
          message: 'Could not reach the game server.',
        );
      }

      final channel = socket.addChannel(
        topic: 'room:$roomCode',
        parameters: params,
      );
      _channel = channel;
      _subscriptions.add(channel.messages.listen(_onChannelMessage));

      final PushResponse reply;
      try {
        reply = await channel.join().future.timeout(timeout);
      } on Object {
        throw const GameError(
          code: GameError.connectionFailed,
          message: 'The game server did not answer.',
        );
      }

      if (!reply.isOk) {
        final error = _errorFrom(reply.response);
        if (error.code == 'room_not_found') {
          _completeClosed(RoomClosedReason.notFound);
        }
        throw error;
      }

      final result = JoinResult.fromJson(_asMap(reply.response));
      // phoenix_socket re-sends channel.parameters on every automatic rejoin.
      final rejoin = rejoinPayload(params, result);
      channel.parameters
        ..clear()
        ..addAll(rejoin);
      _joined = true;
      _status.add(ConnectionStatus.connected);
      return result;
    } catch (_) {
      _teardown();
      if (!_left) _status.add(ConnectionStatus.disconnected);
      rethrow;
    } finally {
      _joining = false;
    }
  }

  Future<void> _push(String event, Map<String, dynamic> payload) async {
    final channel = _channel;
    if (channel == null || !_joined) {
      throw const GameError(
        code: GameError.notJoined,
        message: 'Not connected to a room.',
      );
    }
    final PushResponse reply;
    try {
      reply = await channel.push(event, payload).future;
    } on ChannelTimeoutException {
      throw const GameError(
        code: GameError.timeout,
        message: 'The game server did not answer.',
      );
    } on Object {
      throw const GameError(
        code: GameError.connectionFailed,
        message: 'Connection to the game server was lost.',
      );
    }
    if (!reply.isOk) {
      throw _errorFrom(reply.response);
    }
  }

  void _onChannelMessage(Message message) {
    switch (message.event.value) {
      case 'state':
        try {
          _state.add(RoomState.fromJson(_asMap(message.payload)));
        } catch (error, stackTrace) {
          developer.log(
            'Ignoring malformed state payload',
            name: 'PhoenixGameConnection',
            error: error,
            stackTrace: stackTrace,
          );
        }
      case 'room_closed':
        _completeClosed(_reasonFrom(_asMap(message.payload)['reason']));
        _shutdown();
      default:
        final channel = _channel;
        if (_joined &&
            channel != null &&
            message.event.isChannelReply &&
            message.ref != null &&
            message.ref == channel.joinRef) {
          _onRejoinReply(PushResponse.fromMessage(message));
        }
    }
  }

  /// Reply to an automatic rejoin performed by phoenix_socket after a
  /// reconnect.
  void _onRejoinReply(PushResponse reply) {
    if (reply.isOk) {
      _status.add(ConnectionStatus.connected);
      return;
    }
    if (!reply.isError) return;
    final error = _errorFrom(reply.response);
    // §4.1: a rejoin failing with invalid_token or room_not_found means the
    // room is gone; never silently re-join as someone new.
    if (error.code == 'room_not_found' || error.code == 'invalid_token') {
      _completeClosed(RoomClosedReason.notFound);
    }
    // Any rejoin error is final; stop phoenix_socket's rejoin loop.
    _shutdown();
  }

  void _onSocketDown() {
    if (_left || _closed.isCompleted) return;
    if (_joined) _status.add(ConnectionStatus.reconnecting);
  }

  void _completeClosed(RoomClosedReason reason) {
    if (!_closed.isCompleted) _closed.complete(reason);
  }

  void _shutdown() {
    _teardown();
    _status.add(ConnectionStatus.disconnected);
  }

  void _teardown() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _socket?.dispose();
    _socket = null;
    _channel = null;
    _joined = false;
  }

  static GameError _errorFrom(Object? response) {
    final map = _asMap(response);
    final code = map['code'];
    final message = map['message'];
    return GameError(
      code: code is String ? code : 'unknown_error',
      message: message is String ? message : null,
    );
  }

  static RoomClosedReason _reasonFrom(Object? reason) => switch (reason) {
    'empty' => RoomClosedReason.empty,
    'closed' => RoomClosedReason.closed,
    'finished' => RoomClosedReason.finished,
    _ => RoomClosedReason.shutdown,
  };

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}
