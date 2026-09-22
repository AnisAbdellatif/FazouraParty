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
  /// Throws [GameError] (e.g. `quiz_not_found`) on failure.
  Future<CreatedRoom> createRoom({
    String? quizId,
    QuizDocument? inlineQuiz,
  }) async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final body = inlineQuiz != null
        ? {'quiz': inlineQuiz.forInlineRoom().toJson()}
        : quizId == null
        ? <String, dynamic>{}
        : {'quiz_id': quizId};
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
