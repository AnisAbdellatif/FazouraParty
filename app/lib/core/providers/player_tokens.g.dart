// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_tokens.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// `player_token` per room code, kept in memory for this app session
/// (PROTOCOL.md §3.3).

@ProviderFor(PlayerTokens)
final playerTokensProvider = PlayerTokensProvider._();

/// `player_token` per room code, kept in memory for this app session
/// (PROTOCOL.md §3.3).
final class PlayerTokensProvider
    extends $NotifierProvider<PlayerTokens, Map<String, String>> {
  /// `player_token` per room code, kept in memory for this app session
  /// (PROTOCOL.md §3.3).
  PlayerTokensProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerTokensProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerTokensHash();

  @$internal
  @override
  PlayerTokens create() => PlayerTokens();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, String>>(value),
    );
  }
}

String _$playerTokensHash() => r'f3028b4a9ec80b70a0061531c7807caa0f807e06';

/// `player_token` per room code, kept in memory for this app session
/// (PROTOCOL.md §3.3).

abstract class _$PlayerTokens extends $Notifier<Map<String, String>> {
  Map<String, String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Map<String, String>, Map<String, String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, String>, Map<String, String>>,
              Map<String, String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
