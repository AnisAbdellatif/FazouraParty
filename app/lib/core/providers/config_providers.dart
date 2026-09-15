import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'config_providers.g.dart';

/// Local wall clock; overridable in tests.
typedef Clock = DateTime Function();

/// Server base URL. Override at build time with
/// `--dart-define=SERVER_URL=https://example.com`.
@Riverpod(keepAlive: true)
String serverBaseUrl(Ref ref) => const String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://localhost:4000',
);

@Riverpod(keepAlive: true)
Clock clock(Ref ref) => DateTime.now;
