/// The LAN host: a `dart:io` WebSocket server speaking the Phoenix Channels V2
/// JSON protocol (PROTOCOL.md §2).
///
/// This is the LAN half of the contract the Phoenix endpoint implements in
/// Cloud mode. It speaks only the subset §2 requires — `phx_join`, `phx_leave`,
/// `phx_reply`, `phx_error`, `phx_close`, `heartbeat`, plus the events in §4–§5
/// — which is enough for the same `phoenix_socket` client to talk to it
/// unmodified.
///
/// Android only: a browser cannot open a listening socket, which is a platform
/// constraint rather than a design choice (assessment §4.2). Never import this
/// file directly — go through `lan_host.dart`, which stubs it out on Web.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../game/game.dart';
import '../game/lan_room.dart';
import '../game/pack.dart';

/// Default port. 0 asks the OS for a free one, which is what tests use.
const defaultLanPort = 4040;

/// Heartbeat interval is 30 s and a socket is closed after 60 s of silence
/// (§2), so a phone that sleeps is noticed rather than lingering forever.
const heartbeatTimeout = Duration(seconds: 60);

/// A room hosted on this device, reachable by other phones on the same Wi-Fi.
class LanHost {
  LanHost._(this._server, this.room, this.port, this.addresses);

  /// Starts a host for [pack] on [port] and begins accepting sockets.
  ///
  /// Binds to every interface so guests on the LAN can reach it; that is the
  /// entire point, but it does mean anyone on the network can connect, which is
  /// why the room code is the only thing gating entry.
  static Future<LanHost> start({
    Pack? pack,
    int port = defaultLanPort,
    LanRoom? room,
  }) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    server.autoCompress = false;
    final host = LanHost._(
      server,
      room ?? LanRoom.create(pack: pack ?? const Pack.empty()),
      server.port,
      await _localAddresses(),
    );
    unawaited(host._accept());
    return host;
  }

  final HttpServer _server;
  final LanRoom room;

  /// The port actually bound, which differs from the requested one when 0 was
  /// asked for.
  final int port;

  /// LAN IPv4 addresses guests can reach this host on, best first.
  final List<String> addresses;

  final Set<_LanSocket> _sockets = {};
  bool _stopped = false;

  String get roomCode => room.code;
  String get hostToken => room.hostToken;

  /// The URL a guest types or scans, e.g. `http://192.168.1.20:4040`.
  String? get joinUrl =>
      addresses.isEmpty ? null : 'http://${addresses.first}:$port';

  Future<void> _accept() async {
    try {
      await for (final request in _server) {
        if (!WebSocketTransformer.isUpgradeRequest(request) ||
            !request.uri.path.startsWith('/socket/websocket')) {
          request.response.statusCode = HttpStatus.notFound;
          unawaited(request.response.close());
          continue;
        }
        unawaited(_upgrade(request));
      }
    } on Object {
      // The server was closed underneath us; stop() owns the teardown.
    }
  }

  Future<void> _upgrade(HttpRequest request) async {
    try {
      final webSocket = await WebSocketTransformer.upgrade(request);
      final socket = _LanSocket(this, webSocket);
      _sockets.add(socket);
      socket.listen();
    } on Object {
      // A failed upgrade is the guest's problem; keep serving everyone else.
    }
  }

  void _remove(_LanSocket socket) {
    _sockets.remove(socket);
    room.leave(socket);
  }

  /// Ends the party out loud and releases the port. The room tells every client
  /// why before the sockets close, so nobody is left reconnecting into nothing.
  Future<void> stop({LanCloseReason reason = LanCloseReason.shutdown}) async {
    if (_stopped) return;
    _stopped = true;
    room.close(reason);
    for (final socket in _sockets.toList()) {
      await socket.close();
    }
    _sockets.clear();
    await _server.close(force: true);
  }

  /// Non-loopback IPv4 addresses, preferring the private ranges a home network
  /// actually uses over anything else the device happens to have.
  static Future<List<String>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final addresses = [
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      ];
      addresses.sort((a, b) {
        final byPrivate = _privateRank(a).compareTo(_privateRank(b));
        return byPrivate != 0 ? byPrivate : a.compareTo(b);
      });
      return addresses;
    } on Object {
      return const [];
    }
  }

  static int _privateRank(String address) {
    if (address.startsWith('192.168.')) return 0;
    if (address.startsWith('10.')) return 1;
    if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(address)) return 2;
    return 3;
  }
}

/// One connected guest. Implements [LanConnection] so the room can push to it
/// without knowing it is a socket.
class _LanSocket implements LanConnection {
  _LanSocket(this._host, this._webSocket);

  final LanHost _host;
  final WebSocket _webSocket;

  /// Set once the client joins the room topic; every later frame is checked
  /// against it, so a client cannot push on a topic it never joined.
  String? _topic;
  String? _joinRef;
  Timer? _idleTimer;
  bool _closing = false;

  void listen() {
    _resetIdleTimer();
    _webSocket.listen(
      _onFrame,
      onDone: _onDone,
      onError: (_, _) => _onDone(),
      cancelOnError: true,
    );
  }

