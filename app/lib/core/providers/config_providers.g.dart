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

@ProviderFor(ServerBaseUrl)
final serverBaseUrlProvider = ServerBaseUrlProvider._();

/// Server base URL.
///
/// On the web the app is normally served by the same Phoenix server that runs
/// the API, so its own origin is the right answer and nothing needs configuring
/// per deployment. Override with
/// `--dart-define=SERVER_URL=https://example.com` when the app is hosted
/// somewhere else (or for the Android build, which falls back to localhost).
final class ServerBaseUrlProvider
    extends $NotifierProvider<ServerBaseUrl, String> {
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
  ServerBaseUrl create() => ServerBaseUrl();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$serverBaseUrlHash() => r'2d6fe955c44b47dbb81b86fdfd4f410cce5b592f';

/// Server base URL.
///
/// On the web the app is normally served by the same Phoenix server that runs
/// the API, so its own origin is the right answer and nothing needs configuring
/// per deployment. Override with
/// `--dart-define=SERVER_URL=https://example.com` when the app is hosted
/// somewhere else (or for the Android build, which falls back to localhost).

abstract class _$ServerBaseUrl extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

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
