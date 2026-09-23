/// Pure game logic for one LAN-hosted room (PROTOCOL.md §4–§9).
///
/// Dart port of `server/lib/fazoura/game.ex`, deliberately kept structurally
/// close to it: same guards, same order of checks, same error codes, so the two
/// can be diffed when the protocol changes. Both are held to the same
/// `protocol/fixtures/` (AGENTS.md §8).
///
/// No timers, no sockets and no clock of its own: every function takes the
/// state (and `now` where time matters) and returns a new state. [LanRoom] is
/// the shell that owns the state and supplies the clock.
library;

import 'dart:math';

import 'answer.dart';
import 'pack.dart';

// Each constant below that the server also defines is held to
// protocol/fixtures/constants.json by test/core/protocol_constants_test.dart;
// "must equal" in their comments is that test, not a promise.

/// The compatibility boundary, and the only part of the version on the wire:
/// a host accepts any client sharing its major and refuses the rest with
/// `unsupported_protocol_version` (PROTOCOL.md §1.1, §4.1). Must equal
/// `Fazoura.Game.protocol_major/0`.
const protocolMajor = 9;

/// Which revision of that major this implementation is. Reported in every
/// snapshot and ignored by clients; it exists so a LAN host built from an
/// older tag can be told apart from the cloud. Must equal
/// `Fazoura.Game.protocol_minor/0`.
const protocolMinor = 6;

/// How long a question keeps waiting for a player whose connection has gone.
/// A locked screen or a walk past a thick wall drops the socket for a few
/// seconds while the player is still standing there, and being dropped already
/// costs them the skip penalty — losing the question to a blip as well would be
/// the game's fault, not theirs. Must equal `Fazoura.Game`'s
/// `@waiting_grace_ms` (PROTOCOL.md §6).
const waitingGraceMs = 5000;

/// How long a question stays open after the host ends it. A player who has
/// typed an answer but not locked it in has it sent for them just before the
/// deadline, so ending a question pulls the deadline in rather than scoring on
/// the spot — otherwise the host's button throws away every answer still being
/// typed. Must equal `Fazoura.Game.closing_window_ms/0` (PROTOCOL.md §6).
const closingWindowMs = 3000;
const minTimeLimitMs = 10000;
const maxTimeLimitMs = 120000;
const defaultTimeLimitMs = 30000;
const maxPlayers = 100;
const maxNameLength = 20;
const maxAnswerLength = 100;
const supportedDifficulties = ['easy', 'medium', 'hard'];

/// Points per question by difficulty, used when difficulty scoring is on (§9).
/// A wrong answer costs more on an easy question than on a hard one.
const _pointsByDifficulty = {
  'easy': (right: 10, wrong: -15),
  'medium': (right: 25, wrong: -10),
  'hard': (right: 50, wrong: -5),
};

/// Every question scores the same when difficulty scoring is off.
const _flatPoints = (right: 10, wrong: -10);

/// What letting a question go by costs, whatever its difficulty (§9).
const skipPoints = -10;

enum GamePhase {
  lobby,
  question,
  scoring,
  leaderboard,
  finished;

  String get wire => name;
}

/// Who is acting. The host is a distinct actor even when also playing, because
/// host permissions follow the token, not the player id.
sealed class Actor {
  const Actor();
}

class HostActor extends Actor {
  const HostActor({this.holder = true});

  /// Whether this connection still holds the host role. False once it has been
  /// transferred away (PROTOCOL.md §3.4).
  final bool holder;
}

class PlayerActor extends Actor {
  const PlayerActor(this.id);
  final String id;
}

/// Error codes are protocol codes (§4.2), raised so a caller can map them
/// straight onto a `phx_reply`.
class GameRuleError implements Exception {
  const GameRuleError(this.code);
  final String code;

  @override
  String toString() => 'GameRuleError($code)';
}

class GamePlayer {
  const GamePlayer({
    required this.id,
    required this.name,
    this.score = 0,
    this.connected = false,
    this.disconnectedAt,
    this.avatarHue = 0,
  });

  final String id;
  final String name;
  final int score;
  final bool connected;

  /// When their connection went away, so a question knows whether it is still
  /// worth waiting for them. Never leaves the host.
  final int? disconnectedAt;
  final int avatarHue;

