import 'dart:io';

import 'package:args/args.dart';
import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/quizzes/quiz_selection.dart';

import '../context.dart';
import '../pack.dart';
import '../play/bots.dart';
import 'library.dart';

/// Options that make a seat answer on its own. Shared by `join` and by a host
/// playing along with `host --name`.
void addAnswerOptions(ArgParser parser) {
  parser
    ..addOption(
      'answer',
      help: 'Answer every question with this, when nothing better is known.',
    )
    ..addMultiOption(
      'answers-from',
      help:
          'A quiz whose accepted answers the bot may use: an id, a slug, or a '
          '.json/.fazoura/folder. Repeatable.',
      valueHelp: 'quiz',
    )
    ..addOption(
      'accuracy',
      help: 'Chance of answering right when the answer is known.',
      defaultsTo: '1',
    )
    ..addOption(
      'skip',
      help: 'Chance of letting a question go by.',
      defaultsTo: '0',
    )
    ..addOption(
      'delay',
      help: 'Seconds before answering: one number, or a range like 1-4.',
      defaultsTo: '1-4',
    );
}

/// Whether any answering option was given, i.e. whether this seat is a bot.
bool wantsBot(ArgResults args) =>
    args.wasParsed('answer') ||
    (args['answers-from'] as List<String>).isNotEmpty ||
    args.wasParsed('accuracy') ||
    args.wasParsed('skip');

Future<AnswerPlan> answerPlan(Context context, ArgResults args) async {
  final sources = args['answers-from'] as List<String>;
  final quizzes = [
    for (final source in sources) await loadDocument(context, source),
  ];
  final (minDelay, maxDelay) = parseDelay(args['delay'] as String);
  return AnswerPlan(
    fixed: args['answer'] as String?,
    knowledge: AnswerPlan.learn(quizzes),
    accuracy: parseChance(args['accuracy'] as String, 'accuracy'),
    skip: parseChance(args['skip'] as String, 'skip'),
    minDelay: minDelay,
    maxDelay: maxDelay,
  );
}

/// A whole quiz, answers included: from disk, or downloaded (QUIZ_FORMAT.md
/// §5.3a — the same explicit download the app's "save offline" makes).
Future<QuizDocument> loadDocument(Context context, String source) async {
  if (source.startsWith('@')) {
    return (await findLocal(context, source.substring(1))).quiz;
  }
  if (FileSystemEntity.typeSync(source) != FileSystemEntityType.notFound) {
    return loadQuiz(source).toInlineDocument();
  }
  return context.quizzes.download(source);
}

/// What `host_select_quiz` takes for [source]: a path is sent inline, as the
/// app sends a quiz kept on the device, and an id or slug is a published quiz,
/// sent the way the app sends one ([selectPublishedQuiz]).
Future<QuizSelection> resolveSelection(
  Context context,
  String source, {
  required bool lan,
}) async {
  // A quiz in this machine's library goes the way the app sends one of its
  // own ("My quizzes").
  if (source.startsWith('@')) {
    return selectLocalQuiz(
      await findLocal(context, source.substring(1)),
      lan: lan,
    );
  }
  if (FileSystemEntity.typeSync(source) != FileSystemEntityType.notFound) {
    return InlineQuizSelection(loadQuiz(source).toInlineDocument());
  }
  return selectPublishedQuiz(context.quizzes, source, lan: lan);
}

double parseChance(String value, String name) {
  final chance = double.tryParse(value);
  if (chance == null || chance < 0 || chance > 1) {
    throw UsageError('--$name takes a number from 0 to 1');
  }
  return chance;
}

(Duration, Duration) parseDelay(String value) {
  final parts = value.split('-');
  final seconds = parts.map(double.tryParse).toList();
  if (seconds.any((s) => s == null || s < 0) || seconds.length > 2) {
    throw UsageError('--delay takes seconds, or a range like 1-4');
  }
  Duration of(double s) => Duration(milliseconds: (s * 1000).round());
  final low = of(seconds.first!);
  final high = of(seconds.last!);
  return low <= high ? (low, high) : (high, low);
}

/// A mistake in how the command was called: printed with the usage, exit 64.
class UsageError implements Exception {
  const UsageError(this.message);

  final String message;

  @override
  String toString() => message;
}
