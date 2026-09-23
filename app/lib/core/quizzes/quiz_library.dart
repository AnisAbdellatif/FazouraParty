import 'dart:convert';
import 'dart:math';

import '../api/quiz_api.dart';
import '../models/models.dart';
import '../storage/local_quiz_store.dart';
import 'quiz_archive.dart';

/// The local save worked but the server step (submitting or unpublishing)
/// failed.
class PublishError implements Exception {
  const PublishError(this.saved, this.cause);

  /// The quiz as now stored on the device.
  final LocalQuiz saved;
  final Object cause;

  @override
  String toString() => 'PublishError($cause)';
}

/// This device's quizzes (QUIZ_FORMAT.md §4). Everything is saved locally
/// first; a quiz the creator wants public is then sent for review as one
/// `.fazoura` package, and one made private again is removed from the server.
///
/// Publishing is never immediate. A submission waits in a queue until somebody
/// reads it, so [save] leaves the quiz playable on this device — hosting a
/// private quiz sends it inline and never touches the server's library — and
/// [refreshSubmissions] is what eventually notices that it went public.
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
    var saved = quiz.copyWith(updatedAt: _now(), archiveData: null);
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
    String? archiveData;
    QuizDocument full;
    try {
      final archive = await api.downloadArchive(summary.hostId);
      full = QuizArchive.decode(archive).quiz;
      archiveData = base64Encode(archive);
    } on GameError catch (error) {
      if (error.code != 'quiz_archive_download_failed') rethrow;
      full = await _downloadLegacy(summary);
    } on FormatException {
      full = await _downloadLegacy(summary);
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
      ),
      archiveData: archiveData,
    );
    await store.put(saved);
    return saved;
  }

  Future<QuizDocument> _downloadLegacy(QuizDocument summary) async {
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
    return full.copyWith(questions: questions);
  }

  Future<LocalQuiz> setPublic(LocalQuiz quiz, bool public) => save(
    quiz.copyWith(
      quiz: quiz.quiz.copyWith(visibility: public ? 'public' : 'private'),
    ),
  );

  /// Unpublishes (if needed) and removes the quiz from this device.
  Future<void> delete(LocalQuiz quiz) async {
    // Including anything of it still waiting to be read. Otherwise deleting a
    // quiz would leave its submission in the queue, and approving that would
    // publish something its author had thrown away.
    await _withdraw(quiz);
    if (quiz.publishedId != null) await _unpublish(quiz.publishedId!);
    await store.delete(quiz.localId);
  }

  /// Asks the server what became of the submissions this device sent, and
  /// brings the local library in line with the answers.
  ///
  /// This is the only way a device learns that its quiz went public: approval
  /// happens when somebody reads the queue, which may be days later and is
  /// certainly not while the app is open. Quietly does nothing when the server
  /// can't be reached — an unanswered question about a quiz that is playable
  /// either way is not worth an error.
  Future<List<LocalQuiz>> refreshSubmissions() async {
    final List<QuizSubmission> submissions;
    try {
      submissions = await api.submissions();
    } catch (_) {
      return list();
    }
    final byId = {
      for (final submission in submissions) submission.id: submission,
    };

    for (final quiz in await list()) {
      final sent = quiz.submission;
      if (sent == null) continue;
      // A submission the server has forgotten (withdrawn elsewhere, or a reset)
      // leaves the quiz where it was rather than stuck claiming to be in a
      // queue it isn't in.
      final current = byId[sent.id];
      final settled = current == null ? null : _settle(quiz, current);
      if (current == null) {
        await store.put(quiz.copyWith(submission: null));
      } else if (settled != null) {
        await store.put(settled);
      }
    }
    return list();
  }

  /// What an answered submission does to the quiz it was sent for. Returns null
  /// while it is still waiting, which is the common case.
  static LocalQuiz? _settle(LocalQuiz quiz, QuizSubmission submission) {
    if (submission.isApproved) {
      return quiz.copyWith(
        publishedId: submission.quizId ?? quiz.publishedId,
        submission: null,
      );
    }
    if (submission.isRejected) {
      // A turned-down *edit* leaves the quiz it was offered against exactly as
      // it was: still public, still the version somebody already approved. Only
      // the new contents were refused.
      if (submission.replacesQuizId != null) {
        return quiz.copyWith(submission: submission);
      }
      // Otherwise back to private: it is not public, and saving it again should
      // not silently re-queue it. The note stays so its author can read why and
      // decide whether to change it and submit again.
      return quiz.copyWith(
        quiz: quiz.quiz.copyWith(visibility: 'private'),
        submission: submission,
      );
    }
    return null;
  }

  Future<LocalQuiz> _sync(LocalQuiz quiz) async {
    if (quiz.wantsPublic) return _submit(quiz);
    await _withdraw(quiz);
    if (quiz.publishedId == null) return quiz.copyWith(submission: null);
    await _unpublish(quiz.publishedId!);
    return quiz.copyWith(publishedId: null, submission: null);
  }

  /// Sends the quiz for review as one package. An edit of an already-public
  /// quiz is offered against it, so approving replaces that quiz rather than
  /// adding a second copy.
  Future<LocalQuiz> _submit(LocalQuiz quiz) async {
    // At most one submission per quiz waits in the queue: saving twice before
    // anybody reads it should leave the later version there, not both.
    await _withdraw(quiz);
    final submission = await api.submit(
      QuizArchive.encode(quiz.quiz),
      replaces: quiz.publishedId,
    );
    return quiz.copyWith(submission: submission);
  }

  Future<void> _withdraw(LocalQuiz quiz) async {
    final submission = quiz.submission;
    if (submission == null || !submission.isPending) return;
    try {
      await api.withdraw(submission.id);
    } on GameError catch (error) {
      // Already read, already withdrawn, or never arrived. Either way there is
      // nothing of ours left in the queue, which is all this asked for.
      if (error.code != 'not_found') rethrow;
    }
  }

  Future<void> _unpublish(String id) async {
    try {
      await api.delete(id);
    } on GameError catch (error) {
      if (error.code != 'quiz_not_found') rethrow;
    }
  }
}