  GamePlayer copyWith({
    int? score,
    bool? connected,
    int? disconnectedAt,
    bool clearDisconnectedAt = false,
  }) => GamePlayer(
    id: id,
    name: name,
    score: score ?? this.score,
    connected: connected ?? this.connected,
    disconnectedAt: clearDisconnectedAt
        ? null
        : disconnectedAt ?? this.disconnectedAt,
    avatarHue: avatarHue,
  );
}

class GameSubmission {
  const GameSubmission({
    required this.answer,
    required this.autoCorrect,
    required this.points,
    this.overrideVerdict,
  });

  final String answer;
  final bool autoCorrect;

  /// What the question was worth when this was submitted, so settings cannot
  /// move a score after the fact and an override recomputes the same way (§9).
  final ({int right, int wrong}) points;

  /// Null until the host overrides; then it wins over [autoCorrect].
  final bool? overrideVerdict;

  bool get correct => overrideVerdict ?? autoCorrect;

  int get delta => correct ? points.right : points.wrong;

  GameSubmission withOverride(bool verdict) => GameSubmission(
    answer: answer,
    autoCorrect: autoCorrect,
    points: points,
    overrideVerdict: verdict,
  );
}

class GameSettings {
  const GameSettings({
    required this.questionCount,
    required this.timeLimitMs,
    required this.difficultyMultiplier,
    required this.difficulties,
    required this.availableDifficulties,
  });

  final int questionCount;
  final int timeLimitMs;
  final bool difficultyMultiplier;

  /// The difficulties the host has chosen to play.
  final List<String> difficulties;

  /// The difficulties the pack actually contains, which is what bounds
  /// [difficulties]. Fixed for a selected quiz; the host cannot pick a
  /// difficulty no question has (§5.1).
  final List<String> availableDifficulties;
}

/// The whole state of one room. Mutated in place by the intent handlers, which
/// is safe because exactly one [LanRoom] owns one [Game] and Dart is
/// single-threaded per isolate.
class Game {
  Game({
    required this.roomCode,
    required this.pack,
    this.mode = 'lan',
    this.shuffleQuestions = true,
  }) : settings = _defaultSettings(pack),
       questionOrder = _shuffledOrder(
         _eligibleIndicesFor(pack, _availableDifficulties(pack)),
         shuffleQuestions,
       );

  final String roomCode;
  Pack pack;
  final String mode;

  /// False plays the pack in its written order. Only tests turn it off, so a
  /// scripted scenario knows which question comes next — the same
  /// `shuffle_questions?` option `Fazoura.Game.new/3` takes.
  final bool shuffleQuestions;

  GameSettings settings;
  GamePhase phase = GamePhase.lobby;
  int? questionIndex;
  int? deadline;
  int? pausedRemainingMs;
  String? hostPlayerId;
  int gameNumber = 1;

  /// Offset into the shuffled order for the current game.
  int questionOffset = 0;
  List<int> questionOrder;

  final Map<String, GamePlayer> players = {};
  final Map<String, GameSubmission> submissions = {};

  /// Who was in the room when the current question started. Only they can be
  /// charged for not answering it — a late joiner never saw it (§9).
  final Set<String> asked = {};

  /// Whole pack, at the first question's time limit (clamped to the range).
  static GameSettings _defaultSettings(Pack pack) {
    final time = switch (pack) {
      Pack(defaultTimeLimitMs: final ms?) => ms,
      Pack(questions: [final first, ...]) => first.timeLimitMs,
      _ => defaultTimeLimitMs,
    };
    final available = _availableDifficulties(pack);
    return GameSettings(
      questionCount: pack.questions.length,
      timeLimitMs: time.clamp(minTimeLimitMs, maxTimeLimitMs),
      difficultyMultiplier: pack.defaultDifficultyMultiplier,
      difficulties: available,
      availableDifficulties: available,
    );
  }

  int get _packSize => pack.questions.length;

  int get maxAllowedQuestionCount =>
      _eligibleIndices(settings.difficulties).length;

  void selectQuiz(Pack selected) {
    if (phase != GamePhase.lobby) {
      throw const GameRuleError('invalid_phase');
    }
    if (selected.questions.isEmpty) {
      throw const GameRuleError('empty_pack');
    }
    pack = selected;
    settings = _defaultSettings(selected);
    questionOffset = 0;
    questionOrder = _shuffledOrder(
      _eligibleIndicesFor(selected, settings.difficulties),
      shuffleQuestions,
    );
  }

