import 'dart:io';

import 'package:fazoura_cli/fazoura_cli.dart';

Future<void> main(List<String> arguments) async {
  final code = await absorbSocketNoise(() => runFazoura(arguments));
  await Future.wait([stdout.flush(), stderr.flush()]);
  // Sockets, timers and stdin would otherwise keep the process alive.
  exit(code);
}
