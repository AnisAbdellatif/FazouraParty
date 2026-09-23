import '../api/quiz_api.dart';
import '../connection/game_connection.dart';
import '../models/models.dart';

/// A published quiz as `host_select_quiz` should carry it (PROTOCOL.md §6.4),
/// for a room on the cloud server or on a LAN host.
///
/// The two hosts want opposite things from the same pick. Cloud already has the
/// quiz and takes its id. A LAN host has no quiz database, so the whole
/// document has to travel with the intent — and whole means `download`, not
/// `get`: an ordinary read answers without questions, because accepted answers
/// are never handed to anyone but the publisher (QUIZ_FORMAT.md §5.3 and
/// §5.3a). Sent from `get`, every public quiz reached a LAN room with nothing in
/// it and came back `empty_pack`.
///
/// Either way the wire shape is the same, which is why one selection can mix
/// these with quizzes a device holds itself, sent as [InlineQuizSelection].
/// Shared by the app's quiz browser and `tools/fazoura-cli`, so the rule is
/// decided once.
Future<QuizSelection> selectPublishedQuiz(
  QuizApi api,
  String id, {
  required bool lan,
}) async =>
    lan ? InlineQuizSelection(await api.download(id)) : StoredQuizSelection(id);

/// A quiz from this device's library as `host_select_quiz` should carry it.
///
/// A quiz the device holds is sent whole — it may be private, or carry edits
/// the server has not approved. The exception is an offline copy of somebody
/// else's published quiz (`QuizLibrary.saveCommunityQuiz`): the cloud server
/// already has that one, photos and all, so a cloud room is sent its id. That
/// keeps a big quiz from being uploaded again only to overflow the inline cap
/// (QUIZ_FORMAT.md §5.7), and lets it be played in a public room, which takes
/// published quizzes only (PROTOCOL.md §3.5). A LAN host has no library, so it
/// always gets the whole document — which is what the copy was saved for.
QuizSelection selectLocalQuiz(LocalQuiz local, {required bool lan}) {
  final publishedId = local.quiz.id;
  final offlineCopy =
      publishedId != null && !local.quiz.isOwner && local.publishedId == null;
  return offlineCopy && !lan
      ? StoredQuizSelection(publishedId)
      : InlineQuizSelection(local.quiz);
}
