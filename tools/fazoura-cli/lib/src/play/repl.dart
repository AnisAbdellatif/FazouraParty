import 'dart:async';
import 'dart:convert';

import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';

import 'bots.dart';
import 'seat.dart';

/// Turns a selection argument (a quiz id or slug, or a path) into what
/// `host_select_quiz` takes. Supplied by the command, which knows whether this
/// is a cloud room or a LAN one.
typedef SelectionResolver = Future<QuizSelection> Function(String source);

/// Reports a player in this room (PROTOCOL.md §3.5), with this seat's token.
/// Null where there is nobody to report to — a LAN room.
typedef PlayerReporter =
    Future<void> Function(PlayerSummary player, String reason, String? note);

/// Commands typed at a running session, one per line.
///
/// A player's line is their answer unless it starts with `/`. A host's line is
/// a command; a playing host answers with `a <text>`. Every command maps onto
/// one intent (PROTOCOL.md §4.2) — the server decides whether it is allowed,
/// and a refusal is printed rather than ending the session.
class Repl {
  Repl(this.seat, {required this.resolve, required this.onQuit, this.report});

  final Seat seat;
  final SelectionResolver resolve;
  final PlayerReporter? report;
  final void Function() onQuit;

  GameConnection get _connection => seat.connection;
  bool get _host => seat.state?.you.role == Role.host;

  StreamSubscription<String>? _input;

