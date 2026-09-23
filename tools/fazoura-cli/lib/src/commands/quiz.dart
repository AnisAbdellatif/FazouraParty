import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fazoura_party/core/models/models.dart';

import '../context.dart';
import '../pack.dart';
import 'play_options.dart';

/// Everything the app does with quizzes, from the terminal.
class QuizCommand extends Command<int> {
  QuizCommand(Context context) {
    addSubcommand(_List(context));
    addSubcommand(_Tags(context));
    addSubcommand(_Show(context));
    addSubcommand(_Download(context));
    addSubcommand(_Archive(context));
    addSubcommand(_Pack(context));
    addSubcommand(_Inspect(context));
    addSubcommand(_Init(context));
    addSubcommand(_Submit(context));
    addSubcommand(_Submissions(context));
    addSubcommand(_Withdraw(context));
    addSubcommand(_Delete(context));
    addSubcommand(_Report(context));
  }

  @override
  String get name => 'quiz';

  @override
  String get description =>
      'Browse the library, and build, publish and manage quizzes.';
}

abstract class _QuizSubcommand extends Command<int> {
  _QuizSubcommand(this.context);

  final Context context;

  /// The one positional argument this command takes.
  String single(String what) {
    final rest = argResults!.rest;
    if (rest.length != 1) throw UsageError('$name needs exactly one $what');
    return rest.single;
  }
}

class _List extends _QuizSubcommand {
  _List(super.context) {
    argParser
      ..addOption('search', abbr: 's', help: 'Match a title or a tag.')
      ..addOption('tag', abbr: 't', help: 'Only quizzes with exactly this tag.')
      ..addOption('limit', defaultsTo: '20')
      ..addOption('offset', defaultsTo: '0');
  }

  @override
  String get name => 'list';

  @override
  String get description => 'Public quizzes in the library.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final page = await context.quizzes.list(
      query: args['search'] as String?,
      tag: args['tag'] as String?,
      limit: int.tryParse(args['limit'] as String) ?? 20,
      offset: int.tryParse(args['offset'] as String) ?? 0,
    );
    context.output.result(
      {
        'quizzes': [for (final quiz in page.quizzes) quiz.toJson()],
        'next_offset': page.nextOffset,
      },
      () => [
        for (final quiz in page.quizzes)
          '${(quiz.slug ?? quiz.hostId).padRight(38)} ${quiz.title}'
              ' · ${quiz.questionCount} q'
              '${quiz.hasPhotos ? ' · photos' : ''}'
              ' · ${quiz.tags.join(', ')}',
        if (page.nextOffset != null) '… more: --offset ${page.nextOffset}',
        if (page.quizzes.isEmpty) 'no quizzes',
      ].join('\n'),
    );
    return 0;
  }
}

class _Tags extends _QuizSubcommand {
  _Tags(super.context);

  @override
  String get name => 'tags';

  @override
  String get description => 'Tags in use, and the suggested ones.';

  @override
  Future<int> run() async {
    final tags = await context.quizzes.tags();
    context.output.result(
      {
        'popular': [
          for (final tag in tags.popular) {'tag': tag.tag, 'count': tag.count},
        ],
        'suggested': tags.suggested,
      },
      () =>
          '${tags.popular.map((t) => '${t.tag} (${t.count})').join(', ')}\n'
          'suggested: ${tags.suggested.join(', ')}',
    );
    return 0;
  }
}

class _Show extends _QuizSubcommand {
  _Show(super.context);

  @override
  String get name => 'show';

  @override
  String get description => 'One public quiz, as anybody sees it.';

  @override
  String get invocation => 'fazoura quiz show <id or slug>';

  @override
  Future<int> run() async {
    final quiz = await context.quizzes.get(single('id or slug'));
    context.output.result(quiz.toJson(), () => _describe(quiz));
    return 0;
  }
}

class _Download extends _QuizSubcommand {
  _Download(super.context) {
    argParser.addOption(
      'out',
      abbr: 'o',
      help: 'Write here instead of stdout.',
    );
  }

  @override
  String get name => 'download';

  @override
  String get description =>
      'The whole quiz, accepted answers included (QUIZ_FORMAT.md §5.3a).';

  @override
  String get invocation => 'fazoura quiz download <id or slug> [-o file]';

  @override
  Future<int> run() async {
    final quiz = await context.quizzes.download(single('id or slug'));
    final text = const JsonEncoder.withIndent('  ').convert(quiz.toJson());
    final out = argResults!['out'] as String?;
    if (out == null) {
      stdout.writeln(text);
    } else {
      File(out).writeAsStringSync('$text\n');
      context.output.result({'path': out}, () => out);
    }
    return 0;
  }
}

class _Archive extends _QuizSubcommand {
  _Archive(super.context) {
    argParser.addOption('out', abbr: 'o', help: 'Default: <id>.fazoura');
  }

