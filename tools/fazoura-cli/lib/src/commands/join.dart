import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/connection/lan_game_connection.dart';
import 'package:fazoura_party/core/connection/phoenix_game_connection.dart';
import 'package:fazoura_party/core/lan/lan_host.dart';
import 'package:fazoura_party/core/models/models.dart';

import '../context.dart';
import '../play/bots.dart';
import '../play/repl.dart';
import '../play/seat.dart';
import 'play_options.dart';

class JoinCommand extends Command<int> {
  JoinCommand(this._context) {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help:
            'Display name. With --count, "{n}" is replaced by the number, '
            'or one is appended.',
        defaultsTo: 'Bot',
      )
      ..addOption(
        'count',
        abbr: 'c',
        help: 'Join as this many players, each on its own socket.',
        defaultsTo: '1',
      )
      ..addOption(
        'lan',
        help: 'The LAN host to join, as address or address:port.',
        valueHelp: 'address',
      )
      ..addFlag(
        'stay',
        negatable: false,
        help: 'Bots: stay for a rematch instead of leaving when a game ends.',
      )
      ..addFlag(
        'auto',
        negatable: false,
        help: 'Answer on its own even with no other answering option given.',
      );
    addAnswerOptions(argParser);
  }

  final Context _context;

  @override
  String get name => 'join';

  @override
  String get description =>
      'Join a room as a player — typed answers, or bots with --answer, '
      '--answers-from or --count.';

  @override
  String get invocation => 'fazoura join <CODE> [options]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length != 1) {
      throw const UsageError('join needs exactly one room code');
    }
    final code = args.rest.single.toUpperCase();
    final count = int.tryParse(args['count'] as String) ?? 0;
    if (count < 1) throw const UsageError('--count takes a number from 1');
    final lan = args['lan'] as String?;
    final baseUrl = lan == null ? _context.server : _lanUrl(lan);

    // One person at the keyboard can play one seat; more than that are bots.
    final bots = count > 1 || args.flag('auto') || wantsBot(args);
    final plan = bots ? await answerPlan(_context, args) : null;

    final seats = <Seat>[];
    final tokens = <Seat, String?>{};
    final playerBots = <PlayerBot>[];
    for (var n = 1; n <= count; n++) {
      final name = _nameFor(args['name'] as String, n, count);
      final GameConnection connection = lan == null
          ? PhoenixGameConnection(baseUrl: baseUrl)
          : LanGameConnection(baseUrl: baseUrl);
      final seat = Seat(
        label: name,
        connection: connection,
        output: _context.output,
        narrate: n == 1,
      )..watch();
      final JoinResult joined;
      try {
        joined = await connection.join(code, name);
        _context.output.event('joined', {
          'seat': name,
          'room_code': code,
          'player_id': joined.playerId,
        }, null);
      } on GameError catch (error) {
        _context.output.error(
          '$name could not join: ${error.message ?? error.code}',
        );
        await seat.leave();
        continue;
      }
      seats.add(seat);
      tokens[seat] = joined.playerToken;
      if (plan != null) playerBots.add(PlayerBot(seat, plan)..start());
    }
    if (seats.isEmpty) return 1;

    final finished = Completer<void>();
    void finish() {
      if (!finished.isCompleted) finished.complete();
    }

    Repl? repl;
    if (!bots) {
      final seat = seats.single;
      repl = Repl(
        seat,
        resolve: (source) =>
            resolveSelection(_context, source, lan: lan != null),
        onQuit: finish,
        report: lan != null
            ? null
            : (player, reason, note) async => _context.rooms.reportRoom(
                code,
                reason: reason,
                note: note,
                playerId: player.id,
                playerToken: tokens[seat],
                ownerKey: await _context.ownerKey(),
              ),
      )..attach(stdin);
      _context.output.say('[${seat.label}] type an answer, or /help');
    }

    // Everybody's room is the same room, so any seat seeing it close — or, for
    // bots, seeing the game end — is the end for all of them.
    for (final seat in seats) {
      unawaited(seat.closed.then((_) => finish()));
      if (bots && !args.flag('stay')) {
        unawaited(
          seat.updates
              .firstWhere((state) => state.phase == Phase.finished)
              .then((_) => finish(), onError: (_) {}),
        );
      }
    }
    final interrupted = ProcessSignal.sigint.watch().listen((_) => finish());
    await finished.future;

    await interrupted.cancel();
    for (final bot in playerBots) {
      bot.stop();
    }
    await repl?.detach();
    for (final seat in seats) {
      await seat.leave();
    }
    return 0;
  }

  static String _nameFor(String template, int n, int count) {
    if (template.contains('{n}')) return template.replaceAll('{n}', '$n');
    return count == 1 ? template : '$template $n';
  }

  static String _lanUrl(String address) {
    final bare = address.replaceFirst(RegExp('^https?://'), '');
    return bare.contains(':')
        ? 'http://$bare'
        : LanGameConnection.baseUrlFor(bare, defaultLanPort);
  }
}
