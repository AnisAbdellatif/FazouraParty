import 'dart:convert';

import 'package:sembast/sembast.dart';

import '../quizzes/quiz_archive.dart';
import '../models/models.dart';

/// Quizzes made on this device, newest first.
class LocalQuizStore {
  LocalQuizStore(this._database);

  final Future<Database> _database;

  static final _quizzes = stringMapStoreFactory.store('quizzes');

  Future<List<LocalQuiz>> list() async {
    final records = await _quizzes.find(
      await _database,
      finder: Finder(sortOrders: [SortOrder('updated_at', false)]),
    );
    return [for (final record in records) _decode(record.value)];
  }

  Future<LocalQuiz?> get(String localId) async {
    final value = await _quizzes.record(localId).get(await _database);
    return value == null ? null : _decode(value);
  }

  Future<void> put(LocalQuiz quiz) async {
    final stored = quiz.archiveData == null
        ? quiz
        : quiz.copyWith(
            quiz: quiz.quiz.copyWith(
              questions: [
                for (final question
                    in quiz.quiz.questions ?? const <QuizQuestion>[])
                  question.image == null
                      ? question
                      : question.copyWith(
                          image: question.image!.copyWith(data: null),
                        ),
              ],
            ),
          );
    await _quizzes.record(quiz.localId).put(await _database, {
      'updated_at': stored.updatedAt?.toUtc().toIso8601String() ?? '',
      // One JSON string keeps photo data out of sembast's field indexing.
      'json': jsonEncode(stored.toJson()),
    });
  }

  Future<void> delete(String localId) async {
    await _quizzes.record(localId).delete(await _database);
  }

  static LocalQuiz _decode(Map<String, Object?> value) {
    final local = LocalQuiz.fromJson(
      jsonDecode(value['json']! as String) as Map<String, dynamic>,
    );
    final archiveData = local.archiveData;
    if (archiveData == null) return local;

    // The archive is kept for its photos, which `put` strips from the stored
    // document. Only the questions come back from it: the rest of the document
    // is this device's copy — private, not ours to publish — and the archive's
    // manifest says what the quiz was on the server, "public" included.
    // Taking all of it made every offline copy read back as a quiz this device
    // had failed to submit.
    try {
      final archived = QuizArchive.decode(base64Decode(archiveData)).quiz;
      return local.copyWith(
        quiz: local.quiz.copyWith(questions: archived.questions),
      );
    } on Object {
      // A truncated or corrupt archive costs that quiz its photos, not the
      // whole library: `_decode` runs for every row, so throwing here would
      // make one bad download hide every quiz on the device. The document
      // itself is still stored alongside the archive, so the quiz keeps its
      // prompts and answers and plays without images.
      return local;
    }
  }
}
