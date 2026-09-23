import 'package:args/command_runner.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/quizzes/quiz_library.dart';

import '../context.dart';
import '../pack.dart';
import 'play_options.dart';

/// This machine's quizzes — the app's "My quizzes" — through the app's own
/// [QuizLibrary] (`Context.library`). Every command here is one thing a person
/// does in the app's quiz browser, and runs the same code: saving a quiz on the
/// device, sending it for review, learning what became of it, making it private
/// again, deleting it, and keeping a public quiz for offline play.
///
/// A quiz in the library is named by the start of its local id, by its title or
/// by its slug, and `@<that>` hosts it (`fazoura host --quiz @film`), sent whole
/// the way the app hosts one of its own.
List<Command<int>> libraryCommands(Context context) => [
  _Mine(context),
  _Import(context),
  _Publish(context),
  _Unpublish(context),
  _Forget(context),
  _Save(context),
  _Submit(context),
];

/// The library entry [reference] names: the start of a local id (four
/// characters at least), or a title or slug, ignoring case.
Future<LocalQuiz> findLocal(Context context, String reference) async {
  final wanted = reference.toLowerCase();
  final all = await context.library.list();
  final matches = [
    for (final local in all)
      if ((wanted.length >= 4 && local.localId.startsWith(wanted)) ||
          local.quiz.title.toLowerCase() == wanted ||
          local.quiz.slug?.toLowerCase() == wanted)
        local,
  ];
  if (matches.length == 1) return matches.single;
  if (matches.isEmpty) {
    throw UsageError(
      'no quiz "$reference" in this machine\'s library — try quiz mine',
    );
  }
  throw UsageError(
    '"$reference" could be ${matches.map((m) => '${_short(m)} ${m.quiz.title}').join(', ')}'
    ' — use more of the id',
  );
}

String _short(LocalQuiz local) => local.localId.substring(0, 8);

/// Where a library quiz stands with the server, as the app's browser says it.
String _status(LocalQuiz local) {
  if (local.wasRejected) {
    final note = local.submission?.reviewNote;
    return 'turned down${note == null ? '' : ': "$note"'}';
  }
  if (local.inReview) {
    return local.isPublished ? 'public, edit in review' : 'in review';
  }
  if (local.isPublished) return 'public';
  if (!local.inSync) return 'not sent yet — publish again';
  return 'private';
}

Map<String, Object?> _json(LocalQuiz local) => {
  'local_id': local.localId,
  'title': local.quiz.title,
  'status': _status(local),
  'published_id': local.publishedId,
  'submission': local.submission?.toJson(),
  'questions': local.quiz.questions?.length ?? 0,
};

abstract class _LibraryCommand extends Command<int> {
  _LibraryCommand(this.context);

  final Context context;

  String single(String what) {
    final rest = argResults!.rest;
    if (rest.length != 1) throw UsageError('$name needs exactly one $what');
    return rest.single;
  }

  /// Runs a library change and reports it, turning the app's [PublishError] —
  /// saved on this machine, but the server step failed — into what it means.
  Future<int> change(Future<LocalQuiz> Function() action, String verb) async {
    try {
      final local = await action();
      context.output.result(
        _json(local),
        () => '$verb ${_short(local)} ${local.quiz.title} · ${_status(local)}',
      );
      return 0;
    } on PublishError catch (error) {
      context.output.error(
        'saved on this machine, but the server did not take it: ${error.cause}',
      );
      return 1;
    }
  }
}

class _Mine extends _LibraryCommand {
  _Mine(super.context) {
    argParser.addFlag(
      'offline',
      negatable: false,
      help: "Don't ask the server what became of submissions.",
    );
  }

  @override
  String get name => 'mine';

  @override
  String get description =>
      "This machine's quizzes, and what became of the ones sent for review.";

