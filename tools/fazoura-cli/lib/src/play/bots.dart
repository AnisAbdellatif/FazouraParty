import 'dart:async';
import 'dart:math';

import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/time/lock_in_timer.dart';

import 'seat.dart';

/// How a bot answers: what it knows, how often it is right, how long it takes.
///
/// A player never sees accepted answers before a question ends (AGENTS.md §4),
/// so a bot cannot find the right one by asking the room. It is *told*: given
/// the quizzes being played ([knowledge], from `--answers-from`), it looks the
/// prompt up. That is a testing aid, not a cheat the server allows — the same
/// documents are what the host selected.
class AnswerPlan {
  AnswerPlan({
    this.fixed,
    Map<String, List<String>>? knowledge,
    this.accuracy = 1,
    this.skip = 0,
    this.minDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 4),
    Random? random,
  }) : knowledge = knowledge ?? const {},
       _random = random ?? Random();

  /// Always this answer, unless [knowledge] knows better.
  final String? fixed;

  /// Accepted answers by prompt ([promptKey]).
  final Map<String, List<String>> knowledge;

  /// Chance of giving the right answer when it is known, 0..1.
  final double accuracy;

  /// Chance of letting a question go by without answering, 0..1.
  final double skip;

  final Duration minDelay;
  final Duration maxDelay;
  final Random _random;

  /// The accepted answers of every question in [quizzes], by prompt.
  static Map<String, List<String>> learn(Iterable<QuizDocument> quizzes) => {
    for (final quiz in quizzes)
      for (final question in quiz.questions ?? const <QuizQuestion>[])
        if (question.acceptedAnswers.isNotEmpty)
          promptKey(question.prompt): question.acceptedAnswers,
  };

  /// A prompt as a lookup key: case and spacing do not tell two apart.
  static String promptKey(String prompt) =>
      prompt.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// What to answer [question] with, or null to let it go by.
  String? answerFor(Question question) {
    if (_random.nextDouble() < skip) return null;
    final known = knowledge[promptKey(question.prompt)];
    if (known != null) {
      return _random.nextDouble() < accuracy
          ? known.first
          : 'not ${known.first}';
    }
    return fixed ?? _guesses[_random.nextInt(_guesses.length)];
  }

  Duration delay() {
    final spread = maxDelay.inMilliseconds - minDelay.inMilliseconds;
    return minDelay +
        Duration(milliseconds: spread <= 0 ? 0 : _random.nextInt(spread + 1));
  }

  static const _guesses = ['no idea', 'pass', 'maybe', 'forty two', 'blue'];
}

/// Answers every question put to [seat] according to [plan].
///
/// It keeps to the rules a person's phone does, with the phone's own timing
/// (`LockInTimer`): one answer per question, never while paused, and in
/// before the deadline — brought forward when the host ending the question
/// pulls the deadline in (PROTOCOL.md §6).
class PlayerBot {
  PlayerBot(this.seat, this.plan);

  final Seat seat;
  final AnswerPlan plan;

  StreamSubscription<RoomState>? _subscription;
  String? _answeredKey;

  /// The question being answered, its key, and when the bot means to answer
  /// it — chosen once per question, so later snapshots only ever bring the
  /// answer forward.
  (String, Question, int)? _pending;

  /// The app's own timing (`LockInTimer`): what a person's phone does with a
  /// typed answer is what a bot does with its chosen one.
  late final LockInTimer _lockIn = LockInTimer(onDue: _due);

  void start() {
    _subscription = seat.updates.listen(_onState);
    final current = seat.state;
    if (current != null) _onState(current);
  }

  void stop() {
    _lockIn.disarm();
    unawaited(_subscription?.cancel());
  }

  void _onState(RoomState state) {
    final question = state.question;
    final key = '${state.gameNumber}:${state.questionIndex}';
    final waiting =
        state.phase == Phase.question &&
        question != null &&
        state.you.playerId != null &&
        state.you.submission == null &&
        _answeredKey != key;

    if (!waiting) {
      _pending = null;
      _lockIn.disarm();
      return;
    }

    final pending = _pending;
    final at = pending != null && pending.$1 == key
        ? pending.$3
        : DateTime.now().millisecondsSinceEpoch + plan.delay().inMilliseconds;
    _pending = (key, question, at);
    // A paused question has no deadline, which disarms; the resume arms again.
    _lockIn.arm(
      deadline: state.deadline,
      offsetMs: seat.offsetMs,
      preferredAtLocalMs: at,
    );
  }

  void _due() {
    final pending = _pending;
    if (pending == null) return;
    unawaited(_answer(pending.$1, pending.$2));
  }

  Future<void> _answer(String key, Question question) async {
    _pending = null;
    _answeredKey = key;
    final answer = plan.answerFor(question);
    if (answer == null) {
      seat.note('skipped', {'question': question.id}, 'lets this one go');
      return;
    }
    if (await seat.send('submit', () => seat.connection.submit(answer))) {
      seat.note('submitted', {
        'question': question.id,
        'answer': answer,
      }, 'answers "$answer"');
    }
  }
}

/// What an automatic host does with its room.
class HostPlan {
  const HostPlan({
    this.selection = const [],
    this.configure,
    this.startWhen = 1,
    this.pace = const Duration(seconds: 3),
    this.games = 1,
    this.closeWhenDone = true,
  });