  bool hasPlayer(String? id) => id != null && players.containsKey(id);

  /// The next time [tick] must run, if any: the question's own deadline, or a
  /// disconnected player's grace running out before it, whichever is sooner.
  int? get timerDeadline {
    if (phase != GamePhase.question || pausedRemainingMs != null) return null;
    final grace = _nextGraceExpiry;
    if (deadline == null) return grace;
    if (grace == null) return deadline;
    return grace < deadline! ? grace : deadline;
  }

  // --- Players -------------------------------------------------------------

  /// Adds a player. Throws [GameRuleError] with a join error code (§4.1).
  void addPlayer(String id, Object? name, {int avatarHue = 0}) {
    if (name is! String) throw const GameRuleError('invalid_name');
    final trimmed = name.trim();
    final length = trimmed.characters;

    if (length < 1 || length > maxNameLength) {
      throw const GameRuleError('invalid_name');
    }
    if (players.length >= maxPlayers) throw const GameRuleError('room_full');
    if (_nameTaken(trimmed)) throw const GameRuleError('name_taken');

    players[id] = GamePlayer(id: id, name: trimmed, avatarHue: avatarHue);
  }

  /// Makes the host a player too. A no-op if the host already plays, so a
  /// reconnecting host does not have to re-send a name (§4.1).
  void addHostPlayer(String id, Object? name, {int avatarHue = 0}) {
    if (hostPlayerId != null) return;
    addPlayer(id, name, avatarHue: avatarHue);
    hostPlayerId = id;
  }

  void setConnected(String? id, bool connected, int now) {
    if (id == null) return;
    final player = players[id];
    if (player == null) return;
    players[id] = player.copyWith(
      connected: connected,
      // Kept from the first drop, not refreshed: a phone flapping between two
      // access points must not renew its own grace indefinitely.
      disconnectedAt: connected ? null : player.disconnectedAt ?? now,
      clearDisconnectedAt: connected,
    );
  }

  bool _nameTaken(String name) {
    final key = name.toLowerCase();
    return players.values.any((p) => p.name.toLowerCase() == key);
  }

  /// A random hue (0..359) kept as far as possible from those already in the
  /// room, so two players never look alike. Server-assigned by design: every
  /// device must show the same colour for the same player (AGENTS.md §4).
  int pickAvatarHue([Random? random]) {
    final rng = random ?? Random();
    final used = players.values.map((p) => p.avatarHue).toList();
    final candidates = [for (var i = 0; i < 12; i++) rng.nextInt(360)];
    return candidates.reduce(
      (a, b) => _minHueDistance(a, used) >= _minHueDistance(b, used) ? a : b,
    );
  }

  static int _minHueDistance(int hue, List<int> used) {
    if (used.isEmpty) return 360;
    return used
        .map((other) => min((hue - other).abs(), 360 - (hue - other).abs()))
        .reduce(min);
  }

  // --- Intents -------------------------------------------------------------

  /// Applies one intent. Throws [GameRuleError] on refusal; the caller turns
  /// that into an error reply and leaves the state untouched.
  void handle(
    Actor actor,
    String event,
    Map<String, dynamic> payload,
    int now,
  ) {
    switch (actor) {
      case PlayerActor(:final id):
        // A promoted player holds the role even though they connected as a
        // player (PROTOCOL.md §3.4).
        if (event == 'submit') {
          _submit(id, payload, now);
        } else if (id == hostPlayerId) {
          handle(const HostActor(), event, payload, now);
        } else {
          throw const GameRuleError('not_host');
        }
      case HostActor():
        switch (event) {
          case 'submit':
            final id = hostPlayerId;
            if (id == null) throw const GameRuleError('not_player');
            _submit(id, payload, now);
          case 'host_next':
            _next(now);
          case 'host_pause':
            _pause(now);
          case 'host_resume':
            _resume(now);
          case 'host_override':
            _override(payload);
          case 'host_configure':
            _configure(payload);
          case 'host_rematch':
            _rematch();
          case 'host_transfer':
            _transfer(payload);
          case 'host_remove_player':
            _removePlayer(payload, now);
          // A LAN host has no public list to be on (PROTOCOL.md §3.5).
          case 'host_set_listed':
            throw const GameRuleError('cloud_only');
          default:
            throw const GameRuleError('invalid_payload');
        }
    }
  }

