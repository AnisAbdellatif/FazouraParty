import 'dart:convert';
import 'dart:io';

import 'package:fazoura_cli/fazoura_cli.dart';
import 'package:fazoura_cli/src/context.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Publishing from the CLI is the app's flow: the app's `QuizLibrary` over the
/// app's `LocalQuizStore`. This drives it end to end against a stand-in server
/// and checks both what reached the server and what the library remembers.
void main() {
  late Directory tmp;
  late Map<String, String> env;
  late List<String> calls;
  late Map<String, Map<String, Object?>> queue;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fazoura_library_');
    env = {'FAZOURA_CONFIG_DIR': tmp.path, 'FAZOURA_OWNER_KEY': 'k' * 43};
    calls = [];
    queue = {};
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  var nextId = 0;
  final server = MockClient((request) async {
    final call = '${request.method} ${request.url.path}';
    calls.add(call);
    Map<String, Object?> submission(String? replaces) {
      final id = 's${++nextId}';
      return queue[id] = {
        'id': id,
        'title': 'Film Night',
        'status': 'pending',
        'replaces_quiz_id': replaces,
      };
    }

    return switch (call) {
      'POST /api/quizzes' => http.Response(jsonEncode(submission(null)), 201),
      'PUT /api/quizzes/q1' => http.Response(jsonEncode(submission('q1')), 201),
      'GET /api/submissions' => http.Response(
        jsonEncode({'submissions': queue.values.toList()}),
        200,
      ),
      _ when request.method == 'DELETE' => http.Response('', 204),
      _ => http.Response(jsonEncode({'code': 'nope'}), 404),
    };
  });

  Future<int> fazoura(List<String> args) => runFazoura(
    ['--server', 'http://test', ...args],
    environment: env,
    client: server,
  );

  Future<Map<String, Object?>> only() async {
    final context = Context(
      server: 'http://test',
      output: Output(json: true),
      environment: env,
    );
    final all = await context.library.list();
    expect(all, hasLength(1));
    final local = all.single;
    return {
      'id': local.localId,
      'public': local.wantsPublic,
      'published': local.publishedId,
      'pending': local.inReview,
    };
  }

  test('import, publish, approval, an edit, unpublish, forget', () async {
    final folder = Directory('${tmp.path}/film-night')..createSync();
    File('${folder.path}/film-night.json').writeAsStringSync(
      jsonEncode({
        'format_version': '1.0',
        'title': 'Film Night',
        'tags': ['movies'],
        'questions': [
          {
            'type': 'text',
            'prompt': 'Which film?',
            'accepted_answers': ['Alien'],
          },
        ],
      }),
    );

    expect(await fazoura(['quiz', 'import', folder.path]), 0);
    expect(calls, isEmpty, reason: 'a private quiz never touches the server');
    final id = (await only())['id']! as String;

    expect(await fazoura(['quiz', 'publish', 'film night']), 0);
    expect(calls, ['POST /api/quizzes']);
    expect(await only(), containsPair('pending', true));

    // Somebody reads the queue; the machine learns it on its next look.
    queue['s1']!
      ..['status'] = 'approved'
      ..['quiz_id'] = 'q1';
    expect(await fazoura(['quiz', 'mine']), 0);
    expect(
      await only(),
      allOf(containsPair('published', 'q1'), containsPair('pending', false)),
    );

    // An edit of a public quiz is offered against it, through review again.
    expect(
      await fazoura([
        'quiz',
        'import',
        folder.path,
        '--into',
        id.substring(0, 6),
      ]),
      0,
    );
    expect(calls.last, 'PUT /api/quizzes/q1');
    expect(
      await only(),
      allOf(containsPair('published', 'q1'), containsPair('pending', true)),
    );

    // Private again: the waiting edit is withdrawn, then the quiz taken down.
    calls.clear();
    expect(await fazoura(['quiz', 'unpublish', 'film night']), 0);
    expect(calls, ['DELETE /api/submissions/s2', 'DELETE /api/quizzes/q1']);
    expect(
      await only(),
      allOf(containsPair('public', false), containsPair('published', null)),
    );

    expect(await fazoura(['quiz', 'forget', 'film night']), 0);
    final context = Context(
      server: 'http://test',
      output: Output(json: true),
      environment: env,
    );
    expect(await context.library.list(), isEmpty);
  });

  test('a library quiz is named, or the name is refused', () async {
    expect(await fazoura(['quiz', 'publish', 'nothing']), 64);
  });
}
