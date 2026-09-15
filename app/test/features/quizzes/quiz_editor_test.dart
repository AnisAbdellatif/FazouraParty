import 'dart:convert';
import 'dart:typed_data';

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/quiz_providers.dart';
import 'package:fazoura_party/core/storage/local_quiz_store.dart';
import 'package:fazoura_party/features/quizzes/quiz_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sembast/sembast.dart';

import '../../support/fake_quiz_server.dart';

void main() {
  late FakeQuizServer server;
  late Database database;
  LocalQuiz? saved;
  var pickerCalls = 0;
  final photoBytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 40, height: 20)),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> openEditor(
    WidgetTester tester, {
    LocalQuiz? existing,
    List<QuizDocument> published = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    server = FakeQuizServer([...published]);
    // Real async: sembast work doesn't advance under the fake test clock.
    database = (await tester.runAsync(() async {
      final db = await memoryDatabase();
      if (existing != null) await seedLocal(db, [existing]);
      return db;
    }))!;
    saved = null;
    pickerCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quizApiProvider.overrideWithValue(server.api()),
          localDatabaseProvider.overrideWith((ref) async => database),
          photoPickerProvider.overrideWithValue(() async {
            pickerCalls++;
            return photoBytes;
          }),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () async =>
                    saved = await showQuizEditor(context, existing: existing),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, text);
  }

  Future<List<LocalQuiz>> stored() =>
      LocalQuizStore(Future.value(database)).list();

  testWidgets('a private quiz is saved on the device only', (tester) async {
    await openEditor(tester);

    await enter(tester, 'quizTitleField', '  Movie Night ');
    await tapKey(tester, 'category-movies');
    await enter(tester, 'questionPrompt-0', 'Who directed Jaws?');
    await enter(tester, 'answerInput-0', 'Spielberg');
    await tapKey(tester, 'addAnswer-0');
    // A pending answer is committed on save.
    await enter(tester, 'answerInput-0', 'Steven Spielberg');
    await tapKey(tester, 'difficulty-0-medium');
    await tapKey(tester, 'defaultTime-45');
    await tapKey(tester, 'saveQuizButton');

    expect(server.requests, isEmpty);
    expect(saved, isNotNull);
    final quiz = saved!.quiz;
    expect(quiz.title, 'Movie Night');
    expect(quiz.category, 'movies');
    expect(quiz.visibility, 'private');
    expect(quiz.defaultSettings.timeLimitMs, 45000);
    expect(quiz.questions!.single.acceptedAnswers, [
      'Spielberg',
      'Steven Spielberg',
    ]);
    expect(quiz.questions!.single.difficulty, 'medium');
    expect(saved!.isPublished, isFalse);
    expect(await tester.runAsync(stored), [saved]);
  });

  testWidgets('validates before saving', (tester) async {
    await openEditor(tester);

    await tapKey(tester, 'saveQuizButton');
    expect(find.text('Give your quiz a title.'), findsOneWidget);

    await enter(tester, 'quizTitleField', 'Quiz');
    await tapKey(tester, 'saveQuizButton');
    expect(find.text('Question 1 needs a question.'), findsOneWidget);

    await enter(tester, 'questionPrompt-0', 'Why?');
    await tapKey(tester, 'saveQuizButton');
    expect(
      find.text('Question 1 needs at least one accepted answer.'),
      findsOneWidget,
    );

    await tapKey(tester, 'questionType-0-photo');
    await enter(tester, 'answerInput-0', 'Because');
    await tapKey(tester, 'saveQuizButton');
    expect(find.text('Question 1 needs a photo.'), findsOneWidget);

    expect(saved, isNull);
    expect(await tester.runAsync(stored), isEmpty);
  });

  testWidgets('a public photo quiz keeps the photo locally and publishes it', (
    tester,
  ) async {
    await openEditor(tester);

    await enter(tester, 'quizTitleField', 'Stills');
    await tapKey(tester, 'visibilityPublic');
    expect(find.text('Save & publish'), findsOneWidget);
    await tapKey(tester, 'questionType-0-photo');
    await enter(tester, 'questionPrompt-0', 'Which film?');
    await enter(tester, 'answerInput-0', 'Alien');
    await tapKey(tester, 'addAnswer-0');
    await tapKey(tester, 'pickPhoto-0');

    expect(pickerCalls, 1);
    expect(find.byKey(const Key('photoPreview-0')), findsOneWidget);
    expect(server.requests, isEmpty, reason: 'nothing uploads until saving');

    await tapKey(tester, 'saveQuizButton');

    expect(server.requestsWith('POST', '/api/images'), hasLength(1));
    final body = jsonDecode(
      server.lastWith('POST', '/api/quizzes')!.body,
    ) as Map<String, dynamic>;
    final question = (body['questions'] as List).single as Map<String, dynamic>;
    expect(question['type'], 'text_photo');
    expect((question['image'] as Map)['key'], 'img1.jpg');

    expect(saved?.publishedId, 'pub-2');
    final image = saved!.quiz.questions!.single.image!;
    expect(image.key, 'img1.jpg');
    final jpeg = base64Decode(image.data!);
    expect(jpeg.sublist(0, 3), [0xFF, 0xD8, 0xFF], reason: 'resized to JPEG');
  });

  testWidgets('editing a published quiz reorders and republishes it', (
    tester,
  ) async {
    final existing = localQuiz(
      'local-1',
      'Old title',
      visibility: 'public',
      publishedId: 'pub-1',
      questions: const [
        QuizQuestion(prompt: 'First', acceptedAnswers: ['1']),
        QuizQuestion(
          prompt: 'Second',
          acceptedAnswers: ['2'],
          difficulty: 'hard',
        ),
      ],
    );
    await openEditor(
      tester,
      existing: existing,
      published: [quiz('pub-1', 'Old title', owner: true)],
    );

    expect(find.text('EDIT QUIZ'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);

    await enter(tester, 'quizTitleField', 'New title');
    await tapKey(tester, 'moveDown-0');
    await tapKey(tester, 'addQuestionButton');
    await tapKey(tester, 'deleteQuestion-2');
    await tapKey(tester, 'saveQuizButton');

    final body = jsonDecode(
      server.lastWith('PUT', '/api/quizzes/pub-1')!.body,
    ) as Map<String, dynamic>;
    expect(body['title'], 'New title');
    expect((body['questions'] as List).map((q) => q['prompt']), [
      'Second',
      'First',
    ]);
    expect(saved?.localId, 'local-1');
    expect(saved?.quiz.questions!.first.difficulty, 'hard');
    expect(await tester.runAsync(stored), hasLength(1));
  });

  testWidgets('a failed publish says the quiz was still saved', (tester) async {
    await openEditor(tester);
    server.failWrites = true;

    await enter(tester, 'quizTitleField', 'Quiz');
    await tapKey(tester, 'visibilityPublic');
    await enter(tester, 'questionPrompt-0', 'Why?');
    await enter(tester, 'answerInput-0', 'Because');
    await tapKey(tester, 'saveQuizButton');

    expect(
      find.textContaining('Saved on this device, but publishing failed'),
      findsOneWidget,
    );
    expect(saved, isNull);
    final quizzes = (await tester.runAsync(stored))!;
    expect(quizzes.single.wantsPublic, isTrue);
    expect(quizzes.single.isPublished, isFalse);

    // Saving again reuses the same local quiz.
    server.failWrites = false;
    await tapKey(tester, 'saveQuizButton');
    expect(saved?.publishedId, isNotNull);
    expect(await tester.runAsync(stored), hasLength(1));
  });
}