  void _submit(String id, Map<String, dynamic> payload, int now) {
    if (!hasPlayer(id)) throw const GameRuleError('unknown_player');
    _requirePhase(const [GamePhase.question]);
    if (pausedRemainingMs != null) throw const GameRuleError('paused');
    // Rejected after the deadline even if the phase has not flipped yet (§4.2).
    if (deadline == null || now >= deadline!) {
      throw const GameRuleError('invalid_phase');
    }
    if (submissions.containsKey(id)) {
      throw const GameRuleError('already_submitted');
    }

    final answer = _validateAnswer(payload['answer']);
    final question = currentQuestion!;

    submissions[id] = GameSubmission(
      answer: answer,
      autoCorrect: answerIsCorrect(answer, question.acceptedAnswers),
      points: pointsFor(question),
    );

    _endQuestionIfNobodyLeft(now);
  }

  /// The host ends the question (PROTOCOL.md §6): anyone still due an answer
  /// gets [closingWindowMs] for what they have typed to arrive, and a question
  /// already closing is left alone, so a second tap cannot cut the window
  /// short. A paused question resumes into the window — nobody can submit
  /// while it is paused.
  void _closeQuestion(int now) {
    if (asked.every((id) => _answeredOrGone(id, now))) {
      _scoreQuestion();
      return;
    }
    final remaining = pausedRemainingMs ?? deadline! - now;
    deadline = now + min(remaining, closingWindowMs);
    pausedRemainingMs = null;
  }

  /// Nobody left to wait for: everyone the question was asked of has either
  /// answered or been gone long enough that holding the room for them is only
  /// making everybody else wait (PROTOCOL.md §6).
  ///
  /// At least one answer is required, so a room whose players have all
  /// wandered off runs its clock down rather than racing through the pack
  /// unattended.
  void _endQuestionIfNobodyLeft(int now) {
    if (phase != GamePhase.question || pausedRemainingMs != null) return;
    if (submissions.isEmpty) return;
    if (asked.every((id) => _answeredOrGone(id, now))) _scoreQuestion();
  }

  bool _answeredOrGone(String id, int now) =>
      submissions.containsKey(id) || _gone(players[id], now);

  /// A screen that locked, or a tunnel, drops the socket for a few seconds
  /// while the player is still very much there — so a disconnection is not
  /// immediately taken as an answer nobody is coming. Someone who actually
  /// left stops counting once the grace is up.
  bool _gone(GamePlayer? player, int now) {
    if (player == null) return true;
    if (player.connected) return false;
    final since = player.disconnectedAt;
    return since != null && now - since >= waitingGraceMs;
  }

  /// When a disconnected player's grace runs out, if that is sooner than the
  /// question's own deadline — the room has to wake up and notice.
  int? get _nextGraceExpiry {
    int? soonest;
    for (final id in asked) {
      if (submissions.containsKey(id)) continue;
      final player = players[id];
      if (player == null || player.connected) continue;
      final since = player.disconnectedAt;
      if (since == null) continue;
      final at = since + waitingGraceMs;
      if (soonest == null || at < soonest) soonest = at;
    }
    return soonest;
  }

  void _next(int now) {
    switch (phase) {
      case GamePhase.lobby:
        if (_packSize == 0) throw const GameRuleError('quiz_required');
        _startQuestion(0, now);
      case GamePhase.question:
        _closeQuestion(now);
      case GamePhase.scoring:
        phase = GamePhase.leaderboard;
      case GamePhase.leaderboard:
        final next = questionIndex! + 1;
        if (next < settings.questionCount) {
          _startQuestion(next, now);
        } else {
          phase = GamePhase.finished;
          submissions.clear();
        }
      case GamePhase.finished:
        throw const GameRuleError('invalid_phase');
    }
  }

  void _pause(int now) {
    _requirePhase(const [GamePhase.question]);
    if (pausedRemainingMs != null) throw const GameRuleError('paused');
    pausedRemainingMs = max(deadline! - now, 0);
    deadline = null;
  }

  void _resume(int now) {
    _requirePhase(const [GamePhase.question]);
    final remaining = pausedRemainingMs;
    if (remaining == null) throw const GameRuleError('not_paused');
    deadline = now + remaining;
    pausedRemainingMs = null;
  }