  @override
  Future<int> run() async {
    // As the app does when its browser opens: the only way a device learns
    // that somebody read the queue.
    final quizzes = argResults!.flag('offline')
        ? await context.library.list()
        : await context.library.refreshSubmissions();
    context.output.result(
      [for (final local in quizzes) _json(local)],
      () => [
        for (final local in quizzes)
          '${_short(local)}  ${local.quiz.title}'
              ' · ${local.quiz.questions?.length ?? 0} q · ${_status(local)}',
        if (quizzes.isEmpty) 'nothing here yet — quiz import <folder>',
      ].join('\n'),
    );
    return 0;
  }
}

class _Import extends _LibraryCommand {
  _Import(super.context) {
    argParser.addOption(
      'into',
      help:
          'Replace the contents of a quiz already in the library, keeping '
          'where it stands — republishing it offers an edit, as the app does.',
      valueHelp: 'quiz',
    );
  }

  @override
  String get name => 'import';

  @override
  String get description =>
      "Save a .fazoura, folder or document into this machine's library, private.";

  @override
  String get invocation => 'fazoura quiz import <quiz> [--into <library quiz>]';

  @override
  Future<int> run() async {
    final document = loadQuiz(
      single('.fazoura, folder or document'),
    ).toInlineDocument();
    final into = argResults!['into'] as String?;
    final existing = into == null ? null : await findLocal(context, into);
    final local = LocalQuiz(
      localId: existing?.localId ?? context.library.newLocalId(),
      publishedId: existing?.publishedId,
      submission: existing?.submission,
      quiz: document.copyWith(
        // What was published stays published until it is made private; an
        // import never quietly changes that.
        visibility: existing?.quiz.visibility ?? 'private',
      ),
    );
    return change(() => context.library.save(local), 'saved');
  }
}

class _Publish extends _LibraryCommand {
  _Publish(super.context);

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Send a library quiz for review (QUIZ_FORMAT.md §5.4). An edit of a public '
      'one goes through review too.';

  @override
  String get invocation => 'fazoura quiz publish <library quiz>';

  @override
  Future<int> run() async {
    final local = await findLocal(context, single('library quiz'));
    return change(() => context.library.setPublic(local, true), 'sent');
  }
}

class _Unpublish extends _LibraryCommand {
  _Unpublish(super.context);

  @override
  String get name => 'unpublish';

  @override
  String get description =>
      'Make a library quiz private again: withdrawn from review, or taken off '
      'the server.';

  @override
  String get invocation => 'fazoura quiz unpublish <library quiz>';

  @override
  Future<int> run() async {
    final local = await findLocal(context, single('library quiz'));
    return change(
      () => context.library.setPublic(local, false),
      'made private',
    );
  }
}

class _Forget extends _LibraryCommand {
  _Forget(super.context);

  @override
  String get name => 'forget';

  @override
  String get description =>
      'Delete a quiz from this machine — unpublished and withdrawn first, as '
      'the app deletes one.';

  @override
  String get invocation => 'fazoura quiz forget <library quiz>';

  @override
  Future<int> run() async {
    final local = await findLocal(context, single('library quiz'));
    await context.library.delete(local);
    context.output.result({
      'forgotten': local.localId,
    }, () => 'forgot ${local.quiz.title}');
    return 0;
  }
}

class _Save extends _LibraryCommand {
  _Save(super.context);

  @override
  String get name => 'save';

  @override
  String get description =>
      'Keep a public quiz in the library, photos and all, to host without a '
      'network — the app\'s "Save offline".';

  @override
  String get invocation => 'fazoura quiz save <id or slug>';

  @override
  Future<int> run() async {
    final summary = await context.quizzes.get(single('id or slug'));
    return change(() => context.library.saveCommunityQuiz(summary), 'saved');
  }
}

class _Submit extends _LibraryCommand {
  _Submit(super.context);

  @override
  String get name => 'submit';

  @override
  String get description =>
      'import, then publish: save a quiz into the library and send it for '
      'review in one step.';

  @override
  String get invocation => 'fazoura quiz submit <quiz>';

  @override
  Future<int> run() async {
    final document = loadQuiz(
      single('.fazoura, folder or document'),
    ).toInlineDocument();
    final local = LocalQuiz(
      localId: context.library.newLocalId(),
      quiz: document.copyWith(visibility: 'public'),
    );
    return change(() => context.library.save(local), 'sent');
  }
}