  /// Selected on joining, and again after every rematch.
  final List<QuizSelection> selection;

  /// Applied after every selection, which resets settings to the first quiz's
  /// defaults (PROTOCOL.md §6.4).
  final Configure? configure;

  /// Starts once this many players other than the host are connected.
  final int startWhen;

  /// How long answers and standings stay up before moving on.
  final Duration pace;

  /// Games to play in the room, rematching between them (§6.3).
  final int games;

  /// Close the room after the last game, rather than leave it to empty out.
  final bool closeWhenDone;
}

/// Lobby settings to apply; anything left null keeps the room's own value.
class Configure {
  const Configure({
    this.questionCount,
    this.timeLimit,
    this.difficultyScoring,
    this.difficulties,
  });

  final int? questionCount;
  final Duration? timeLimit;
  final bool? difficultyScoring;
  final List<String>? difficulties;

  bool get isEmpty =>
      questionCount == null &&
      timeLimit == null &&
      difficultyScoring == null &&
      difficulties == null;

  /// `host_configure` wants every field, so what was not asked for comes from
  /// [current]. A question count over what the pool holds is clamped rather
  /// than refused: "all of them" is what `--questions 999` means.
  Future<void> apply(GameConnection connection, GameSettings current) {
    final difficulties = this.difficulties ?? current.difficulties;
    return connection.hostConfigure(
      questionCount: min(
        questionCount ?? current.questionCount,
        current.maxQuestionCount,
      ),
      timeLimitMs: timeLimit?.inMilliseconds ?? current.timeLimitMs,
      difficultyMultiplier: difficultyScoring ?? current.difficultyMultiplier,
      difficulties: difficulties,
    );
  }
}

/// Selects the quizzes and applies the settings, as a host does in the lobby.
Future<bool> prepareLobby(
  Seat seat,
  List<QuizSelection> selection,
  Configure? configure,
) async {
  if (selection.isEmpty) return true;
  final selected = await seat.send(
    'select',
    () => seat.connection.hostSelectQuiz(selection),
  );
  if (!selected || configure == null || configure.isEmpty) return selected;
  final settings = await _settled(seat);
  if (settings == null) return false;
  return seat.send(
    'configure',
    () => configure.apply(seat.connection, settings),
  );
}

/// The settings once the snapshot carrying the new selection has arrived.
Future<GameSettings?> _settled(Seat seat) async {
  bool ready(RoomState? state) =>
      state != null && state.packTitles.isNotEmpty && state.settings != null;
  if (ready(seat.state)) return seat.state!.settings;
  final state = await seat.updates
      .firstWhere(ready)
      .timeout(const Duration(seconds: 10), onTimeout: () => seat.state!);
  return state.settings;
}

/// Runs a room from lobby to the last game without anybody at the keyboard.
class HostBot {
  HostBot(this.seat, this.plan);

  final Seat seat;
  final HostPlan plan;

  final _done = Completer<void>();
  final _handled = <String>{};
  StreamSubscription<RoomState>? _subscription;
  Timer? _timer;
  var _gamesStarted = 0;

  /// Completes once the last game is over and the room closed (or left).
  Future<void> get done => _done.future;

  void start() {
    _subscription = seat.updates.listen(_onState);
    final current = seat.state;
    if (current != null) _onState(current);
  }

  void stop() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    if (!_done.isCompleted) _done.complete();
  }

  void _once(String key, Duration after, Future<void> Function() action) {
    if (!_handled.add(key)) return;
    _timer?.cancel();
    _timer = Timer(after, () => unawaited(action()));
  }

  void _onState(RoomState state) {
    if (state.you.role != Role.host) return;
    final game = state.gameNumber;
    final spot = '$game:${state.questionIndex}';

    switch (state.phase) {
      case Phase.lobby when state.packTitles.isEmpty:
        // A rematch goes back to choosing (§6.3): choose the same again.
        if (game > 1) {
          _once(
            'select:$game',
            Duration.zero,
            () => prepareLobby(seat, plan.selection, plan.configure),
          );
        }
      case Phase.lobby:
        final others = state.players
            .where((p) => p.connected && p.id != state.you.playerId)
            .length;
        if (others >= plan.startWhen) {
          _once('start:$game', const Duration(milliseconds: 300), () async {
            _gamesStarted++;
            seat.note('auto', {'action': 'start'}, 'starting game $game');
            await seat.send('start', seat.connection.hostNext);
          });
        }
      case Phase.question:
        break;
      case Phase.scoring:
        _once(
          'scored:$spot',
          plan.pace,
          () => seat.send('next', seat.connection.hostNext),
        );
      case Phase.leaderboard:
        _once(
          'standings:$spot',
          plan.pace,
          () => seat.send('next', seat.connection.hostNext),
        );
      case Phase.finished:
        _once('finished:$game', plan.pace, () async {
          if (_gamesStarted < plan.games) {
            await seat.send('rematch', seat.connection.hostRematch);
            return;
          }
          if (plan.closeWhenDone) {
            await seat.send('close', seat.connection.hostClose);
          }
          stop();
        });
    }
  }
}
