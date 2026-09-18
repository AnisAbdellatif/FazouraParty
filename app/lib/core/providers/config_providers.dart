import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'served_origin.dart';

part 'config_providers.g.dart';

const _serverUrlOverrideKey = 'fazoura.debug_server_url';

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
class ServerBaseUrl extends _$ServerBaseUrl {
  @override
  String build() {
    final fallback = _defaultServerUrl();
    if (kDebugMode) unawaited(_loadOverride(fallback));
    return fallback;
  }

  Future<void> _loadOverride(String fallback) async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString(_serverUrlOverrideKey);
    if (override != null && override.isNotEmpty && state == fallback) {
      state = override;
    }
  }

  Future<void> setDebugOverride(String? value) async {
    if (!kDebugMode) return;
    final prefs = await SharedPreferences.getInstance();
    final trimmed = value?.trim() ?? '';

    if (trimmed.isEmpty) {
      await prefs.remove(_serverUrlOverrideKey);
      state = _defaultServerUrl();
    } else {
      await prefs.setString(_serverUrlOverrideKey, trimmed);
      state = trimmed;
    }
  }
}

String _defaultServerUrl() {
  const configured = String.fromEnvironment('SERVER_URL');
  if (configured.isNotEmpty) return configured;
  return servedOrigin() ?? 'http://localhost:4000';
}

@Riverpod(keepAlive: true)
Clock clock(Ref ref) => DateTime.now;
