import 'package:fazoura_party/core/models/models.dart';

/// What changed between two snapshots, in words.
///
/// Every `state` is a complete `RoomState` (PROTOCOL.md §5.1), never a delta,
/// so the story of a game has to be recovered by comparing consecutive ones.
/// That is all this does: it holds no state of its own and never talks to the
/// server, so what it says is exactly what the snapshots say.
List<String> narrate(RoomState? before, RoomState now) {
  final lines = <String>[];
  final names = {for (final player in now.players) player.id: player.name};
  String nameOf(String id) => names[id] ?? id;

  if (before == null) {
    final count = now.players.length;
    lines.add(
      'in room ${now.roomCode} as ${now.you.role.name}'
      '${now.you.playerId == null ? '' : ' (${nameOf(now.you.playerId!)})'}'
      ' · ${now.phase.name} · ${_count(count, 'player')}'
      '${now.roomSize == null ? '' : ' of ${now.roomSize}'}'
      '${now.listed ? ' · public' : ''}',
    );
    if (now.packTitles.isNotEmpty) lines.add(_quizzes(now));
    if (now.phase == Phase.question) lines.addAll(_question(now));
    return lines;
  }

  if (before.you.role != now.you.role) {
    lines.add(
      now.you.role == Role.host
          ? 'you are now the host'
          : 'you are no longer the host',
    );
  }

  final earlier = {for (final player in before.players) player.id: player};
  for (final player in now.players) {
    final was = earlier[player.id];
    if (was == null) {
      lines.add('+ ${player.name} joined');
      continue;
    }
    if (was.connected && !player.connected) lines.add('${player.name} dropped');
    if (!was.connected && player.connected) lines.add('${player.name} is back');
    if (!was.isHost && player.isHost) {
      lines.add('${player.name} is now the host');
    }
    if (now.phase == Phase.question &&
        before.phase == Phase.question &&
        before.questionIndex == now.questionIndex &&
        !was.hasSubmitted &&
        player.hasSubmitted) {
      final done = now.players.where((p) => p.hasSubmitted).length;
      lines.add('${player.name} answered ($done/${now.players.length})');
    }
  }

  if (before.roomSizeLimit != now.roomSizeLimit) {
    lines.add('room size unlocked up to ${now.roomSizeLimit}');
  }
  if (before.roomSize != now.roomSize && now.roomSize != null) {
    lines.add('room size ${now.roomSize}');
  }
  if (before.listed != now.listed) {
    lines.add(now.listed ? 'room is now public' : 'room is now code-only');
  }

  if (now.gameNumber != before.gameNumber) {
    lines.add('rematch · game ${now.gameNumber}');
  }

  if (now.phase == Phase.lobby &&
      (!_sameList(before.packTitles, now.packTitles) ||
          before.settings != now.settings) &&
      now.packTitles.isNotEmpty) {
    lines.add(_quizzes(now));
  }

  final newQuestion =
      now.phase == Phase.question &&
      (before.phase != Phase.question ||
          before.questionIndex != now.questionIndex ||
          before.gameNumber != now.gameNumber);
  if (newQuestion) {
    lines.addAll(_question(now));
  } else if (now.phase == Phase.question) {
    if (before.pausedRemainingMs == null && now.pausedRemainingMs != null) {
      lines.add('paused · ${_seconds(now.pausedRemainingMs!)} left');
    }
    if (before.pausedRemainingMs != null && now.pausedRemainingMs == null) {
      lines.add('resumed');
    }
    final was = before.deadline;
    final is_ = now.deadline;
    // The host ending a question pulls the deadline in (PROTOCOL.md §6).
    if (was != null && is_ != null && is_ < was - 500) {
      lines.add('closing · ${_seconds(is_ - now.serverTime)} left');
    }
  }

  if (now.phase == Phase.scoring && before.phase != Phase.scoring) {
    lines.addAll(_scoring(now, nameOf));
  } else if (now.phase == Phase.scoring || now.phase == Phase.leaderboard) {
    // Overrides (PROTOCOL.md §6.1): a verdict changed after scoring.
    final earlierRows = {
      for (final row in before.submissions ?? const <SubmissionView>[])
        row.playerId: row,
    };
    for (final row in now.submissions ?? const <SubmissionView>[]) {
      final was = earlierRows[row.playerId];
      if (was != null && was.correct != row.correct) {
        lines.add(
          '${nameOf(row.playerId)} marked ${row.correct == true ? 'right' : 'wrong'}'
          ' (${_signed(row.delta ?? 0)})',
        );
      }
    }
  }

  if (now.phase == Phase.leaderboard && before.phase != Phase.leaderboard) {
    lines.add('standings · ${_standings(now)}');
  }
  if (now.phase == Phase.finished && before.phase != Phase.finished) {
    lines.add('game over · ${_standings(now)}');
  }

  return lines;
}

String _quizzes(RoomState state) {
  final settings = state.settings;
  final details = settings == null
      ? ''
      : ' · ${_count(settings.questionCount, 'question')}'
            ' · ${_seconds(settings.timeLimitMs)} each'
            '${settings.difficultyMultiplier ? ' · difficulty scoring' : ''}'
            ' · ${settings.difficulties.join(',')}';
  return 'quizzes: ${state.packTitles.join(' · ')}$details';
}

List<String> _question(RoomState state) {
  final question = state.question;
  if (question == null) return const [];
  final points = question.points;
  final remaining = state.deadline == null
      ? (state.pausedRemainingMs == null
            ? ''
            : ' · paused, ${_seconds(state.pausedRemainingMs!)}')
      : ' · ${_seconds(state.deadline! - state.serverTime)}';
  return [
    'Q${(state.questionIndex ?? 0) + 1}/${state.questionCount}'
        ' · ${question.difficulty}'
        ' · ${_signed(points.right)} / ${_signed(points.wrong)}'
        ' / skip ${_signed(points.skipped)}$remaining',
    '  ${question.prompt}',
    if (question.imageUrl != null) '  photo: ${question.imageUrl}',
  ];
}

List<String> _scoring(RoomState state, String Function(String) nameOf) {
  final answers = state.acceptedAnswers ?? const <String>[];
  return [
    'answer: ${answers.join(' / ')}',
    for (final row in state.submissions ?? const <SubmissionView>[])
      '  ${nameOf(row.playerId)}: '
          '${row.answer == null ? '—' : '"${row.answer}"'}'
          ' ${row.correct == true ? '✓' : '✗'} ${_signed(row.delta ?? 0)}',
  ];
}

String _standings(RoomState state) {
  final players = [...state.players]
    ..sort((a, b) => b.score.compareTo(a.score));
  return [
    for (final (index, player) in players.indexed)
      '${index + 1}. ${player.name} ${player.score}',
  ].join(' · ');
}

String _count(int n, String thing) => n == 1 ? '1 $thing' : '$n ${thing}s';

String _seconds(int ms) => '${(ms / 1000).ceil()}s';

String _signed(int n) => n > 0 ? '+$n' : '$n';

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
