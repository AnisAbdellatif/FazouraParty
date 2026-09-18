import 'dart:convert';
import 'dart:math';

import '../api/quiz_api.dart';
import '../models/models.dart';
import '../storage/local_quiz_store.dart';

/// The local save worked but the server step (publish or unpublish) failed.
class PublishError implements Exception {
  const PublishError(this.saved, this.cause);

  /// The quiz as now stored on the device.
  final LocalQuiz saved;
  final Object cause;

  @override
  String toString() => 'PublishError($cause)';
}

/// This device's quizzes (QUIZ_FORMAT.md §4). Everything is saved locally
/// first; public quizzes are then published to the server and private ones
/// removed from it.
class QuizLibrary {
  QuizLibrary({
    required this.store,
    required this.api,
    DateTime Function()? now,
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final LocalQuizStore store;
  final QuizApi api;
  final DateTime Function() _now;
  final Random _random;

  Future<List<LocalQuiz>> list() => store.list();

  String newLocalId() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  /// Saves [quiz] on the device, then brings the server in line with its
  /// visibility. Throws [PublishError] if only the local save succeeded.
  Future<LocalQuiz> save(LocalQuiz quiz) async {
    var saved = quiz.copyWith(updatedAt: _now());
    await store.put(saved);
    try {
      saved = await _sync(saved);
    } catch (error) {
      throw PublishError(await store.get(saved.localId) ?? saved, error);
    }
    await store.put(saved);
    return saved;
  }

  /// Downloads a public quiz and all of its photos, then stores it privately
  /// on this device so it can be hosted without a network connection.
  Future<LocalQuiz> saveCommunityQuiz(QuizDocument summary) async {
    final full = await api.download(summary.hostId);
    final questions = <QuizQuestion>[];
    for (final question in full.questions ?? const <QuizQuestion>[]) {
      final image = question.image;
      if (question.hasPhoto && image?.url != null && image?.data == null) {
        final bytes = await api.downloadImage(image!.url!);
        questions.add(
          question.copyWith(
            image: image.copyWith(
              data: base64Encode(bytes),
              key: null,
              url: null,
            ),
          ),
        );
      } else {
        questions.add(question);
      }
    }
    final existing = (await list()).where(
      (local) => local.quiz.id == summary.id && !local.isPublished,
    );
    final saved = LocalQuiz(
      localId: existing.isEmpty ? newLocalId() : existing.first.localId,
      quiz: full.copyWith(
        id: full.id ?? summary.id,
        visibility: 'private',
        isOwner: false,
        questions: questions,
      ),
    );
    await store.put(saved);
    return saved;
  }

  Future<LocalQuiz> setPublic(LocalQuiz quiz, bool public) => save(
    quiz.copyWith(
      quiz: quiz.quiz.copyWith(visibility: public ? 'public' : 'private'),
    ),
  );

  /// Unpublishes (if needed) and removes the quiz from this device.
  Future<void> delete(LocalQuiz quiz) async {
    if (quiz.publishedId != null) await _unpublish(quiz.publishedId!);
    await store.delete(quiz.localId);
  }

  Future<LocalQuiz> _sync(LocalQuiz quiz) async {
    if (quiz.wantsPublic) return _publish(quiz);
    if (quiz.publishedId == null) return quiz;
    await _unpublish(quiz.publishedId!);
    return quiz.copyWith(publishedId: null);
  }

  Future<LocalQuiz> _publish(LocalQuiz quiz, {bool retried = false}) async {
    final withKeys = await _uploadPhotos(quiz);
    final body = withKeys.quiz.forPublishing();
    try {
      final id = withKeys.publishedId;
      final published = id == null
          ? await api.create(body)
          : await _replaceOrCreate(id, body);
      return withKeys.copyWith(publishedId: published.id);
    } on GameError catch (error) {
      // Uploaded photos can disappear (e.g. a server reset): upload again once.
      if (error.code != 'unknown_image' || retried) rethrow;
      return _publish(_withoutPhotoKeys(withKeys), retried: true);
    }
  }

  Future<QuizDocument> _replaceOrCreate(String id, QuizDocument body) async {
    try {
      return await api.replace(id, body);
    } on GameError catch (error) {
      if (error.code != 'quiz_not_found') rethrow;
      return api.create(body);
    }
  }

  Future<void> _unpublish(String id) async {
    try {
      await api.delete(id);
    } on GameError catch (error) {
      if (error.code != 'quiz_not_found') rethrow;
    }
  }

  static bool _needsUpload(QuizQuestion question) =>
      question.hasPhoto &&
      question.image?.key == null &&
      question.image?.data != null;

  /// Uploads photos that have no server key yet and stores the keys, so a
  /// later retry doesn't upload them again.
  Future<LocalQuiz> _uploadPhotos(LocalQuiz quiz) async {
    final questions = quiz.quiz.questions ?? const <QuizQuestion>[];
    if (!questions.any(_needsUpload)) return quiz;
    final updated = <QuizQuestion>[];
    for (final question in questions) {
      if (_needsUpload(question)) {
        final uploaded = await api.uploadImage(
          base64Decode(question.image!.data!),
        );
        updated.add(
          question.copyWith(image: question.image!.copyWith(key: uploaded.key)),
        );
      } else {
        updated.add(question);
      }
    }
    final result = quiz.copyWith(quiz: quiz.quiz.copyWith(questions: updated));
    await store.put(result);
    return result;
  }

  static LocalQuiz _withoutPhotoKeys(LocalQuiz quiz) => quiz.copyWith(
    quiz: quiz.quiz.copyWith(
      questions: [
        for (final question in quiz.quiz.questions ?? const <QuizQuestion>[])
          question.image == null
              ? question
              : question.copyWith(
                  image: question.image!.copyWith(key: null, url: null),
                ),
      ],
    ),
  );
}
