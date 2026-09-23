import 'dart:convert';
import 'dart:typed_data';

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/quiz_providers.dart';
import 'package:fazoura_party/core/storage/local_quiz_store.dart';
import 'package:fazoura_party/features/quizzes/quiz_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:sembast/sembast.dart';

import '../../support/fake_quiz_server.dart';

void main() {
  // These are about what happens once the community rules are agreed to;
  // community_rules_test.dart is about the agreeing.
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'fazoura.community_rules_accepted': 1,
    }),
  );

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
    await tapKey(tester, 'suggestedTag-movies');
    await enter(tester, 'tagInput', '  Pub   QUIZ ');
    await tapKey(tester, 'addTagButton');
    // A tag still in the input is kept on save.
    await enter(tester, 'tagInput', '80s');
    await enter(tester, 'questionPrompt-0', 'Who directed Jaws?');
    await enter(tester, 'answerInput-0', 'Spielberg');
    await tapKey(tester, 'addAnswer-0');
    // A pending answer is committed on save.
    await enter(tester, 'answerInput-0', 'Steven Spielberg');
    await tapKey(tester, 'difficulty-0-medium');
    await tapKey(tester, 'defaultTime-45');
    await tapKey(tester, 'saveQuizButton');

    expect(server.requestsWith('POST', '/api/quizzes'), isEmpty);
    expect(saved, isNotNull);
    final quiz = saved!.quiz;
    expect(quiz.title, 'Movie Night');
    expect(quiz.tags, ['movies', 'pub quiz', '80s']);
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
    expect(find.text('Add at least one tag.'), findsOneWidget);

    await tapKey(tester, 'suggestedTag-general');
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

  testWidgets('a public photo quiz keeps the photo and submits it', (
    tester,
  ) async {
    await openEditor(tester);

    await enter(tester, 'quizTitleField', 'Stills');
    await tapKey(tester, 'suggestedTag-movies');
    await tapKey(tester, 'visibilityPublic');
    expect(find.text('Save & submit'), findsOneWidget);
    await tapKey(tester, 'questionType-0-photo');
    await enter(tester, 'questionPrompt-0', 'Which film?');
    await enter(tester, 'answerInput-0', 'Alien');
    await tapKey(tester, 'addAnswer-0');
    await tapKey(tester, 'pickPhoto-0');

    expect(pickerCalls, 1);
    expect(find.byKey(const Key('photoPreview-0')), findsOneWidget);

    await tapKey(tester, 'saveQuizButton');

    // The photo went into the package, not to the uploads volume: nothing an
    // admin has not read is ever written there.
    expect(server.requestsWith('POST', '/api/images'), isEmpty);
    final queued = server.pending.single;
    expect(queued.hasPhotos, isTrue);
    final question = queued.document.questions!.single;
    expect(question.type, 'text_photo');
    expect(question.image!.key, isNull);
    expect(base64Decode(question.image!.data!).sublist(0, 3), [
      0xFF,
      0xD8,
      0xFF,
    ], reason: 'resized to JPEG, and carried inside the package');

    // Not public: it is waiting to be read, and playable here meanwhile.
    expect(saved?.publishedId, isNull);
    expect(saved?.inReview, isTrue);
    expect(server.quizzes, isEmpty);
    expect(saved!.quiz.questions!.single.image!.data, isNotNull);
  });

  testWidgets('editing a published quiz reorders and resubmits it', (
    tester,
  ) async {
    final existing = localQuiz(
      'local-1',
      'Old title',
      visibility: 'public',
      publishedId: 'pub-1',
      tags: const ['quiz night'],
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
    expect(find.byKey(const ValueKey('tag-quiz night')), findsOneWidget);

    await enter(tester, 'quizTitleField', 'New title');
    await tapKey(tester, 'moveDown-0');
    await tapKey(tester, 'addQuestionButton');
    await tapKey(tester, 'deleteQuestion-2');
    await tapKey(tester, 'saveQuizButton');

    // An edit of a public quiz is offered against it and goes back through the
    // queue; the published version stays as it was until somebody reads this.
    expect(server.lastWith('PUT', '/api/quizzes/pub-1'), isNotNull);
    final queued = server.pending.single;
    expect(queued.replacesQuizId, 'pub-1');
    expect(queued.document.title, 'New title');
    expect(queued.document.questions!.map((q) => q.prompt), [
      'Second',
      'First',
    ]);
    expect(server.quizzes.single.title, 'Old title');
    expect(saved?.localId, 'local-1');
    expect(saved?.quiz.tags, ['quiz night']);
    expect(saved?.quiz.questions!.first.difficulty, 'hard');
    expect(await tester.runAsync(stored), hasLength(1));
  });

  testWidgets('a failed submission says the quiz was still saved', (
    tester,
  ) async {
    await openEditor(tester);
    server.failWrites = true;

    await enter(tester, 'quizTitleField', 'Quiz');
    await tapKey(tester, 'suggestedTag-general');
    await tapKey(tester, 'visibilityPublic');
    await enter(tester, 'questionPrompt-0', 'Why?');
    await enter(tester, 'answerInput-0', 'Because');
    await tapKey(tester, 'saveQuizButton');

    expect(find.textContaining('could not be sent for review'), findsOneWidget);
    expect(saved, isNull);
    final quizzes = (await tester.runAsync(stored))!;
    expect(quizzes.single.wantsPublic, isTrue);
    expect(quizzes.single.inReview, isFalse);

    // Saving again reuses the same local quiz.
    server.failWrites = false;
    await tapKey(tester, 'saveQuizButton');
    expect(saved?.inReview, isTrue);
    expect(await tester.runAsync(stored), hasLength(1));
  });
}
