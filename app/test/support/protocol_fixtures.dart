import 'dart:convert';
import 'dart:io';

/// Loads the shared contract fixtures from `<repo>/protocol/fixtures`, the same
/// files the server replays in `Fazoura.ProtocolFixtures` (PROTOCOL.md §11).
///
/// These are read from disk rather than copied into Dart on purpose: a copy
/// drifts silently, which is exactly what the shared fixtures exist to prevent
/// (AGENTS.md §8). `flutter test` runs with the package root as its working
/// directory, so `../protocol` is the repo's protocol folder.
class ProtocolFixtures {
  static final Directory dir = Directory('../protocol/fixtures');

  static Map<String, dynamic> load(String relative) {
    final file = File('${dir.path}/$relative');
    if (!file.existsSync()) {
      throw StateError('missing protocol fixture: ${file.path}');
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Every `scenarios/*.json` script, sorted by path for a stable test order.
  static List<({String name, Map<String, dynamic> scenario})> scenarios() {
    final scenarioDir = Directory('${dir.path}/scenarios');
    if (!scenarioDir.existsSync()) {
      throw StateError('missing protocol scenarios: ${scenarioDir.path}');
    }
    final files =
        scenarioDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      throw StateError('no protocol scenarios in ${scenarioDir.path}');
    }
    return [
      for (final file in files)
        (
          name: file.uri.pathSegments.last,
          scenario: jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
        ),
    ];
  }
}
