import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/connection/lan_game_connection.dart';
import 'package:fazoura_party/core/connection/phoenix_game_connection.dart';
import 'package:fazoura_party/core/lan/lan_host.dart';

import '../context.dart';
import '../play/bots.dart';
import '../play/repl.dart';
import '../play/seat.dart';
import 'play_options.dart';

class HostCommand extends Command<int> {
  HostCommand(this._context) {
    argParser
      ..addOption(
        'name',
        help:
            'Play along under this name. Without it the host only runs the room.',
      )
      ..addMultiOption(
        'quiz',
        abbr: 'q',
        help:
            'A quiz to play: an id or slug, or a .json/.fazoura/folder sent '
            'inline. Repeatable, up to 10.',
        valueHelp: 'quiz',
      )
      ..addFlag(
        'listed',
        negatable: false,
        help: 'Show the room in public rooms. Library quizzes only.',
      )
      ..addFlag(
        'lan',
        negatable: false,
        help: 'Host on this machine for the local network, not on the server.',
      )
      ..addOption(
        'port',
        help: 'Port for --lan.',
        defaultsTo: '$defaultLanPort',
      )
      ..addOption(
        'size-code',
        help:
            'A room size code from an admin, redeemed as soon as the room '
            'opens, to let in more than the usual number of players.',
      )
      ..addOption(
        'room-size',
        help: 'How many players the room lets in (after --size-code).',
      )
      ..addOption('questions', help: 'Questions per game.')
      ..addOption('time', help: 'Seconds per question (10-120).')
      ..addFlag(
        'difficulty-scoring',
        defaultsTo: null,
        help:
            'Score by difficulty (easy +10/-15, medium +25/-10, hard +50/-5).',
      )
      ..addOption(
        'difficulties',
        help: 'Which difficulties to draw from, e.g. easy,medium.',
      )
      ..addFlag(
        'auto',
        negatable: false,
        help:
            'Run the room unattended: start when enough players are in, move '
            'on after each question, close when done.',
      )
      ..addOption(
        'start-when',
        help: '--auto: start once this many players besides the host are in.',
        defaultsTo: '1',
      )
      ..addOption(
        'pace',
        help: '--auto: seconds answers and standings stay up.',
        defaultsTo: '3',
      )
      ..addOption(
        'games',
        help: '--auto: games to play, rematching between them.',
        defaultsTo: '1',
      )
      ..addFlag(
        'keep-open',
        negatable: false,
        help: '--auto: leave the room open after the last game.',
      );
    addAnswerOptions(argParser);
  }

  final Context _context;

  @override
  String get name => 'host';

  @override
  String get description =>
      'Open a room and host it — typed commands, or --auto to run it alone.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final lan = args.flag('lan');
    final listed = args.flag('listed');
    if (lan && listed) throw const UsageError('a LAN room cannot be listed');
    final sizeCode = args['size-code'] as String?;
    if (lan && sizeCode != null) {
      throw const UsageError('a LAN room has no room size codes');
    }
    final roomSize = _int(args, 'room-size');
    final displayName = args['name'] as String?;

    final selection = [
      for (final source in args['quiz'] as List<String>)
        await resolveSelection(_context, source, lan: lan),
    ];
    final configure = Configure(
      questionCount: _int(args, 'questions'),
      timeLimit: _int(args, 'time') == null
          ? null
          : Duration(seconds: _int(args, 'time')!),
      difficultyScoring: args['difficulty-scoring'] as bool?,
      difficulties: (args['difficulties'] as String?)
          ?.split(',')
          .map((d) => d.trim())
          .where((d) => d.isNotEmpty)
          .toList(),
    );

    // The room: created on the server, or served from this process.
    LanHost? lanHost;
    final String code;
    final String hostToken;
    final GameConnection connection;
    if (lan) {
      lanHost = await LanHost.start(port: _int(args, 'port') ?? defaultLanPort);
      code = lanHost.roomCode;
      hostToken = lanHost.hostToken;
      // The host joins its own server over loopback, like the app does.
      connection = LanGameConnection(
        baseUrl: 'http://127.0.0.1:${lanHost.port}',
      );
    } else {
      final created = await _context.rooms.createRoom(listed: listed);
      code = created.roomCode;
      hostToken = created.hostToken;
      connection = PhoenixGameConnection(baseUrl: _context.server);
    }

    final seat = Seat(
      label: displayName ?? 'host',
      connection: connection,
      output: _context.output,
    )..watch();
    await connection.joinAsHost(code, hostToken, displayName: displayName);
    _context.output.event(
      'room',
      {
        'room_code': code,
        'host_token': hostToken,
        'listed': listed,
        if (lanHost != null) 'join_url': lanHost.joinUrl,
        if (lanHost != null) 'port': lanHost.port,
      },
      [
        'room $code${listed ? ' · public' : ''}',
        if (lanHost != null)
          'LAN: fazoura join $code --lan ${lanHost.joinUrl ?? '127.0.0.1:${lanHost.port}'}',
      ].join('\n'),
    );

    // Before the lobby fills, so `--start-when` can count past the usual size.
    final sized =
        (sizeCode == null ||
            await seat.send(
              'code',
              () => connection.hostRedeemSizeCode(sizeCode),
            )) &&
        (roomSize == null ||
            await seat.send(
              'size',
              () => connection.hostSetRoomSize(roomSize),
            ));
    if (!sized) {
      await seat.leave();
      await lanHost?.stop();
      return 1;
    }

    await prepareLobby(seat, selection, configure);

    final finished = Completer<void>();
    void finish() {
      if (!finished.isCompleted) finished.complete();
    }

    HostBot? hostBot;
    PlayerBot? playerBot;
    Repl? repl;
    if (args.flag('auto')) {
      hostBot = HostBot(
        seat,
        HostPlan(
          selection: selection,
          configure: configure,
          startWhen: _int(args, 'start-when') ?? 1,
          pace: Duration(
            milliseconds:
                ((double.tryParse(args['pace'] as String) ?? 3) * 1000).round(),
          ),
          games: _int(args, 'games') ?? 1,
          closeWhenDone: !args.flag('keep-open'),
        ),
      )..start();
      unawaited(hostBot.done.then((_) => finish()));
    } else {
      repl = Repl(
        seat,
        resolve: (source) => resolveSelection(_context, source, lan: lan),
        onQuit: finish,
        report: lan
            ? null
            : (player, reason, note) async => _context.rooms.reportRoom(
                code,
                reason: reason,
                note: note,
                playerId: player.id,
                hostToken: hostToken,
                ownerKey: await _context.ownerKey(),
              ),
      )..attach(stdin);
      _context.output.say('[${seat.label}] type help for commands');
    }
    if (displayName != null && (wantsBot(args) || args.flag('auto'))) {
      playerBot = PlayerBot(seat, await answerPlan(_context, args))..start();
    }

    final interrupted = ProcessSignal.sigint.watch().listen((_) => finish());
    unawaited(seat.closed.then((_) => finish()));
    await finished.future;

    await interrupted.cancel();
    hostBot?.stop();
    playerBot?.stop();
    await repl?.detach();
    await seat.leave();
    await lanHost?.stop();
    return 0;
  }

  int? _int(dynamic args, String name) {
    final value = args[name] as String?;
    if (value == null) return null;
    final parsed = int.tryParse(value);
    if (parsed == null) throw UsageError('--$name takes a whole number');
    return parsed;
  }
}
