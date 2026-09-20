/// The shell around [Game] for a LAN-hosted room.
///
/// Dart counterpart of `server/lib/fazoura/rooms/room_server.ex`: it owns the
/// state, supplies the clock, tracks connections, issues tokens and pushes a
/// per-recipient snapshot to every client after each change.
///
/// Transport-agnostic on purpose — it knows nothing about WebSockets. The
/// server ([LanHost]) adapts sockets onto [LanConnection], which keeps the game
/// testable without opening a port.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'game.dart';
import 'lan_images.dart';
import 'pack.dart';
import '../models/quiz.dart';

/// Room codes avoid I, O, 0 and 1 (PROTOCOL.md §3.2).
const roomCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const roomCodeLength = 6;

/// A room with nobody in it closes after 30 seconds; a finished one after 10
/// minutes (PROTOCOL.md §3.2, §3.4).
const emptyTtl = Duration(seconds: 30);
const finishedTtl = Duration(minutes: 10);

/// Why a room ended (§5.2).
enum LanCloseReason {
  empty,
  closed,
  finished,
  shutdown;

  String get wire => name;
}

/// One joined client, from the room's point of view. The transport implements
/// this; the room only ever pushes to it.
abstract interface class LanConnection {
  void pushState(Map<String, dynamic> state);
  void pushClosed(String reason);
}

/// The reply to a successful join (§4.1).
typedef LanJoinReply = ({String role, String? playerId, String? playerToken});