  /// A socket that has gone quiet past the heartbeat window is gone, whatever
  /// TCP thinks (§2).
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(heartbeatTimeout, () => unawaited(close()));
  }

  void _onFrame(Object? raw) {
    _resetIdleTimer();
    if (raw is! String) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return; // Not our protocol; ignore rather than kill the socket.
    }
    // V2 frames are [join_ref, ref, topic, event, payload] (§2).
    if (decoded is! List || decoded.length < 5) return;

    final joinRef = decoded[0] as String?;
    final ref = decoded[1] as String?;
    final topic = decoded[2] as String?;
    final event = decoded[3] as String?;
    final payload = decoded[4];

    if (topic == null || event == null) return;

    if (topic == 'phoenix' && event == 'heartbeat') {
      _reply(null, ref, topic, ok: true, response: const {});
      return;
    }

    switch (event) {
      case 'phx_join':
        _onJoin(joinRef, ref, topic, _asMap(payload));
      case 'phx_leave':
        _reply(joinRef, ref, topic, ok: true, response: const {});
        unawaited(close());
      default:
        _onIntent(joinRef, ref, topic, event, _asMap(payload));
    }
  }

  void _onJoin(
    String? joinRef,
    String? ref,
    String topic,
    Map<String, dynamic> payload,
  ) {
    if (topic != 'room:${_host.roomCode}') {
      _replyError(joinRef, ref, topic, 'room_not_found');
      return;
    }
    // A second join on the same socket would leave the room holding two actors
    // for one connection; the client never does this.
    if (_topic != null) {
      _replyError(joinRef, ref, topic, 'invalid_payload');
      return;
    }

    try {
      final reply = _host.room.join(this, payload);
      _topic = topic;
      _joinRef = joinRef;
      _reply(
        joinRef,
        ref,
        topic,
        ok: true,
        response: {
          'role': reply.role,
          'player_id': reply.playerId,
          'player_token': reply.playerToken,
        },
      );
      // The room pushed a snapshot during join, before _topic was set, so send
      // this client its own view now that it can be addressed (§4.1).
      pushState(
        _host.room.game.view(
          reply.role == 'host'
              ? const HostActor()
              : PlayerActor(reply.playerId!),
          DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } on GameRuleError catch (error) {
      _replyError(joinRef, ref, topic, error.code);
    }
  }

  void _onIntent(
    String? joinRef,
    String? ref,
    String topic,
    String event,
    Map<String, dynamic> payload,
  ) {
    if (_topic == null || topic != _topic) {
      _replyError(joinRef, ref, topic, 'invalid_token');
      return;
    }
    try {
      _host.room.handle(this, event, payload);
      _reply(joinRef, ref, topic, ok: true, response: const {});
    } on GameRuleError catch (error) {
      _replyError(joinRef, ref, topic, error.code);
    }
  }

  @override
  void pushState(Map<String, dynamic> state) {
    final topic = _topic;
    if (topic == null) return;
    _send([_joinRef, null, topic, 'state', state]);
  }

  @override
  void pushClosed(String reason) {
    final topic = _topic;
    if (topic == null) return;
    _send([
      _joinRef,
      null,
      topic,
      'room_closed',
      {'reason': reason},
    ]);
    unawaited(close());
  }

  void _reply(
    String? joinRef,
    String? ref,
    String topic, {
    required bool ok,
    required Map<String, dynamic> response,
  }) {
    _send([
      joinRef,
      ref,
      topic,
      'phx_reply',
      {'status': ok ? 'ok' : 'error', 'response': response},
    ]);
  }

  void _replyError(String? joinRef, String? ref, String topic, String code) {
    _reply(
      joinRef,
      ref,
      topic,
      ok: false,
      response: {'code': code, 'message': lanErrorMessage(code)},
    );
  }

  void _send(List<Object?> frame) {
    if (_closing) return;
    try {
      _webSocket.add(jsonEncode(frame));
    } on Object {
      // The socket died between the check and the write; _onDone cleans up.
    }
  }

  void _onDone() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _host._remove(this);
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    try {
      await _webSocket.close();
    } on Object {
      // Already gone.
    }
    _host._remove(this);
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

/// Human-readable text for an error code, matching the Cloud host's wording
/// (`FazouraWeb.RoomChannel`). Clients branch on `code` only (§4.2), so this is
/// for logs and fallback UI.
String lanErrorMessage(String code) => switch (code) {
  'unsupported_protocol_version' =>
    'This app version is not compatible with the server.',
  'room_not_found' => "That room doesn't exist or has ended.",
  'invalid_token' => 'Your session for this room is no longer valid.',
  'invalid_name' => 'Names must be 1–20 characters.',
  'name_taken' => 'Someone in the room already has that name.',
  'room_full' => 'This room is full.',
  'invalid_phase' => "That can't be done right now.",
  'not_host' => 'Only the host can do that.',
  'not_player' => 'Only players can do that.',
  'invalid_answer' => 'Answers must be 1–100 characters.',
  'invalid_wager' => 'Wager must be a whole number from 1 to 10.',
  'already_submitted' => 'You already answered this question.',
  'unknown_player' => 'No such player in this room.',
  'no_submission' => "That player didn't answer this question.",
  'paused' => 'The timer is paused.',
  'not_paused' => "The timer isn't paused.",
  'invalid_settings' =>
    'Choose 1 question up to the pack size, and 10–120 seconds per question.',
  'quiz_required' => 'Choose a quiz before starting the game.',
  'empty_pack' => 'That quiz has no playable questions.',
  _ => 'Malformed request.',
};