  void attach(Stream<List<int>> input) {
    _input = input
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => unawaited(
            handle(line).catchError((Object error) {
              seat.output.error('$error');
            }),
          ),
        );
  }

  Future<void> detach() async => _input?.cancel();

  Future<void> handle(String raw) async {
    final line = raw.trim();
    if (line.isEmpty) return;

    if (!_host && !line.startsWith('/')) {
      await _submit(line);
      return;
    }

    final words = line.replaceFirst(RegExp('^/'), '').split(RegExp(r'\s+'));
    final command = words.first.toLowerCase();
    final args = words.skip(1).toList();
    final rest = args.join(' ');

    switch (command) {
      case 'help' || '?':
        seat.output.say(_host ? _hostHelp : _playerHelp);
      case 'state':
        seat.output.result(
          seat.state?.toJson(),
          () =>
              const JsonEncoder.withIndent('  ').convert(seat.state?.toJson()),
        );
      case 'players':
        for (final player in seat.state?.players ?? const <PlayerSummary>[]) {
          seat.output.say(
            '  ${player.name}${player.isHost ? ' (host)' : ''}'
            ' · ${player.score}'
            '${player.connected ? '' : ' · away'}'
            '${player.hasSubmitted ? ' · answered' : ''}',
          );
        }
      case 'a' || 'answer':
        await _submit(rest);
      case 'quit' || 'leave' || 'exit':
        onQuit();
      case 'start' || 'next' || 'n' || 'end':
        await seat.send(command, _connection.hostNext);
      case 'pause':
        await seat.send('pause', _connection.hostPause);
      case 'resume':
        await seat.send('resume', _connection.hostResume);
      case 'rematch':
        await seat.send('rematch', _connection.hostRematch);
      case 'close':
        await seat.send('close', _connection.hostClose);
      case 'listed' || 'public':
        final on =
            args.isEmpty || const {'on', 'yes', 'true'}.contains(args.first);
        await seat.send('listed', () => _connection.hostSetListed(on));
      case 'size':
        final size = int.tryParse(rest);
        if (size == null) return seat.output.error('size <players>');
        await seat.send('size', () => _connection.hostSetRoomSize(size));
      case 'code' || 'unlock':
        if (rest.isEmpty) return seat.output.error('code <room size code>');
        await seat.send('code', () => _connection.hostRedeemSizeCode(rest));
      case 'override' || 'right' || 'wrong':
        await _override(command, args);
      case 'remove' || 'kick':
        final player = seat.findPlayer(rest);
        if (player == null) return _unknownPlayer(rest);
        await seat.send(
          'remove',
          () => _connection.hostRemovePlayer(player.id),
        );
      case 'report':
        await _report(args);
      case 'transfer':
        final player = seat.findPlayer(rest);
        if (player == null) return _unknownPlayer(rest);
        await seat.send('transfer', () => _connection.hostTransfer(player.id));
      case 'select':
        if (args.isEmpty) {
          return seat.output.error('select <quiz id or path>...');
        }
        try {
          final selection = [for (final source in args) await resolve(source)];
          await seat.send(
            'select',
            () => _connection.hostSelectQuiz(selection),
          );
        } on Object catch (error) {
          seat.output.error('$error');
        }
      case 'set' || 'configure':
        await _configure(args);
      default:
        seat.output.error('unknown command "$command" — try help');
    }
  }

  Future<void> _submit(String answer) async {
    if (answer.isEmpty) return seat.output.error('a <answer>');
    if (await seat.send('submit', () => _connection.submit(answer))) {
      seat.note('submitted', {'answer': answer}, 'answered "$answer"');
    }
  }

  /// `override <player> right|wrong`, or the short forms `right <player>` and
  /// `wrong <player>`.
  Future<void> _override(String command, List<String> args) async {
    final (String name, String verdict) = command == 'override'
        ? (args.take(args.length - 1).join(' '), args.isEmpty ? '' : args.last)
        : (args.join(' '), command);
    if (verdict != 'right' && verdict != 'wrong') {
      return seat.output.error('override <player> right|wrong');
    }
    final player = seat.findPlayer(name);
    if (player == null) return _unknownPlayer(name);
    await seat.send(
      'override',
      () => _connection.hostOverride(player.id, verdict == 'right'),
    );
  }

  /// `report <player> <reason> [note…]`, the reason one of the report reasons.
  Future<void> _report(List<String> args) async {
    final report = this.report;
    if (report == null) {
      return seat.output.error('reporting is for rooms on the server');
    }
    final reasons = {for (final reason in quizReportReasons) reason.value};
    final at = args.indexWhere(reasons.contains);
    if (at < 1) {
      return seat.output.error('report <player> <${reasons.join('|')}> [note]');
    }
    final name = args.take(at).join(' ');
    final player = seat.findPlayer(name);
    if (player == null) return _unknownPlayer(name);
    final note = args.skip(at + 1).join(' ');
    try {
      await report(player, args[at], note.isEmpty ? null : note);
      seat.note('reported', {'player': player.id}, 'reported ${player.name}');
    } on GameError catch (error) {
      seat.output.error('report refused: ${error.message ?? error.code}');
    }
  }

  /// `set questions=10 time=20 scoring=on difficulties=easy,hard`
  Future<void> _configure(List<String> args) async {
    final settings = seat.state?.settings;
    if (settings == null) {
      return seat.output.error('select a quiz first — settings come with it');
    }
    int? questions;
    Duration? time;
    bool? scoring;
    List<String>? difficulties;
    for (final pair in args) {
      final [key, value] = pair.contains('=') ? pair.split('=') : [pair, ''];
      switch (key) {
        case 'questions' || 'q':
          questions = int.tryParse(value);
        case 'time' || 't':
          final seconds = int.tryParse(value.replaceAll('s', ''));
          time = seconds == null ? null : Duration(seconds: seconds);
        case 'scoring' || 'difficulty-scoring':
          scoring = const {'on', 'yes', 'true'}.contains(value);
        case 'difficulties' || 'd':
          difficulties = value.split(',').where((d) => d.isNotEmpty).toList();
        default:
          return seat.output.error('unknown setting "$key"');
      }
    }
    final configure = Configure(
      questionCount: questions,
      timeLimit: time,
      difficultyScoring: scoring,
      difficulties: difficulties,
    );
    await seat.send('configure', () => configure.apply(_connection, settings));
  }

  void _unknownPlayer(String name) =>
      seat.output.error('no player called "$name" — try players');

  static const _playerHelp = '''
Type an answer and press enter to lock it in. Commands start with /:
  /state          the latest snapshot, as JSON
  /players        who is in the room
  /report <player> <reason> [note]   in a public room
  /leave          leave the room''';

  static const _hostHelp = '''
  start | next | end      start the game, end a question, move on (host_next)
  pause | resume          freeze or restart the clock
  right <player>          mark a player's answer right (or: wrong <player>)
  select <quiz>...        choose quizzes: ids, slugs, or .json/.fazoura/folders
  set questions=10 time=20 scoring=on difficulties=easy,hard
  listed on|off           put the room on the public list, or take it off
  size <players>          how many players the room lets in
  code <room size code>   raise the room's limit with a code from an admin
  remove <player>         take a player out of the room
  report <player> <reason> [note]
  transfer <player>       hand the host role over
  rematch | close         play again, or end the room for everyone
  a <answer>              answer, when playing along
  state | players | help | leave''';
}