  @override
  String get name => 'archive';

  @override
  String get description => 'A public quiz and its photos as a .fazoura file.';

  @override
  String get invocation => 'fazoura quiz archive <id or slug> [-o file]';

  @override
  Future<int> run() async {
    final id = single('id or slug');
    final bytes = await context.quizzes.downloadArchive(id);
    final out = (argResults!['out'] as String?) ?? '$id.fazoura';
    File(out).writeAsBytesSync(bytes);
    context.output.result({
      'path': out,
      'bytes': bytes.length,
    }, () => '$out · ${bytes.length ~/ 1024} KB');
    return 0;
  }
}

class _Pack extends _QuizSubcommand {
  _Pack(super.context) {
    argParser
      ..addOption(
        'quiz',
        abbr: 'q',
        help: 'The quiz document, when the folder holds more than one.',
      )
      ..addOption(
        'out',
        abbr: 'o',
        help: 'Where to write (default: <folder>.fazoura beside it).',
      );
  }

  @override
  String get name => 'pack';

  @override
  String get description =>
      'Build a .fazoura package from a folder of quiz JSON and photos '
      '(QUIZ_FORMAT.md §5.3b).';

  @override
  String get invocation => 'fazoura quiz pack <folder> [-q doc.json] [-o out]';

  @override
  Future<int> run() async {
    final folder = Directory(single('folder'));
    if (!folder.existsSync()) throw PackError('${folder.path} is not a folder');
    final named = argResults!['quiz'] as String?;
    final document = findDocument(folder, named == null ? null : File(named));
    final packed = packFolder(folder, document);
    final bytes = packed.encode();
    final target =
        (argResults!['out'] as String?) ??
        '${folder.absolute.path.replaceFirst(RegExp(r'/+$'), '')}.fazoura';
    File(target)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    context.output.result(
      {
        'path': target,
        'questions': packed.questionCount,
        'photos': packed.photos.length,
        'bytes': bytes.length,
      },
      () =>
          '$target · ${_count(packed.questionCount, 'question')}'
          ' · ${_count(packed.photos.length, 'photo')}'
          ' · ${(bytes.length / 1024).round()} KB',
    );
    return 0;
  }
}

class _Inspect extends _QuizSubcommand {
  _Inspect(super.context) {
    argParser.addOption(
      'extract',
      help: 'Also unpack the document and photos into this folder.',
      valueHelp: 'folder',
    );
  }

  @override
  String get name => 'inspect';

  @override
  String get description =>
      'Check a .fazoura, folder or document the way the server would, and '
      'say what is in it.';

  @override
  String get invocation => 'fazoura quiz inspect <quiz> [--extract folder]';

  @override
  Future<int> run() async {
    final packed = loadQuiz(single('.fazoura, folder or document'));
    final into = argResults!['extract'] as String?;
    if (into != null) {
      final folder = Directory(into)..createSync(recursive: true);
      packed.photos.forEach((path, bytes) {
        File('${folder.path}/$path')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes);
      });
      final slug = (packed.document['slug'] as String?) ?? 'quiz';
      File('${folder.path}/$slug.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(packed.document)}\n',
      );
    }
    final quiz = packed.toInlineDocument();
    context.output.result(
      {
        'title': quiz.title,
        'questions': packed.questionCount,
        'photos': packed.photos.length,
        'tags': quiz.tags,
        'extracted': ?into,
      },
      () =>
          '${_describe(quiz)}\n'
          '${_count(packed.photos.length, 'photo')}'
          '${into == null ? '' : ' · extracted to $into'}',
    );
    return 0;
  }
}

class _Init extends _QuizSubcommand {
  _Init(super.context) {
    argParser.addOption('title', help: 'Default: the folder name.');
  }

  @override
  String get name => 'init';

  @override
  String get description => 'Start a quiz folder from a template.';

  @override
  String get invocation => 'fazoura quiz init <folder> [--title "Film Night"]';

  @override
  Future<int> run() async {
    final folder = Directory(single('folder'));
    final slug = folder.absolute.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
    );
    final document = File('${folder.path}/$slug.json');
    if (document.existsSync()) {
      throw PackError('${document.path} already exists');
    }
    Directory('${folder.path}/media').createSync(recursive: true);
    final title = (argResults!['title'] as String?) ?? slug;
    document.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'format_version': formatVersion,
        'version': 1,
        'slug': slug,
        'title': title,
        'description': '',
        'language': 'en',
        'tags': ['general'],
        'default_settings': {'time_limit_ms': 30000, 'difficulty_multiplier': false},
        'questions': [
          {
            'type': 'text',
            'prompt': 'What is the capital of Australia?',
            'accepted_answers': ['Canberra'],
            'difficulty': 'easy',
          },
          {
            'type': 'text_photo',
            'prompt': 'Which city is this?',
            'accepted_answers': ['Paris'],
            'difficulty': 'medium',
            'image': {'path': 'media/replace-me.jpg', 'alt': 'Describe the photo'},
          },
        ],
      })}\n',
    );
    context.output.result(
      {'path': document.path},
      () =>
          '${document.path}\n'
          'Put photos in ${folder.path}/media, then: '
          'fazoura quiz pack ${folder.path}',
    );
    return 0;
  }
}

