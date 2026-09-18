import 'dart:convert';

import 'package:fazoura_party/core/api/quiz_api.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/storage/local_quiz_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';

const testOwnerKey = 'test-owner-key-aaaaaaaaaaaaaaaaaaaaaaaaaaaa';

QuizDocument quiz(
  String id,
  String title, {
  bool owner = false,
  String source = 'custom',
  int count = 5,
  List<String> tags = const ['general'],
}) => QuizDocument(
  id: id,
  title: title,
  isOwner: owner,
  visibility: 'public',
  source: source,
  tags: tags,
  questionCount: count,
);

/// A quiz on this device with [questions] text questions.
LocalQuiz localQuiz(
  String localId,
  String title, {
  String visibility = 'private',
  String? publishedId,
  List<QuizQuestion>? questions,
  List<String> tags = const ['general'],
  DateTime? updatedAt,
}) => LocalQuiz(
  localId: localId,
  publishedId: publishedId,
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 16),
  quiz: QuizDocument(
    title: title,
    visibility: visibility,
    tags: tags,
    questions:
        questions ??
        const [
          QuizQuestion(prompt: 'First?', acceptedAnswers: ['1']),
        ],
  ),
);

/// A fresh in-memory database for one test.
Future<Database> memoryDatabase() =>
    newDatabaseFactoryMemory().openDatabase('test.db');

/// Seeds [quizzes] into [database].
Future<void> seedLocal(Database database, List<LocalQuiz> quizzes) async {
  final store = LocalQuizStore(Future.value(database));
  for (final quiz in quizzes) {
    await store.put(quiz);
  }
}

/// In-memory stand-in for the quiz and image endpoints (QUIZ_FORMAT.md §5).
/// Listings omit questions, like the real server.
class FakeQuizServer {
  FakeQuizServer([List<QuizDocument>? quizzes]) : quizzes = quizzes ?? [];

  final List<QuizDocument> quizzes;
  final List<http.Request> requests = [];

  /// What an admin has configured as quick picks (`GET /api/tags`).
  List<String> suggestedTags = defaultQuizTags;

  bool failLists = false;
  bool failWrites = false;
  int _ids = 0;

  QuizApi api() => QuizApi(
    baseUrl: 'http://localhost:4000',
    ownerKey: () async => testOwnerKey,
    client: client,
  );

  List<http.Request> requestsWith(String method, String pathPrefix) => [
    for (final request in requests)
      if (request.method == method && request.url.path.startsWith(pathPrefix))
        request,
  ];

  http.Request? lastWith(String method, String pathPrefix) {
    final matching = requestsWith(method, pathPrefix);
    return matching.isEmpty ? null : matching.last;
  }

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    final query = request.url.queryParameters;

    if (request.method == 'GET' && path == '/api/quizzes') {
      if (failLists) return _json({'code': 'boom'}, 500);
      final search = query['q']?.toLowerCase();
      final tag = query['tag'];
      final offset = int.parse(query['offset'] ?? '0');
      final limit = int.parse(query['limit'] ?? '20');
      final matching = quizzes
          .where(
            (q) =>
                search == null ||
                q.title.toLowerCase().contains(search) ||
                q.tags.any((t) => t.contains(search)),
          )
          .where((q) => tag == null || q.tags.contains(tag))
          .toList();
      return _json({
        'quizzes': [
          for (final q in matching.skip(offset).take(limit))
            q.copyWith(questions: null).toJson(),
        ],
        'next_offset': offset + limit < matching.length ? offset + limit : null,
      });
    }

    if (request.method == 'GET' && path == '/api/tags') {
      final counts = <String, int>{};
      for (final q in quizzes) {
        for (final tag in q.tags) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
      final entries = counts.entries.toList()
        ..sort(
          (a, b) => a.value == b.value
              ? a.key.compareTo(b.key)
              : b.value.compareTo(a.value),
        );
      final limit = int.parse(query['limit'] ?? '30');
      return _json({
        'tags': [
          for (final entry in entries.take(limit))
            {'tag': entry.key, 'count': entry.value},
        ],
        'suggested': suggestedTags,
      });
    }

    final downloadId = RegExp(r'^/api/quizzes/(.+)/download$')
        .firstMatch(path)
        ?.group(1);
    if (request.method == 'GET' && downloadId != null) {
      final index = quizzes.indexWhere((q) => q.id == downloadId);
      if (index < 0) return _json({'code': 'quiz_not_found'}, 404);
      return _json(quizzes[index].toJson());
    }

    if (request.method == 'GET' && path.startsWith('/uploads/')) {
      return http.Response.bytes([0xFF, 0xD8, 0xFF, 0xE0], 200);
    }

    if (request.method != 'GET' && failWrites) {
      return _json({'code': 'boom', 'message': 'Server is down'}, 503);
    }

    if (request.method == 'POST' && path == '/api/quizzes') {
      final created = _fromBody(request).copyWith(id: 'pub-${++_ids}');
      quizzes.add(created);
      return _json(created.toJson(), 201);
    }

    if (request.method == 'POST' && path == '/api/images') {
      final key = 'img${++_ids}.jpg';
      return _json({
        'key': key,
        'url': 'http://localhost:4000/uploads/$key',
      }, 201);
    }

    final id = RegExp(r'^/api/quizzes/(.+)$').firstMatch(path)?.group(1);
    final index = quizzes.indexWhere((q) => q.id == id);
    if (index < 0) return _json({'code': 'quiz_not_found'}, 404);

    switch (request.method) {
      case 'GET':
        return _json(quizzes[index].toJson());
      case 'PUT':
        quizzes[index] = _fromBody(request).copyWith(id: id);
        return _json(quizzes[index].toJson());
      case 'DELETE':
        quizzes.removeAt(index);
        return http.Response('', 204);
    }
    return _json({'code': 'not_found'}, 404);
  });

  static QuizDocument _fromBody(http.Request request) {
    final document = QuizDocument.fromJson(
      jsonDecode(request.body) as Map<String, dynamic>,
    );
    return document.copyWith(
      isOwner: true,
      source: 'custom',
      visibility: 'public',
      questionCount: document.questions?.length ?? 0,
    );
  }

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);
}
