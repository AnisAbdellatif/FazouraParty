import 'dart:convert';

import 'package:sembast/sembast.dart';

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
    await _quizzes.record(quiz.localId).put(await _database, {
      'updated_at': quiz.updatedAt?.toUtc().toIso8601String() ?? '',
      // One JSON string keeps photo data out of sembast's field indexing.
      'json': jsonEncode(quiz.toJson()),
    });
  }

  Future<void> delete(String localId) async {
    await _quizzes.record(localId).delete(await _database);
  }

  static LocalQuiz _decode(Map<String, Object?> value) => LocalQuiz.fromJson(
    jsonDecode(value['json']! as String) as Map<String, dynamic>,
  );
}
