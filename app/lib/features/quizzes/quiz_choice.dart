/// What the host picked in the quiz browser.
///
/// Kept apart from the browser screen so that screens which only *handle* a
/// selection do not have to load the browser to name its type: the browser
/// pulls in the editor, the photo pipeline and `package:image` behind it, and
/// a guest who only ever joins a game should never download any of that
/// (`quiz_browser_screen.dart` is imported `deferred`).
library;

import '../../core/models/models.dart';

sealed class QuizChoice {
  const QuizChoice();
}

/// A quiz stored on the server (built-in or published), hosted by id.
final class PublicQuizChoice extends QuizChoice {
  const PublicQuizChoice(this.quiz);

  final QuizDocument quiz;
}

/// One of this device's quizzes.
final class LocalQuizChoice extends QuizChoice {
  const LocalQuizChoice(this.quiz);

  final LocalQuiz quiz;
}
