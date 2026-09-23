import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Id of the built-in Phase 1 pack.
const builtInPackId = 'general-knowledge';

/// Cloud room creation (PROTOCOL.md §3.1).
class RoomApi {
  RoomApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// `POST /api/rooms` → `{room_code, host_token}` (PROTOCOL.md §3.1).
  /// Hosts the stored quiz [quizId], or, when [inlineQuiz] is given, a
  /// private quiz sent whole with its photos (QUIZ_FORMAT.md §5.7).
  /// With [listed], the room goes on the public list (§3.5) and plays
  /// published quizzes only.
  /// Throws [GameError] (e.g. `quiz_not_found`) on failure.
  Future<CreatedRoom> createRoom({
    String? quizId,
    QuizDocument? inlineQuiz,
    bool listed = false,
  }) async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final body = <String, dynamic>{
      'quiz': ?inlineQuiz?.forInlineRoom().toJson(),
      if (inlineQuiz == null) 'quiz_id': ?quizId,
      if (listed) 'listed': true,
    };
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$base/api/rooms'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      );
    } on Object {
      throw const GameError(
        code: GameError.connectionFailed,
        message: 'Could not reach the game server.',
      );
    }

    final decoded = _decode(response.body);
    if (response.statusCode == 201 || response.statusCode == 200) {
      return CreatedRoom.fromJson(decoded);
    }
    final code = decoded['code'];
    final message = decoded['message'];
    throw GameError(
      code: code is String ? code : 'http_${response.statusCode}',
      message: message is String ? message : null,
    );
  }

  /// `GET /api/rooms` — the rooms their hosts chose to list (PROTOCOL.md
  /// §3.5), best first. Throws [GameError] when the list cannot be had.
  Future<List<PublicRoom>> listRooms() async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$base/api/rooms'),
            headers: {'accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
    } on Object {
      throw const GameError(
        code: GameError.connectionFailed,
        message: 'Could not reach the game server.',
      );
    }

    final decoded = _decode(response.body);
    final rooms = decoded['rooms'];
    if (response.statusCode != 200 || rooms is! List) {
      final code = decoded['code'];
      throw GameError(
        code: code is String ? code : 'http_${response.statusCode}',
        message: decoded['message'] is String
            ? decoded['message'] as String
            : null,
      );
    }
    // One entry this build cannot read — a phase added in a later minor, say —
    // costs that room its place on the list, not the whole list.
    final listed = <PublicRoom>[];
    for (final room in rooms) {
      if (room is! Map<String, dynamic>) continue;
      try {
        listed.add(PublicRoom.fromJson(room));
      } on Object {
        continue;
      }
    }
    return listed;
  }

  /// `GET /api/rooms/:code` — whether this device's `hostToken` still opens
  /// that room (PROTOCOL.md §3.1).
  ///
  /// True it is there, false it is gone, and **null when the answer could not
  /// be had** — no network, a server that did not respond, anything but a
  /// definite `404`. The caller uses that to decide whether to forget the
  /// room, and forgetting one over a blip on the way to the party would be
  /// worse than briefly offering one that has ended.
  Future<bool?> hostRoomAlive(String code, String hostToken) async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$base/api/rooms/$code'),
            headers: {'x-host-token': hostToken, 'accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 6));
    } on Object {
      return null;
    }

    if (response.statusCode == 200) return true;
    // Only the server's own "no" counts, and it has to say so in the body. A
    // bare 404 is what a server too old to know this route answers, and what a
    // captive portal answers to everything — neither has any idea whether the
    // party is still going, and forgetting the room on their say-so would take
    // the host's only way back in.
    if (response.statusCode == 404 &&
        _decode(response.body)['code'] == 'room_not_found') {
      return false;
    }
    return null;
  }

  /// `POST /api/rooms/:code/report` — reports the quiz a question in this room
  /// came from (QUIZ_FORMAT.md §5.9).
  ///
  /// The room is where content is actually seen: browsing a quiz shows a title,
  /// a description and tags, and nothing anybody would object to. The server
  /// resolves the question to its quiz itself, so no quiz id is ever broadcast
  /// — one during a game would also be a cheat button, since the download
  /// endpoint hands out the accepted answers.
  ///
  /// Either token this room issued is proof of being in it, and one is
  /// required: without it this would say which six-character codes are live
  /// games. A host who is also playing has only a host token, so both are
  /// accepted. Throws [GameError] — `quiz_not_public` when the host made the
  /// quiz themselves, so there is nothing published to take down.
  ///
  /// With [playerId] it reports that player instead — their name or their
  /// answer (PROTOCOL.md §3.5). There is no account to point at; the server
  /// keeps what was on the screen and what a ban needs.
  Future<void> reportRoom(
    String code, {
    required String reason,
    required String ownerKey,
    String? playerToken,
    String? hostToken,
    String? questionId,
    String? playerId,
    String? note,
  }) async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$base/api/rooms/$code/report'),
        headers: {
          'content-type': 'application/json',
          'accept': 'application/json',
          'x-player-token': ?playerToken,
          'x-host-token': ?hostToken,
          'x-owner-key': ownerKey,
        },
        body: jsonEncode({
          'reason': reason,
          'question_id': ?questionId,
          'player_id': ?playerId,
          if (note != null && note.isNotEmpty) 'note': note,
        }),
      );
    } on Object {
      throw const GameError(
        code: GameError.connectionFailed,
        message: 'Could not reach the game server.',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final decoded = _decode(response.body);
    final code0 = decoded['code'];
    final message = decoded['message'];
    throw GameError(
      code: code0 is String ? code0 : 'http_${response.statusCode}',
      message: message is String ? message : null,
    );
  }

  void close() => _client.close();

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }
}
