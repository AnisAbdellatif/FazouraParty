import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fazoura_party/core/api/quiz_api.dart';
import 'package:fazoura_party/core/quizzes/quiz_archive.dart';
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
  QuizSubmission? submission,
}) => LocalQuiz(
  localId: localId,
  publishedId: publishedId,
  submission: submission,
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

/// One `.fazoura` package waiting in the review queue.
class FakeSubmission {
  FakeSubmission({
    required this.id,
    required this.document,
    required this.hasPhotos,
    this.replacesQuizId,
  });

  final String id;

  /// Decoded from the package the device sent, with the real reader — so a
  /// package the client cannot build correctly fails here rather than passing.
  final QuizDocument document;
  final bool hasPhotos;
  final String? replacesQuizId;

  String status = QuizSubmission.pending;
  String? reviewNote;
  String? quizId;

  Map<String, Object?> get json => {
    'id': id,
    'title': document.title,
    'status': status,
    'question_count': document.questions?.length ?? 0,
    'has_photos': hasPhotos,
    'review_note': reviewNote,
    'quiz_id': quizId,
    'replaces_quiz_id': replacesQuizId,
    'submitted_at': DateTime.utc(2026, 9, 16, 12).toIso8601String(),
    'reviewed_at': null,
  };
}

/// In-memory stand-in for the quiz and image endpoints (QUIZ_FORMAT.md §5).
/// Listings omit questions, like the real server.
class FakeQuizServer {
  FakeQuizServer([List<QuizDocument>? quizzes]) : quizzes = quizzes ?? [];

  final List<QuizDocument> quizzes;

  /// Packages sent for review and not yet published. Nothing here is in
  /// [quizzes]: that is the whole point of the queue.
  final List<FakeSubmission> submissions = [];
  final List<http.Request> requests = [];

  /// What an admin has configured as quick picks (`GET /api/tags`).
  List<String> suggestedTags = defaultQuizTags;

  bool failLists = false;
  bool failWrites = false;
  bool failArchives = false;
  int _ids = 0;
  int _submissionIds = 0;

  /// Still waiting to be read. An answered submission keeps its row, as the
  /// real server does, so that its author's device can learn what happened.
  List<FakeSubmission> get pending => [
    for (final item in submissions)
      if (item.status == QuizSubmission.pending) item,
  ];

  /// Reports somebody has sent about a public quiz, newest last.
  final List<({String quizId, String reason, String? note})> reports = [];

  /// Puts a package in the queue without a request, for a test that needs a
  /// device to start out with something already waiting.
  FakeSubmission queue(QuizDocument document, {String? replaces}) {
    final submission = FakeSubmission(
      id: 'sub-${++_submissionIds}',
      document: document,
      hasPhotos: (document.questions ?? const <QuizQuestion>[]).any(
        (question) => question.hasPhoto,
      ),
      replacesQuizId: replaces,
    );
    submissions.add(submission);
    return submission;
  }

  /// Stands in for an admin reading the queue and publishing it (ADMIN.md
  /// §3.2). Only now does a quiz exist.
  QuizDocument approve(String id) {
    final submission = submissions.firstWhere((item) => item.id == id);
    final published = submission.document.copyWith(
      id: submission.replacesQuizId ?? 'pub-${++_ids}',
      isOwner: true,
      source: 'custom',
      visibility: 'public',
      questionCount: submission.document.questions?.length ?? 0,
    );
    final existing = quizzes.indexWhere((item) => item.id == published.id);
    if (existing < 0) {
      quizzes.add(published);
    } else {
      quizzes[existing] = published;
    }
    submission
      ..status = QuizSubmission.approved
      ..quizId = published.id;
    return published;
  }

  void reject(String id, String note) {
    submissions.firstWhere((item) => item.id == id)
      ..status = QuizSubmission.rejected
      ..reviewNote = note;
  }

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

    final archiveId = RegExp(r'^/api/quizzes/(.+)/archive$')
        .firstMatch(path)
        ?.group(1);
    if (request.method == 'GET' && archiveId != null) {
      if (failArchives) {
        return _json({'code': 'quiz_archive_download_failed'}, 404);
      }
      final index = quizzes.indexWhere((q) => q.id == archiveId);
      if (index < 0) return _json({'code': 'quiz_not_found'}, 404);
      return http.Response.bytes(_archive(quizzes[index]), 200);
    }

    if (request.method == 'GET' && path.startsWith('/uploads/')) {
      return http.Response.bytes([0xFF, 0xD8, 0xFF, 0xE0], 200);
    }

    if (request.method != 'GET' && failWrites) {
      return _json({'code': 'boom', 'message': 'Server is down'}, 503);
    }

    if (request.method == 'GET' && path == '/api/submissions') {
      if (failLists) return _json({'code': 'boom'}, 500);
      return _json({
        'submissions': [for (final item in submissions) item.json],
      });
    }

    final withdrawId = RegExp(r'^/api/submissions/(.+)$')
        .firstMatch(path)
        ?.group(1);
    if (request.method == 'DELETE' && withdrawId != null) {
      final index = submissions.indexWhere((item) => item.id == withdrawId);
      if (index < 0) return _json({'code': 'not_found'}, 404);
      submissions.removeAt(index);
      return http.Response('', 204);
    }

    // Publishing is a submission: the package goes in the queue and no quiz
    // exists until an admin approves it (§5.4).
    if (request.method == 'POST' && path == '/api/quizzes') {
      return _json(_submit(request).json, 201);
    }

    // Before the catch-all below, which would otherwise read "pub-1/report"
    // as a quiz id.
    final reportedId = RegExp(r'^/api/quizzes/(.+)/report$')
        .firstMatch(path)
        ?.group(1);
    if (request.method == 'POST' && reportedId != null) {
      if (quizzes.indexWhere((q) => q.id == reportedId) < 0) {
        return _json({'code': 'quiz_not_found'}, 404);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final reason = body['reason'] as String?;
      if (reason == null || !_reportReasons.contains(reason)) {
        return _json({'code': 'invalid_report'}, 422);
      }
      reports.add((
        quizId: reportedId,
        reason: reason,
        note: body['note'] as String?,
      ));
      // Nothing back: what an admin decides is not something a caller can
      // probe by reading the answer (§5.9).
      return http.Response('', 204);
    }

    final id = RegExp(r'^/api/quizzes/(.+)$').firstMatch(path)?.group(1);
    final index = quizzes.indexWhere((q) => q.id == id);
    if (index < 0) return _json({'code': 'quiz_not_found'}, 404);

    switch (request.method) {
      case 'GET':
        // Without questions, as the real `show` answers anyone but the
        // publisher (QUIZ_FORMAT.md §5.3) — accepted answers are not handed out
        // by an ordinary read. Returning them here hid a bug where the LAN host
        // sent a quiz with nothing in it.
        return _json(quizzes[index].copyWith(questions: null).toJson());
      case 'PUT':
        // An edit is a submission too, offered against the quiz it replaces.
        return _json(_submit(request, replaces: id).json);
      case 'DELETE':
        quizzes.removeAt(index);
        return http.Response('', 204);
    }
    return _json({'code': 'not_found'}, 404);
  });

  FakeSubmission _submit(http.Request request, {String? replaces}) {
    final package = _filePart(request);
    // Read with the app's own decoder, which is the server's reader in
    // miniature: a package whose manifest or photos don't line up throws here
    // rather than quietly becoming a submission.
    final document = QuizArchive.decode(package).quiz;
    final submission = FakeSubmission(
      id: 'sub-${++_submissionIds}',
      document: document,
      hasPhotos: (document.questions ?? const <QuizQuestion>[]).any(
        (question) => question.hasPhoto,
      ),
      replacesQuizId: replaces,
    );
    submissions.add(submission);
    return submission;
  }

  /// The `file` part of a `multipart/form-data` body. Latin-1 round-trips
  /// bytes through a string one for one, so a ZIP survives being sliced this
  /// way.
  static Uint8List _filePart(http.Request request) {
    final contentType = request.headers['content-type'] ?? '';
    final boundary = RegExp('boundary=(.+)').firstMatch(contentType)?.group(1);
    if (boundary == null) {
      throw StateError('Expected a multipart body, got: $contentType');
    }
    final body = latin1.decode(request.bodyBytes);
    for (final part in body.split('--$boundary')) {
      final split = part.indexOf('\r\n\r\n');
      if (split < 0 || !part.contains('name="file"')) continue;
      final content = part.substring(split + 4);
      return Uint8List.fromList(
        latin1.encode(
          content.endsWith('\r\n')
              ? content.substring(0, content.length - 2)
              : content,
        ),
      );
    }
    throw StateError('No "file" part in the request.');
  }

  static const _reportReasons = {
    'sexual',
    'hate',
    'violence',
    'illegal',
    'spam',
    'other',
  };

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  static List<int> _archive(QuizDocument quiz) {
    final document = quiz.toJson();
    final questions = (document['questions'] as List<dynamic>? ?? []).map((
      raw,
    ) {
      final question = Map<String, dynamic>.from(raw as Map);
      final image = question['image'];
      if (image is Map) {
        final imageMap = Map<String, dynamic>.from(image);
        final url = imageMap['url'] as String?;
        question['image'] = {
          'path': 'media/${url == null ? 'photo.jpg' : url.split('/').last}',
          'alt': imageMap['alt'],
        };
      }
      return question;
    }).toList();
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'quiz': {...document, 'questions': questions},
          }),
        ),
      );
    if (questions.any((question) => (question as Map)['image'] != null)) {
      archive.addFile(
        ArchiveFile('media/photo.jpg', 4, [0xFF, 0xD8, 0xFF, 0xE0]),
      );
    }
    return ZipEncoder().encodeBytes(archive);
  }
}
