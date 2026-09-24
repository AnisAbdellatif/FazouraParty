import 'dart:convert';
import 'dart:io';

import 'package:fazoura_cli/fazoura_cli.dart';
import 'package:fazoura_cli/src/context.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('fazoura_cli_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a command that does not exist is a usage error', () async {
    expect(await runFazoura(['nope']), 64);
    expect(await runFazoura(['join']), 64, reason: 'no room code');
  });

  test('quiz pack writes a package a quiz can be read back from', () async {
    final folder = Directory('${tmp.path}/film-night')..createSync();
    File('${folder.path}/film-night.json').writeAsStringSync(
      jsonEncode({
        'format_version': '1.0',
        'title': 'Film Night',
        'tags': ['movies'],
        'questions': [
          {
            'type': 'text',
            'prompt': 'Which film?',
            'accepted_answers': ['Alien'],
          },
        ],
      }),
    );
    final out = '${tmp.path}/out.fazoura';

    expect(await runFazoura(['quiz', 'pack', folder.path, '-o', out]), 0);
    expect(await runFazoura(['quiz', 'inspect', out]), 0);
    expect(await runFazoura(['quiz', 'pack', '${tmp.path}/missing']), 1);
  });

  test('one publisher key per machine, shared by every instance', () async {
    final environment = {'FAZOURA_CONFIG_DIR': tmp.path};
    Context context() => Context(
      server: 'http://localhost:4000',
      output: Output(json: true),
      environment: environment,
    );

    final first = await context().ownerKey();
    expect(first, hasLength(43));
    expect(await context().ownerKey(), first);
    expect(File('${tmp.path}/owner_key').readAsStringSync().trim(), first);

    final other = Context(
      server: 'http://localhost:4000',
      output: Output(json: true),
      environment: {...environment, 'FAZOURA_OWNER_KEY': 'a' * 43},
    );
    expect(await other.ownerKey(), 'a' * 43, reason: 'acting as someone else');
  });
}
