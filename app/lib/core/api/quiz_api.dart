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

  Future<QuizDocument> create(QuizDocument quiz) async => QuizDocument.fromJson(
    await _send('POST', '/api/quizzes', json: quiz.toJson()),
  );

  Future<QuizDocument> replace(String id, QuizDocument quiz) async =>
      QuizDocument.fromJson(
        await _send('PUT', '/api/quizzes/$id', json: quiz.toJson()),
      );

  /// Unpublishes a quiz this device published (§5.5).
  Future<void> delete(String id) => _send('DELETE', '/api/quizzes/$id');

  /// Uploads a (pre-resized) photo; returns its key and url (§5.6).
  Future<QuizImage> uploadImage(
    List<int> bytes, {
    String filename = 'photo.jpg',
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/images'))
      ..headers['x-owner-key'] = await ownerKey()
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on Object {
      throw _unreachable;
    }
    final body = _check(response);
    return QuizImage(key: body['key'] as String, url: body['url'] as String?);
  }

  void close() => _client.close();

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
