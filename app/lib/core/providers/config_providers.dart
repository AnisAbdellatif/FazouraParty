import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'served_origin.dart';

part 'config_providers.g.dart';

/// Local wall clock; overridable in tests.
typedef Clock = DateTime Function();

/// Server base URL.
///
/// On the web the app is normally served by the same Phoenix server that runs
/// the API, so its own origin is the right answer and nothing needs configuring
/// per deployment. Override with
/// `--dart-define=SERVER_URL=https://example.com` when the app is hosted
/// somewhere else (or for the Android build, which falls back to localhost).
@Riverpod(keepAlive: true)
String serverBaseUrl(Ref ref) {
  const configured = String.fromEnvironment('SERVER_URL');
  if (configured.isNotEmpty) return configured;
  return servedOrigin() ?? 'http://localhost:4000';
}

@Riverpod(keepAlive: true)
Clock clock(Ref ref) => DateTime.now;