class _Submit extends _QuizSubcommand {
  _Submit(super.context) {
    argParser.addOption(
      'replaces',
      help: 'The published quiz this is a new version of.',
      valueHelp: 'quiz id',
    );
  }

  @override
  String get name => 'submit';

  @override
  String get description =>
      'Send a quiz for review. Nothing is public until somebody approves it '
      '(QUIZ_FORMAT.md §5.4).';

  @override
  String get invocation => 'fazoura quiz submit <quiz> [--replaces id]';

  @override
  Future<int> run() async {
    final source = single('.fazoura, folder or document');
    final bytes = source.endsWith('.fazoura')
        ? File(source).readAsBytesSync()
        : loadQuiz(source).encode();
    final submission = await context.quizzes.submit(
      bytes,
      replaces: argResults!['replaces'] as String?,
    );
    context.output.result(
      submission.toJson(),
      () => 'submission ${submission.id} · ${submission.status}',
    );
    return 0;
  }
}

class _Submissions extends _QuizSubcommand {
  _Submissions(super.context);

  @override
  String get name => 'submissions';

  @override
  String get description => 'What became of the quizzes sent from here.';

  @override
  Future<int> run() async {
    final submissions = await context.quizzes.submissions();
    context.output.result(
      [for (final submission in submissions) submission.toJson()],
      () => [
        for (final s in submissions)
          '${s.id} · ${s.status.padRight(8)} · ${s.title}'
              '${s.quizId == null ? '' : ' → ${s.quizId}'}'
              '${s.reviewNote == null ? '' : '\n    "${s.reviewNote}"'}',
        if (submissions.isEmpty) 'nothing submitted from here',
      ].join('\n'),
    );
    return 0;
  }
}

class _Withdraw extends _QuizSubcommand {
  _Withdraw(super.context);

  @override
  String get name => 'withdraw';

  @override
  String get description => 'Take back a submission still waiting for review.';

  @override
  String get invocation => 'fazoura quiz withdraw <submission id>';

  @override
  Future<int> run() async {
    final id = single('submission id');
    await context.quizzes.withdraw(id);
    context.output.result({'withdrawn': id}, () => 'withdrew $id');
    return 0;
  }
}

class _Delete extends _QuizSubcommand {
  _Delete(super.context);

  @override
  String get name => 'delete';

  @override
  String get description => 'Unpublish a quiz published from here.';

  @override
  String get invocation => 'fazoura quiz delete <quiz id>';

  @override
  Future<int> run() async {
    final id = single('quiz id');
    await context.quizzes.delete(id);
    context.output.result({'deleted': id}, () => 'unpublished $id');
    return 0;
  }
}

class _Report extends _QuizSubcommand {
  _Report(super.context) {
    argParser
      ..addOption(
        'reason',
        help: 'Why (QUIZ_FORMAT.md §5.9).',
        allowed: [for (final reason in quizReportReasons) reason.value],
        allowedHelp: {
          for (final reason in quizReportReasons) reason.value: reason.label,
        },
        mandatory: true,
      )
      ..addOption('note', help: 'Anything a reviewer should know.');
  }

  @override
  String get name => 'report';

  @override
  String get description => 'Report a public quiz.';

  @override
  String get invocation => 'fazoura quiz report <quiz id> --reason <reason>';

  @override
  Future<int> run() async {
    final id = single('quiz id');
    await context.quizzes.report(
      id,
      reason: argResults!['reason'] as String,
      note: argResults!['note'] as String?,
    );
    context.output.result({'reported': id}, () => 'reported $id');
    return 0;
  }
}

String _describe(QuizDocument quiz) => [
  '${quiz.title}${quiz.slug == null ? '' : ' (${quiz.slug})'}',
  if (quiz.description?.isNotEmpty ?? false) quiz.description!,
  '${_count(quiz.questions?.length ?? quiz.questionCount, 'question')}'
      ' · ${quiz.tags.join(', ')} · ${quiz.language}',
  for (final (index, question) in (quiz.questions ?? const []).indexed)
    '  ${index + 1}. [${question.difficulty}] ${question.prompt}'
        '${question.acceptedAnswers.isEmpty ? '' : ' → ${question.acceptedAnswers.join(' / ')}'}'
        '${question.hasPhoto ? ' (photo)' : ''}',
].join('\n');

String _count(int n, String thing) => n == 1 ? '1 $thing' : '$n ${thing}s';
