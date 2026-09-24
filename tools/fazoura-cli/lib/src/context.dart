import 'dart:convert';
import 'dart:io';

import 'package:fazoura_party/core/api/quiz_api.dart';
import 'package:fazoura_party/core/api/room_api.dart';
import 'package:fazoura_party/core/quizzes/quiz_library.dart';
import 'package:fazoura_party/core/storage/local_quiz_store.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast_io.dart';

/// Where the CLI talks to when nothing says otherwise: the local stack
/// (`scripts/ci.sh up`) and `mix phx.server` both listen here.
const defaultServer = 'http://localhost:4000';

/// What every command is given: which server, how to print, and this
/// machine's publisher key.
class Context {
  Context({
    required String server,
    required this.output,
    String? ownerKey,
    Map<String, String>? environment,
    http.Client? client,
  }) : _client = client,
       server = server.endsWith('/')
           ? server.substring(0, server.length - 1)
           : server,
       _ownerKey = ownerKey,
       _environment = environment ?? Platform.environment;

  final String server;
  final Output output;
  final Map<String, String> _environment;
  final http.Client? _client;
  String? _ownerKey;

  late final RoomApi rooms = RoomApi(baseUrl: server, client: _client);
  late final QuizApi quizzes = QuizApi(
    baseUrl: server,
    ownerKey: ownerKey,
    client: _client,
  );

  /// This machine's quizzes — the CLI's "My quizzes" — kept exactly as the app
  /// keeps a device's: the app's own [QuizLibrary] over the app's own
  /// [LocalQuizStore], in a sembast file beside the publisher key. Publishing,
  /// tracking a submission and withdrawing all go through the app's code.
  ///
  /// One file per machine, shared by every instance. Sembast is not built for
  /// two processes writing at once, so library commands are best run one at a
  /// time; playing is not affected.
  late final QuizLibrary library = QuizLibrary(
    store: LocalQuizStore(
      databaseFactoryIo.openDatabase(
        '${configDirectory(_environment).path}/library.db',
      ),
    ),
    api: quizzes,
  );

  /// This machine's publisher key — the CLI's equivalent of the one the app
  /// keeps per device (QUIZ_FORMAT.md §4). It is what lets `quiz delete`
  /// and `quiz submissions` find what was published from here, so it is kept
  /// in a file rather than made up per run: every instance on the machine
  /// shares it, however many are running.
  ///
  /// `--owner-key` or `FAZOURA_OWNER_KEY` override the file, to act as a
  /// second publisher.
  Future<String> ownerKey() async {
    final known = _ownerKey ?? _environment['FAZOURA_OWNER_KEY'];
    if (known != null && known.isNotEmpty) return _ownerKey = known;

    final file = File('${configDirectory(_environment).path}/owner_key');
    if (file.existsSync()) {
      final stored = file.readAsStringSync().trim();
      if (stored.length >= 32) return _ownerKey = stored;
    }

    final key = generateOwnerKey();
    file.parent.createSync(recursive: true);
    // Written aside and renamed, so two instances starting together cannot
    // leave a half-written key for either of them to read.
    final temporary = File('${file.path}.$pid')..writeAsStringSync('$key\n');
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', temporary.path]);
    }
    temporary.renameSync(file.path);
    return _ownerKey = file.readAsStringSync().trim();
  }
}

/// `$FAZOURA_CONFIG_DIR`, else `$XDG_CONFIG_HOME/fazoura`, else
/// `~/.config/fazoura`.
Directory configDirectory(Map<String, String> environment) {
  final explicit = environment['FAZOURA_CONFIG_DIR'];
  if (explicit != null && explicit.isNotEmpty) return Directory(explicit);
  final xdg = environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return Directory('$xdg/fazoura');
  final home = environment['HOME'] ?? environment['USERPROFILE'] ?? '.';
  return Directory('$home/.config/fazoura');
}

/// Lines for people, or one JSON object per line for scripts (`--json`).
///
/// In JSON mode everything on stdout is NDJSON, so a script can read events
/// from several instances at once; anything meant only for a person goes to
/// stderr or nowhere.
class Output {
  Output({required this.json, IOSink? out, IOSink? err})
    : _out = out ?? stdout,
      _err = err ?? stderr;

  final bool json;
  final IOSink _out;
  final IOSink _err;

  /// Text for a person. Dropped in JSON mode.
  void say(String line) {
    if (!json) _out.writeln(line);
  }

  /// A command's result: [data] as JSON, or [human] for a person.
  void result(Object? data, String Function() human) {
    json ? _out.writeln(jsonEncode(data)) : _out.writeln(human());
  }

  /// Something that happened during a game, as `{"event": type, ...}`.
  void event(String type, Map<String, Object?> fields, String? human) {
    if (json) {
      _out.writeln(jsonEncode({'event': type, ...fields}));
    } else if (human != null) {
      _out.writeln(human);
    }
  }

  void error(String message) {
    if (json) {
      _out.writeln(jsonEncode({'event': 'error', 'message': message}));
    }
    _err.writeln('fazoura: $message');
  }
}