  void _override(Map<String, dynamic> payload) {
    _requirePhase(const [GamePhase.scoring, GamePhase.leaderboard]);
    final id = payload['player_id'];
    final correct = payload['correct'];
    if (id is! String || correct is! bool) {
      throw const GameRuleError('invalid_payload');
    }
    if (!hasPlayer(id)) throw const GameRuleError('unknown_player');

    final old = submissions[id];
    if (old == null) throw const GameRuleError('no_submission');

    final updated = old.withOverride(correct);
    // Re-apply the difference, so an override equal to the auto verdict is a
    // no-op rather than double-counting (§6.1).
    final change = updated.delta - old.delta;
    submissions[id] = updated;
    players[id] = players[id]!.copyWith(score: players[id]!.score + change);
  }

  void _configure(Map<String, dynamic> payload) {
    _requirePhase(const [GamePhase.lobby]);
    final count = payload['question_count'];
    final time = payload['time_limit_ms'];
    final bonus = payload['difficulty_multiplier'];
    final raw = payload['difficulties'];

    if (count is! int || time is! int || bonus is! bool) {
      throw const GameRuleError('invalid_settings');
    }

    // A payload that names no difficulties keeps the ones already selected,
    // and then may not ask for more questions than those difficulties have —
    // there is no new selection to clamp against.
    final keepsSelection = raw is! List;
    if (keepsSelection && count > maxAllowedQuestionCount) {
      throw const GameRuleError('invalid_settings');
    }

    final selected = keepsSelection
        ? settings.difficulties
        : raw.toSet().toList();
    final eligible = _eligibleIndices(selected).length;

    if (selected.isEmpty ||
        selected.any(
          (difficulty) =>
              !supportedDifficulties.contains(difficulty) ||
              !settings.availableDifficulties.contains(difficulty),
        ) ||
        count < 1 ||
        eligible < 1 ||
        // Narrowing the difficulties shrinks the pool, so a count from before
        // is clamped rather than refused; asking for more than the current
        // selection holds is a mistake worth reporting (§6.2).
        (count > eligible && _sameDifficulties(selected)) ||
        time < minTimeLimitMs ||
        time > maxTimeLimitMs) {
      throw const GameRuleError('invalid_settings');
    }

    settings = GameSettings(
      questionCount: min(count, eligible),
      timeLimitMs: time,
      difficultyMultiplier: bonus,
      difficulties: [for (final difficulty in selected) difficulty as String],
      availableDifficulties: settings.availableDifficulties,
    );
    questionOffset = 0;
    questionOrder = _shuffledOrder(
      _eligibleIndices(settings.difficulties),
      shuffleQuestions,
    );
  }

  bool _sameDifficulties(List<Object?> selected) {
    final current = settings.difficulties;
    if (selected.length != current.length) return false;
    for (var i = 0; i < selected.length; i++) {
      if (selected[i] != current[i]) return false;
    }
    return true;
  }

  /// Moves the role to a player. The room shell checks they are connected and
  /// mints their new token; this only moves it within the game state.
  void _transfer(Map<String, dynamic> payload) {
    final id = payload['player_id'];
    if (id is! String) throw const GameRuleError('invalid_payload');
    if (!hasPlayer(id)) throw const GameRuleError('unknown_player');
    hostPlayerId = id;
  }

  /// Takes a player out of the room (PROTOCOL.md §4.2): gone from the players,
  /// from this question's answers and from the people it was asked of, so it
  /// costs nobody a penalty and holds nobody up. The host's own seat is not the
  /// host's to remove — handing the role over is how a host leaves.
  void _removePlayer(Map<String, dynamic> payload, int now) {
    final id = payload['player_id'];
    if (id is! String) throw const GameRuleError('invalid_payload');
    if (!hasPlayer(id)) throw const GameRuleError('unknown_player');
    if (id == hostPlayerId) throw const GameRuleError('invalid_payload');
    players.remove(id);
    submissions.remove(id);
    asked.remove(id);
    _endQuestionIfNobodyLeft(now);
  }

  void _rematch() {
    _requirePhase(const [GamePhase.finished]);
    for (final entry in players.entries) {
      players[entry.key] = entry.value.copyWith(score: 0);
    }
    // The room stays, the players stay, the quiz does not: a rematch drops
    // back to the lobby so the host can pick what to play next (§6.3).
    pack = const Pack.empty();
    settings = _defaultSettings(pack);
    questionOffset = 0;
    questionOrder = [];
    phase = GamePhase.lobby;
    questionIndex = null;
    deadline = null;
    pausedRemainingMs = null;
    submissions.clear();
    asked.clear();
    gameNumber += 1;
  }

