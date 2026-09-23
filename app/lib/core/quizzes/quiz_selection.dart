import '../api/quiz_api.dart';
import '../connection/game_connection.dart';

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
