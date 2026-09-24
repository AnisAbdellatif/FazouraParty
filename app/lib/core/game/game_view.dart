/// What each connection to a LAN host is sent: the complete `RoomState`
/// snapshot of a game as one recipient sees it (PROTOCOL.md §5.1), with the
/// visibility rules of §7 applied.
///
/// Kept apart from [Game], as `Fazoura.Game.View` is kept apart from
/// `Fazoura.Game` on the server: the game decides what happens, this decides
/// who may see what. Every snapshot is complete, never a delta, so this is the
/// whole of the wire format for a room — and the two files are the ones to
/// compare when the two hosts disagree about it.
library;

import 'game.dart';
import 'pack.dart';

/// The complete `RoomState` snapshot of [game] as [recipient] sees it, at
/// [now]. Built per recipient, never broadcast identically, because `you`
/// differs and the visibility rules are the same for everyone including the
/// host (§7).
Map<String, dynamic> roomState(Game game, Actor recipient, int now) {
  final question = game.currentQuestion;
  // Same for every role: the host may be playing, so nobody gets an early
  // look at the answers or anyone else's guess (§7).
  final revealed = _scored(game);
  final settings = game.settings;

  return {
    'protocol_version': protocolMajor,
    'protocol_minor': protocolMinor,
    'room_code': game.roomCode,
    'mode': game.mode,
    'listed': false,
    'room_size': game.roomSize,
    'room_size_limit': game.roomSizeLimit,
    'phase': game.phase.wire,
    'server_time': now,
    'pack_titles': game.pack.questions.isEmpty
        ? const <String>[]
        : game.pack.titles,
    'question_index': game.questionIndex,
    'question_count': settings.questionCount,
    'game_number': game.gameNumber,
    'settings': {
      'question_count': settings.questionCount,
      'time_limit_ms': settings.timeLimitMs,
      'difficulty_multiplier': settings.difficultyMultiplier,
      'max_question_count': game.maxAllowedQuestionCount,
      'difficulties': settings.difficulties,
      'available_difficulties': settings.availableDifficulties,
      'min_time_limit_ms': minTimeLimitMs,
      'max_time_limit_ms': maxTimeLimitMs,
    },
    'question': question == null ? null : _question(game, question),
    'deadline': game.deadline,
    'paused_remaining_ms': game.pausedRemainingMs,
    'accepted_answers': question != null && revealed
        ? question.acceptedAnswers
        : null,
    'players': _players(game),
    'you': _you(game, recipient, question),
    'submissions': question != null && revealed ? _submissions(game) : null,
  };
}

bool _scored(Game game) =>
    game.phase == GamePhase.scoring || game.phase == GamePhase.leaderboard;

Map<String, dynamic> _question(Game game, PackQuestion question) {
  final points = game.pointsFor(question);
  return {
    'id': question.id,
    'type': question.type,
    'prompt': question.prompt,
    'image_url': question.imageUrl,
    'time_limit_ms': question.timeLimitMs,
    'difficulty': question.difficulty,
    'points': {
      'right': points.right,
      'wrong': points.wrong,
      'skipped': skipPoints,
    },
  };
}

List<Map<String, dynamic>> _players(Game game) {
  final tracksSubmissions = game.phase == GamePhase.question || _scored(game);

  // Listed field by field rather than serialising the player, so anything
  // the host keeps for its own bookkeeping — `disconnectedAt` — cannot reach
  // a broadcast just by existing (§5.1).
  return [
    for (final player in _sortedPlayers(game))
      {
        'id': player.id,
        'name': player.name,
        'score': player.score,
        'connected': player.connected,
        'has_submitted':
            tracksSubmissions && game.submissions.containsKey(player.id),
        'is_host': player.id == game.hostPlayerId,
        'avatar_hue': player.avatarHue,
      },
  ];
}

/// Score descending, then name ascending case-insensitively (§5.1).
List<GamePlayer> _sortedPlayers(Game game) =>
    game.players.values.toList()..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

/// Everyone the question was put to gets a row, so the scoring screen never
/// has to know what saying nothing costs: `answer: null` is the player who let
/// it go by.
List<Map<String, dynamic>> _submissions(Game game) => [
  for (final player in _sortedPlayers(game))
    if (game.questionDelta(player.id) case final change?)
      {
        'player_id': player.id,
        'answer': game.submissions[player.id]?.answer,
        'auto_correct': game.submissions[player.id]?.autoCorrect ?? false,
        'override': game.submissions[player.id]?.overrideVerdict,
        'correct': game.submissions[player.id]?.correct ?? false,
        'delta': change,
      },
];

Map<String, dynamic> _you(Game game, Actor recipient, PackQuestion? question) {
  // `role` reports who holds the role *now*, not how this connection
  // authenticated: after a transfer or promotion the two differ, and the
  // client has to be told the truth (PROTOCOL.md §3.4). `HostActor.holder`
  // is the room's record of whether the host connection is still the holder.
  final (role, id) = switch (recipient) {
    HostActor(:final holder) => (holder ? 'host' : 'player', game.hostPlayerId),
    PlayerActor(:final id) => (id == game.hostPlayerId ? 'host' : 'player', id),
  };

  final submission = question == null || id == null
      ? null
      : game.submissions[id];
  final scored = _scored(game);
  // From scoring on, a player who said nothing is told what that cost them.
  final skipped =
      scored && submission == null && id != null && game.asked.contains(id);

  return {
    'role': role,
    'player_id': id,
    // Filled in by the room shell for the one recipient who was just given
    // the role; the game itself has no tokens.
    'host_token': null,
    'submission': switch (submission) {
      final s? => {
        'answer': s.answer,
        'correct': scored ? s.correct : null,
        'delta': scored ? s.delta : null,
      },
      _ when skipped => {'answer': null, 'correct': false, 'delta': skipPoints},
      _ => null,
    },
  };
}
