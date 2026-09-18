// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lan_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Cloud unless something sets otherwise; reset when a session ends so a later
/// game never silently inherits a dead LAN address.

@ProviderFor(CurrentGameTarget)
final currentGameTargetProvider = CurrentGameTargetProvider._();

/// Cloud unless something sets otherwise; reset when a session ends so a later
/// game never silently inherits a dead LAN address.
final class CurrentGameTargetProvider
    extends $NotifierProvider<CurrentGameTarget, GameTarget> {
  /// Cloud unless something sets otherwise; reset when a session ends so a later
  /// game never silently inherits a dead LAN address.
  CurrentGameTargetProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentGameTargetProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentGameTargetHash();

  @$internal
  @override
  CurrentGameTarget create() => CurrentGameTarget();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameTarget value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameTarget>(value),
    );
  }
}

String _$currentGameTargetHash() => r'a892d9bea446b32966eaa507c1a31ec46b28e55e';

/// Cloud unless something sets otherwise; reset when a session ends so a later
/// game never silently inherits a dead LAN address.

abstract class _$CurrentGameTarget extends $Notifier<GameTarget> {
  GameTarget build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<GameTarget, GameTarget>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GameTarget, GameTarget>,
              GameTarget,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The LAN room this device is hosting, if any.
///
/// Held here rather than in a screen because the server must outlive any one
/// widget: the host navigating between screens must not take the party down
/// with it. Disposing the provider stops the server and ends the room out loud.

@ProviderFor(HostedLanRoom)
final hostedLanRoomProvider = HostedLanRoomProvider._();

/// The LAN room this device is hosting, if any.
///
/// Held here rather than in a screen because the server must outlive any one
/// widget: the host navigating between screens must not take the party down
/// with it. Disposing the provider stops the server and ends the room out loud.
final class HostedLanRoomProvider
    extends $NotifierProvider<HostedLanRoom, LanHost?> {
  /// The LAN room this device is hosting, if any.
  ///
  /// Held here rather than in a screen because the server must outlive any one
  /// widget: the host navigating between screens must not take the party down
  /// with it. Disposing the provider stops the server and ends the room out loud.
  HostedLanRoomProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hostedLanRoomProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hostedLanRoomHash();

  @$internal
  @override
  HostedLanRoom create() => HostedLanRoom();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LanHost? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LanHost?>(value),
    );
  }
}

String _$hostedLanRoomHash() => r'454db1739c0d29e315ed562a3e660d9802390a9c';

/// The LAN room this device is hosting, if any.
///
/// Held here rather than in a screen because the server must outlive any one
/// widget: the host navigating between screens must not take the party down
/// with it. Disposing the provider stops the server and ends the room out loud.

abstract class _$HostedLanRoom extends $Notifier<LanHost?> {
  LanHost? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<LanHost?, LanHost?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LanHost?, LanHost?>,
              LanHost?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