class LanRoom {
  LanRoom({
    required this.code,
    required Pack pack,
    required this.hostToken,
    int Function()? now,
    Random? random,
    this.imageBaseUrl,
    bool shuffleQuestions = true,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _random = random ?? Random.secure(),
       images = LanImages(random: random),
       game = Game(
         roomCode: code,
         pack: pack,
         shuffleQuestions: shuffleQuestions,
       ) {
    _emptySince = _now();
    _schedule();
  }

  /// Creates a room with a fresh code and host token.
  factory LanRoom.create({
    required Pack pack,
    int Function()? now,
    Random? random,
    String? imageBaseUrl,
    bool shuffleQuestions = true,
  }) {
    final rng = random ?? Random.secure();
    return LanRoom(
      code: generateRoomCode(rng),
      pack: pack,
      hostToken: _opaqueToken(rng, 'h'),
      now: now,
      random: rng,
      imageBaseUrl: imageBaseUrl,
      shuffleQuestions: shuffleQuestions,
    );
  }

  final String code;
  final String hostToken;
  final Game game;

  /// The selected quiz's photos, served by the transport (§5.7).
  final LanImages images;

  /// Origin the host is reachable on, e.g. `http://192.168.1.20:4040`. Set by
  /// [LanHost] once it knows which port and address it bound, because a guest
  /// has to be able to fetch a photo from it.
  String? imageBaseUrl;

  final int Function() _now;
  final Random _random;

  final Map<LanConnection, Actor> _connections = {};
  final Map<String, String> _playerTokens = {};

  int? _emptySince;
  // Whether the connection that authenticated with the host token still holds
  // the role, and which player it plays as once it does not.
  bool _heldByHostConn = true;
  String? _demotedPlayerId;
  // The only token that authenticates as host. Replaced on every change of
  // role, which is what retires the previous holder's copy (§3.3). Cloud uses a
  // signed generation counter; here the room holds the string itself, so a new
  // random one is the same thing.
  late String _currentHostToken = hostToken;
  // Players owed a fresh host token in their next snapshot. Cleared once sent.
  final Map<String, String> _pendingTokens = {};
  int? _finishedAt;
  Timer? _timer;
  bool _closed = false;

  /// Completes when the room ends, with the reason clients were told.
  Future<LanCloseReason> get closed => _closedCompleter.future;
  final Completer<LanCloseReason> _closedCompleter = Completer();

  bool get isClosed => _closed;
  int get connectionCount => _connections.length;

  static String generateRoomCode(Random random) => List.generate(
    roomCodeLength,
    (_) => roomCodeAlphabet[random.nextInt(roomCodeAlphabet.length)],
  ).join();

  /// Opaque, unguessable and scoped to this room. Unlike Cloud, a LAN host has
  /// no secret key base to sign with and no need for one: the token never
  /// leaves the device that issued it, so 192 bits of randomness held in memory
  /// is the whole mechanism (§3.3 — tokens are opaque to clients).
  static String _opaqueToken(Random random, String prefix) {
    final bytes = List.generate(24, (_) => random.nextInt(256));
    return '${prefix}_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  String _newPlayerId() => _opaqueToken(_random, 'p').substring(0, 14);

  // --- Joining -------------------------------------------------------------

  /// Authenticates and registers [connection]. Throws [GameRuleError] with a
  /// join error code (§4.1); the caller replies with it and does not connect.
  LanJoinReply join(LanConnection connection, Map<String, dynamic> params) {
    if (_closed) throw const GameRuleError('room_not_found');
    if (params['protocol_version'] != protocolVersion) {
      throw const GameRuleError('unsupported_protocol_version');
    }

    final reply = _authenticate(params);
    final actor = reply.role == 'host'
        ? const HostActor()
        : PlayerActor(reply.playerId!);

    _connections[connection] = actor;
    _emptySince = null;
    switch (actor) {
      case HostActor():
        game.setConnected(game.hostPlayerId, true);
      case PlayerActor(:final id):
        game.setConnected(id, true);
    }

    _broadcast();
    _schedule();
    return reply;
  }

  LanJoinReply _authenticate(Map<String, dynamic> params) {
    final host = params['host_token'];
    if (host is String) {
      // Only the current token: every transfer mints a new one, so a former
      // host cannot take the room back (§3.3).
      if (host != _currentHostToken) throw const GameRuleError('invalid_token');
      // A host join carrying a name makes the host play too; ignored once the
      // host already plays, so reconnects need only the host token (§4.1).
      final name = params['display_name'];
      if (name != null && game.hostPlayerId == null) {
        game.addHostPlayer(
          _newPlayerId(),
          name,
          avatarHue: game.pickAvatarHue(_random),
        );
      }
      return (role: 'host', playerId: game.hostPlayerId, playerToken: null);
    }

    final playerToken = params['player_token'];
    if (playerToken is String) {
      final id = _playerTokens[playerToken];
      // A token for a player who is no longer here is as good as invalid: the
      // client must drop it rather than silently rejoin as someone new (§4.1).
      if (id == null || !game.hasPlayer(id)) {
        throw const GameRuleError('invalid_token');
      }
      return (role: 'player', playerId: id, playerToken: playerToken);
    }

    final id = _newPlayerId();
    game.addPlayer(
      id,
      params['display_name'],
      avatarHue: game.pickAvatarHue(_random),
    );
    final token = _opaqueToken(_random, 't');
    _playerTokens[token] = id;
    return (role: 'player', playerId: id, playerToken: token);
  }

  /// Drops a connection. The player stays in the room, marked disconnected,
  /// and keeps their score (§4.2).
  void leave(LanConnection connection) {
    final actor = _connections.remove(connection);
    if (actor == null || _closed) return;

    // Another socket may still be acting as the same player.
    final stillPresent = _connections.values.any(
      (other) => switch ((other, actor)) {
        (HostActor(), HostActor()) => true,
        (PlayerActor(id: final a), PlayerActor(id: final b)) => a == b,
        _ => false,
      },
    );
    if (stillPresent) return;

    switch (actor) {
      case HostActor():
        game.setConnected(game.hostPlayerId, false);
        _promoteHost();
      case PlayerActor(:final id):
        game.setConnected(id, false);
    }
    if (_connections.isEmpty) _emptySince = _now();
    _broadcast();
    _schedule();
  }

  /// The host's connection is gone: rather than leave the room hostless until
  /// it times out, hand the role to someone still here (PROTOCOL.md §3.4).
  void _promoteHost() {
    final candidates = _connectedPlayerIds();
    if (candidates.isEmpty) return;
    _grantHost(
      candidates[_random.nextInt(candidates.length)],
      game.hostPlayerId,
    );
  }

  /// Moves the role to [playerId] and mints their token. The generation bump is
  /// what retires every token issued before this point.
  ///
  /// [outgoing] is who held the role *before* this call — passed in rather
  /// than read from the game, because unlike the Elixir version this port
  /// mutates in place, so by the time a transfer gets here the game may
  /// already name the new holder. Getting it wrong would leave the demoted
  /// host looking at the new host's own view (§3.4, §7).
  void _grantHost(String playerId, String? outgoing) {
    _demotedPlayerId ??= outgoing;
    _heldByHostConn = false;
    _currentHostToken = _opaqueToken(_random, 'h');
    game.hostPlayerId = playerId;
    _pendingTokens[playerId] = _currentHostToken;
  }

  List<String> _connectedPlayerIds() => [
    for (final actor in _connections.values)
      if (actor is PlayerActor) actor.id,
  ];

  // --- Intents -------------------------------------------------------------

  /// Applies an intent from [connection]. Throws [GameRuleError] on refusal.
  void handle(
    LanConnection connection,
    String event,
    Map<String, dynamic> payload,
  ) {
    if (_closed) throw const GameRuleError('room_not_found');
    final actor = _connections[connection];
    if (actor == null) throw const GameRuleError('invalid_token');

    final now = _now();

    // Ending the room is the shell's business: no state to advance, only
    // sockets to tell (PROTOCOL.md §3.4).
    if (event == 'host_close') {
      // The host *connection*, not merely whoever holds the role: a connection
      // that has handed the role away is an ordinary client, and a promoted
      // player closes the room by the same route Cloud gives them — none
      // (`FazouraWeb.RoomChannel` → `Rooms.intent/3`).
      if (_recipient(actor) case HostActor(holder: true)) {
        close(LanCloseReason.closed);
        return;
      }
      throw const GameRuleError('not_host');
    }

    if (event == 'host_transfer') {
      _handleTransfer(actor, payload, now);
      return;
    }

    if (event == 'host_select_quiz') {
      _handleSelectQuiz(actor, payload, now);
      return;
    }

    // Expire the question first, so a submit can't land after time is up even
    // if the timer callback hasn't run yet.
    game.tick(now);
    game.handle(_recipient(actor), event, payload, now);

    _afterChange(now);
  }

  /// Replaces the lobby's quiz. Cloud resolves either a stored `quiz_id` or a
  /// full inline document; a LAN host has no quiz database and no internet, so
  /// only the document means anything to it — the wire contract is the same
  /// either way (PROTOCOL.md §4.2).
  ///
  /// The photos travel inside that document as base64, so this is also where
  /// they are taken out and stored for the transport to serve (§5.7).
  void _handleSelectQuiz(Actor actor, Map<String, dynamic> payload, int now) {
    // Whoever holds the role may choose, including a promoted player: the same
    // two ways in that `Fazoura.Rooms.RoomServer` accepts `:select_quiz`.
    if (!_holdsHostRole(_recipient(actor))) {
      throw const GameRuleError('not_host');
    }

    final document = payload['quiz'];
    if (document is! Map<String, dynamic>) {
      throw const GameRuleError('invalid_quiz');
    }

    final QuizDocument quiz;
    try {
      quiz = QuizDocument.fromJson(document);
    } on Object {
      throw const GameRuleError('invalid_quiz');
    }

    // Store the photos only once the quiz is accepted: `selectQuiz` refuses an
    // empty pack or a game already under way, and a refused selection must
    // leave the room exactly as it was, photos included.
    final prepared = images.prepare(quiz);
    game.selectQuiz(Pack.fromQuiz(prepared.quiz, imageUrl: _imageUrl));
    images.commit(prepared.images);
    _afterChange(now);
  }

  /// Where a guest fetches a photo of the selected quiz. Mirrors Cloud's
  /// `/api/room-images/<key>`, so the two differ only in the origin.
  String _imageUrl(String key) => '${imageBaseUrl ?? ''}/api/room-images/$key';

  /// Whether [recipient] may act as the host: the host connection while it
  /// still holds the role, or the player it was handed to (§3.4).
  bool _holdsHostRole(Actor recipient) => switch (recipient) {
    HostActor(:final holder) => holder,
    PlayerActor(:final id) => id == game.hostPlayerId,
  };

  void _handleTransfer(Actor actor, Map<String, dynamic> payload, int now) {
    final target = payload['player_id'];
    if (target is! String) throw const GameRuleError('invalid_payload');
    // Handing the role to someone who has left would leave the room hostless,
    // which is what promotion exists to prevent.
    if (!_connectedPlayerIds().contains(target)) {
      throw const GameRuleError('not_connected');
    }
    // Who is handing it over, read before the game is touched: `host_transfer`
    // moves the role inside the game state, so afterwards it is too late to
    // ask.
    final outgoing = game.hostPlayerId;
    game.handle(_recipient(actor), 'host_transfer', payload, now);
    _grantHost(target, outgoing);
    _afterChange(now);
  }

  void _afterChange(int now) {
    // A rematch leaves `finished`, which cancels the finished-room expiry.
    if (game.phase != GamePhase.finished) {
      _finishedAt = null;
    } else {
      _finishedAt ??= now;
    }
    _broadcast();
    _schedule();
  }

  // --- Timers --------------------------------------------------------------

  /// Advances the room to [_now]: ends a question whose deadline has passed
  /// and closes a room that has sat empty or finished for too long.
  ///
  /// Called by the room's own timer in a real game, and directly by tests
  /// driving an injected clock — the same seam `Fazoura.Rooms.tick/1` is.
  void tick() => _onTimer();

  void _onTimer() {
    if (_closed) return;
    final now = _now();
    game.tick(now);

    if (_expired(_emptySince, emptyTtl.inMilliseconds, now)) {
      close(LanCloseReason.empty);
      return;
    }
    if (_expired(_finishedAt, finishedTtl.inMilliseconds, now)) {
      close(LanCloseReason.finished);
      return;
    }
    _afterChange(now);
  }

  static bool _expired(int? since, int ttl, int now) =>
      since != null && now - since >= ttl;

  void _schedule() {
    _timer?.cancel();
    if (_closed) return;

    final due = <int>[
      ?game.timerDeadline,
      if (_emptySince case final since?) since + emptyTtl.inMilliseconds,
      if (_finishedAt case final at?) at + finishedTtl.inMilliseconds,
    ];
    if (due.isEmpty) return;

    final delay = due.reduce(min) - _now();
    _timer = Timer(Duration(milliseconds: max(delay, 0)), _onTimer);
  }

  // --- Broadcast and shutdown ---------------------------------------------

  /// A complete snapshot to every client, built per recipient (§5.1, §7).
  void _broadcast() {
    final now = _now();
    for (final entry in _connections.entries) {
      final view = game.view(_recipient(entry.value), now);
      // A new host token reaches exactly one recipient, in the snapshot right
      // after they were given the role (PROTOCOL.md §5.1).
      final id = switch (entry.value) {
        PlayerActor(:final id) => id,
        HostActor() => null,
      };
      (view['you'] as Map<String, dynamic>)['host_token'] = id == null
          ? null
          : _pendingTokens[id];
      entry.key.pushState(view);
    }
    // Delivered once: the token is only news to the client that just got it.
    _pendingTokens.clear();
  }

  /// A connection that authenticated as host may no longer hold the role: after
  /// a transfer it is an ordinary client and must be told so (§3.4).
  Actor _recipient(Actor actor) {
    if (actor is! HostActor || _heldByHostConn) return actor;
    final demoted = _demotedPlayerId;
    return demoted == null
        ? const HostActor(holder: false)
        : PlayerActor(demoted);
  }

  /// Ends the room, telling every client why while their sockets are still
  /// open — a party must never end in silence (AGENTS.md §5).
  void close(LanCloseReason reason) {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;

    for (final connection in _connections.keys.toList()) {
      connection.pushClosed(reason.wire);
    }
    _connections.clear();
    // The photos outlive nothing: a closed room's quiz is gone, and these are
    // megabytes held in a phone's memory (QUIZ_FORMAT.md §5.7).
    images.clear();
    if (!_closedCompleter.isCompleted) _closedCompleter.complete(reason);
  }
}
