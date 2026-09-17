// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Server base URL.
///
/// On the web the app is normally served by the same Phoenix server that runs
/// the API, so its own origin is the right answer and nothing needs configuring
/// per deployment. Override with
/// `--dart-define=SERVER_URL=https://example.com` when the app is hosted
/// somewhere else (or for the Android build, which falls back to localhost).

@ProviderFor(serverBaseUrl)
final serverBaseUrlProvider = ServerBaseUrlProvider._();

/// Server base URL.
///
/// On the web the app is normally served by the same Phoenix server that runs
/// the API, so its own origin is the right answer and nothing needs configuring
/// per deployment. Override with
/// `--dart-define=SERVER_URL=https://example.com` when the app is hosted
/// somewhere else (or for the Android build, which falls back to localhost).

final class ServerBaseUrlProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// Server base URL.
  ///
  /// On the web the app is normally served by the same Phoenix server that runs
  /// the API, so its own origin is the right answer and nothing needs configuring
  /// per deployment. Override with
  /// `--dart-define=SERVER_URL=https://example.com` when the app is hosted
  /// somewhere else (or for the Android build, which falls back to localhost).
  ServerBaseUrlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverBaseUrlProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverBaseUrlHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return serverBaseUrl(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$serverBaseUrlHash() => r'2340d2fe0afca439c30433ad62d788c5c655646f';

@ProviderFor(clock)
final clockProvider = ClockProvider._();

final class ClockProvider extends $FunctionalProvider<Clock, Clock, Clock>
    with $Provider<Clock> {
  ClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clockHash();

  @$internal
  @override
  $ProviderElement<Clock> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Clock create(Ref ref) {
    return clock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Clock value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Clock>(value),
    );
  }
}

String _$clockHash() => r'ce4c8073e4878f6859ed9a59fae2c1819b4179af';
