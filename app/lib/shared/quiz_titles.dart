/// How a round is named from the quizzes it draws on (PROTOCOL.md §6.4).
///
/// The wire carries the titles as a list and leaves the wording to clients, so
/// this is the one place that decides it. Long selections are summarised
/// rather than listed: a phone-width lobby cannot show ten titles, and the
/// exact contents matter less than roughly what is being played.
library;

String describeQuizzes(List<String> titles, {String ifEmpty = ''}) =>
    switch (titles.length) {
      0 => ifEmpty,
      1 => titles.single,
      2 => '${titles[0]} & ${titles[1]}',
      _ => '${titles.first} & ${titles.length - 1} more',
    };
