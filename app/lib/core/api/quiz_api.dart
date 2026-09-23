import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Quiz REST API (protocol/QUIZ_FORMAT.md §5). Every request carries this
/// device's publisher key so the server recognises quizzes it published.
class QuizApi {
  QuizApi({required this.baseUrl, required this.ownerKey, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;

  /// This device's owner key, resolved lazily (it is created on first use).
  final Future<String> Function() ownerKey;
  final http.Client _client;

  /// Public quizzes (§5.1). [query] matches the title or a tag; [tag] keeps
  /// only quizzes carrying exactly that tag.
  Future<QuizPage> list({
    String? query,
    String? tag,
    int limit = 20,
    int offset = 0,
  }) async {
    final body = await _send(
      'GET',
      '/api/quizzes',
      query: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return QuizPage(
      quizzes: [
        for (final item in body['quizzes'] as List<dynamic>)
          QuizDocument.fromJson(item as Map<String, dynamic>),
      ],
      nextOffset: body['next_offset'] as int?,
    );
  }

  Future<QuizDocument> get(String id) async =>
      QuizDocument.fromJson(await _send('GET', '/api/quizzes/$id'));

  /// Explicitly downloads the full quiz for offline use. Unlike [get], this
  /// includes accepted answers for community quizzes.
  Future<QuizDocument> download(String id) async =>
      QuizDocument.fromJson(await _send('GET', '/api/quizzes/$id/download'));

  Future<List<int>> downloadArchive(String id) async {
    final response = await _client.get(
      _uri('/api/quizzes/$id/archive'),
      headers: {'accept': 'application/zip'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GameError(
        code: 'quiz_archive_download_failed',
        message: 'Could not download the offline quiz.',
      );
    }
    return response.bodyBytes;
  }

  Future<List<int>> downloadImage(String url) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse(url),
        headers: {'accept': 'image/*'},
      );
    } on Object {
      throw _unreachable;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GameError(
        code: 'image_download_failed',
        message: 'Could not download a quiz image.',
      );
    }
    return response.bodyBytes;
  }

  /// Tags public quizzes use (most used first) and the quick picks an admin
  /// maintains on the server (§5.2).
  Future<QuizTags> tags({int limit = 30}) async {
    final body = await _send('GET', '/api/tags', query: {'limit': '$limit'});
    return (
      popular: [
        for (final item in body['tags'] as List<dynamic>? ?? const [])
          (
            tag: (item as Map<String, dynamic>)['tag'] as String,
            count: item['count'] as int,
          ),
      ],
      suggested: [
        for (final tag in body['suggested'] as List<dynamic>? ?? const [])
          tag as String,
      ],
    );
  }

  /// Sends a `.fazoura` package for review (§5.4). Publishing is a submission:
  /// this puts the package in the queue and creates no quiz, so nothing is
  /// listed and no photo is written to the server until somebody approves it.
  ///
  /// [replaces] offers the package as a new version of a quiz this device
  /// already published. An edit goes through the queue too — otherwise the
  /// review would mean nothing, since anyone could publish something harmless
  /// and then swap its contents.
  Future<QuizSubmission> submit(List<int> package, {String? replaces}) async =>
      QuizSubmission.fromJson(
        await _sendPackage(
          replaces == null ? 'POST' : 'PUT',
          replaces == null ? '/api/quizzes' : '/api/quizzes/$replaces',
          package,
        ),
      );

  /// What this device has sent for review, newest first (§5.4a).
  Future<List<QuizSubmission>> submissions() async {
    final body = await _send('GET', '/api/submissions');
    return [
      for (final item in body['submissions'] as List<dynamic>? ?? const [])
        QuizSubmission.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Takes a submission back out of the queue. This device's own only.
  Future<void> withdraw(String id) => _send('DELETE', '/api/submissions/$id');

  /// Reports a public quiz as something that should not be public (§5.9).
  ///
  /// The server answers the same way whatever it does with it — first report or
  /// fifth, already dismissed or not. That is deliberate: what an admin has
  /// decided is not something a caller gets to probe.
  Future<void> report(String id, {required String reason, String? note}) =>
      _send(
        'POST',
        '/api/quizzes/$id/report',
        json: {
          'reason': reason,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );

  /// Unpublishes a quiz this device published (§5.5).
  Future<void> delete(String id) => _send('DELETE', '/api/quizzes/$id');

  void close() => _client.close();

  Future<Map<String, dynamic>> _sendPackage(
    String method,
    String path,
    List<int> package,
  ) async {
    final request = http.MultipartRequest(method, _uri(path))
      ..headers['x-owner-key'] = await ownerKey()
      ..headers['accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes('file', package, filename: 'quiz.fazoura'),
      );
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on Object {
      throw _unreachable;
    }
    return _check(response);
  }

  static const _unreachable = GameError(
    code: GameError.connectionFailed,
    message: 'Could not reach the game server.',
  );

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? json,
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers['x-owner-key'] = await ownerKey()
      ..headers['accept'] = 'application/json';
    if (json != null) {
      request
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode(json);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on Object {
      throw _unreachable;
    }
    return _check(response);
  }

  static Map<String, dynamic> _check(http.Response response) {
    final body = _decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    final code = body['code'];
    throw GameError(
      code: code is String ? code : 'http_${response.statusCode}',
      message:
          firstValidationError(body['errors']) ?? body['message'] as String?,
    );
  }

  static Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  /// First readable message from a changeset-style `errors` object, e.g.
  /// `Question 2: prompt can't be blank`.
  static String? firstValidationError(Object? errors, [String prefix = '']) {
    if (errors is Map) {
      for (final entry in errors.entries) {
        final field = entry.key.toString().replaceAll('_', ' ');
        final value = entry.value;
        if (value is List && value.isNotEmpty && value.first is String) {
          return '$prefix$field ${value.first}';
        }
        if (value is List) {
          for (final (index, item) in value.indexed) {
            final nested = firstValidationError(
              item,
              'Question ${index + 1}: ',
            );
            if (nested != null) return nested;
          }
        }
      }
    }
    return null;
  }
}