  /// Ends the current question if its deadline has passed, or if there is
  /// nobody left to wait for. Call before handling anything, so an intent
  /// can't slip in after time is up.
  void tick(int now) {
    if (phase != GamePhase.question) return;
    if (deadline != null && now >= deadline!) {
      _scoreQuestion();
      return;
    }
    // Not only after a submission: the last person the room was waiting for
    // may be one whose grace has just run out, and nothing else would notice.
    _endQuestionIfNobodyLeft(now);
  }

  void _startQuestion(int index, int now) {
    phase = GamePhase.question;
    questionIndex = index;
    deadline = now + settings.timeLimitMs;
    pausedRemainingMs = null;
    submissions.clear();
    asked
      ..clear()
      ..addAll(players.keys);
  }

  /// What the current question did to [id]: their submission's delta, the skip
  /// penalty if they were asked and said nothing, or nothing at all for
  /// someone who joined mid-question (§9).
  int? questionDelta(String id) {
    final submission = submissions[id];
    if (submission != null) return submission.delta;
    return asked.contains(id) ? skipPoints : null;
  }

  void _scoreQuestion() {
    for (final id in players.keys.toList()) {
      final change = questionDelta(id);
      if (change != null) {
        players[id] = players[id]!.copyWith(score: players[id]!.score + change);
      }
    }
    phase = GamePhase.scoring;
    deadline = null;
    pausedRemainingMs = null;
  }

  void _requirePhase(List<GamePhase> allowed) {
    if (!allowed.contains(phase)) throw const GameRuleError('invalid_phase');
  }

  static String _validateAnswer(Object? answer) {
    if (answer is! String) throw const GameRuleError('invalid_answer');
    final trimmed = answer.trim();
    if (trimmed.characters < 1 || trimmed.characters > maxAnswerLength) {
      throw const GameRuleError('invalid_answer');
    }
    return trimmed;
  }

  /// What [question] is worth under the current settings (§9).
  ({int right, int wrong}) pointsFor(PackQuestion question) =>
      settings.difficultyMultiplier
      ? (_pointsByDifficulty[question.difficulty] ?? _flatPoints)
      : _flatPoints;

  /// The shuffled pack is played from [questionOffset], wrapping around, at
  /// the host's chosen time limit (per-question pack limits are ignored, §6.2).
  PackQuestion? get currentQuestion {
    if (phase == GamePhase.lobby || phase == GamePhase.finished) return null;
    final index = questionIndex;
    if (index == null || questionOrder.isEmpty) return null;
    // Wraps on the *order*, not the pack: with a difficulty selected, the
    // order holds only the eligible questions and is the shorter of the two.
    final orderIndex = (questionOffset + index) % questionOrder.length;
    final question = pack.questions[questionOrder[orderIndex]];
    return question.copyWith(timeLimitMs: settings.timeLimitMs);
  }

  static List<int> _shuffledOrder(List<int> indices, bool shuffle) {
    final order = List<int>.from(indices);
    if (shuffle) order.shuffle();
    return order;
  }

  static List<String> _availableDifficulties(Pack pack) => supportedDifficulties
      .where(
        (difficulty) =>
            pack.questions.any((question) => question.difficulty == difficulty),
      )
      .toList();

  static List<int> _eligibleIndicesFor(Pack pack, List<Object?> difficulties) =>
      [
        for (var index = 0; index < pack.questions.length; index++)
          if (difficulties.contains(pack.questions[index].difficulty)) index,
      ];

  List<int> _eligibleIndices(List<Object?> difficulties) =>
      _eligibleIndicesFor(pack, difficulties);
}

/// Grapheme-cluster length, the unit PROTOCOL.md §4.1 specifies for names and
/// answers. `String.length` counts UTF-16 code units, which would let a name of
/// 20 emoji through as 40.
extension on String {
  int get characters {
    var count = 0;
    for (var i = 0; i < length; i += 1) {
      final unit = codeUnitAt(i);
      // Skip the low surrogate of a pair: it is part of the same character.
      final isLowSurrogate = unit >= 0xDC00 && unit <= 0xDFFF;
      if (!isLowSurrogate) count += 1;
    }
    return count;
  }
}
