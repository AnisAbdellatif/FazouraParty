import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:http/http.dart' as http;

import 'commands/host.dart';
import 'commands/join.dart';
import 'commands/play_options.dart';
import 'commands/quiz.dart';
import 'commands/rooms.dart';
import 'context.dart';
import 'pack.dart';

/// Runs one `fazoura` invocation and returns its exit code: 0 done, 1 the
/// server or the input said no, 64 the command itself was wrong.
Future<int> runFazoura(
  List<String> arguments, {
  Map<String, String>? environment,
  http.Client? client,
}) async {
  final env = environment ?? Platform.environment;
  final globals = ArgParser(allowTrailingOptions: true)
    ..addOption(
      'server',
      abbr: 's',
      help:
          'The server to talk to. Default: \$FAZOURA_SERVER, else $defaultServer.',
    )
    ..addFlag(
      'json',
      negatable: false,
      help: 'Print one JSON object per line instead of text, for scripts.',
    )
    ..addOption(
      'owner-key',
      help:
          'Publisher key to act as. Default: \$FAZOURA_OWNER_KEY, else one '
          'kept in ~/.config/fazoura/owner_key for this machine.',
    );

  // The globals are needed to build the commands, so they are read first on
  // their own; the runner then parses everything again.
  // A mistake here is reported properly by the runner's own parse below.
  ArgResults? early;
  try {
    early =
        (ArgParser()
              ..addFlag('help', abbr: 'h')
              ..addOption('server', abbr: 's')
              ..addFlag('json')
              ..addOption('owner-key'))
            .parse(_leadingGlobals(arguments));
  } on FormatException {
    early = null;
  }
  final output = Output(json: early?.flag('json') ?? false);
  final context = Context(
    server:
        (early?['server'] as String?) ?? env['FAZOURA_SERVER'] ?? defaultServer,
    output: output,
    ownerKey: early?['owner-key'] as String?,
    environment: env,
    client: client,
  );

  final runner =
      CommandRunner<int>(
          'fazoura',
          'Play and manage Fazoura Party from the terminal.\n\n'
              'Every instance is one or more devices: run several to fill a room.',
        )
        ..addCommand(RoomsCommand(context))
        ..addCommand(HostCommand(context))
        ..addCommand(JoinCommand(context))
        ..addCommand(QuizCommand(context));
  for (final option in globals.options.values) {
    if (option.name == 'help') continue;
    if (option.isFlag) {
      runner.argParser.addFlag(
        option.name,
        abbr: option.abbr,
        help: option.help,
        negatable: option.negatable ?? true,
      );
    } else {
      runner.argParser.addOption(
        option.name,
        abbr: option.abbr,
        help: option.help,
      );
    }
  }

  try {
    return await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln('${error.message}\n\n${error.usage}');
    return 64;
  } on UsageError catch (error) {
    output.error(error.message);
    return 64;
  } on PackError catch (error) {
    output.error(error.message);
    return 1;
  } on GameError catch (error) {
    output.error(error.message ?? error.code);
    return 1;
  } on SocketException catch (error) {
    output.error('could not reach ${context.server}: ${error.message}');
    return 1;
  }
}

/// The options before the command name: the only ones that can be global.
List<String> _leadingGlobals(List<String> arguments) {
  final leading = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (!argument.startsWith('-')) break;
    leading.add(argument);
    final takesValue = const {
      '--server',
      '-s',
      '--owner-key',
    }.contains(argument);
    if (takesValue && i + 1 < arguments.length) leading.add(arguments[++i]);
  }
  return leading;
}
