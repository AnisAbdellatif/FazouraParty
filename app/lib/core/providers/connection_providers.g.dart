// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(roomApi)
final roomApiProvider = RoomApiProvider._();

final class RoomApiProvider
    extends $FunctionalProvider<RoomApi, RoomApi, RoomApi>
    with $Provider<RoomApi> {
  RoomApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomApiHash();

  @$internal
  @override
  $ProviderElement<RoomApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoomApi create(Ref ref) {
    return roomApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomApi>(value),
    );
  }
}

String _$roomApiHash() => r'109d81f03bbf5e3bf01da99bc2c8c12121f85da8';

/// The connection for the current room session. This is the only place that
/// names a concrete transport; everything else depends on [GameConnection].
///
/// Which one it builds follows [currentGameTargetProvider], so a LAN game and a
/// cloud game are the same code path above this line (PROTOCOL.md §10).
///
/// Invalidate it to start a fresh session (disposal leaves the room).

@ProviderFor(gameConnection)
final gameConnectionProvider = GameConnectionProvider._();

/// The connection for the current room session. This is the only place that
/// names a concrete transport; everything else depends on [GameConnection].
///
/// Which one it builds follows [currentGameTargetProvider], so a LAN game and a
/// cloud game are the same code path above this line (PROTOCOL.md §10).
///
/// Invalidate it to start a fresh session (disposal leaves the room).

final class GameConnectionProvider
    extends $FunctionalProvider<GameConnection, GameConnection, GameConnection>
    with $Provider<GameConnection> {
  /// The connection for the current room session. This is the only place that
  /// names a concrete transport; everything else depends on [GameConnection].
  ///
  /// Which one it builds follows [currentGameTargetProvider], so a LAN game and a
  /// cloud game are the same code path above this line (PROTOCOL.md §10).
  ///
  /// Invalidate it to start a fresh session (disposal leaves the room).
  GameConnectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gameConnectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gameConnectionHash();

  @$internal
  @override
  $ProviderElement<GameConnection> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GameConnection create(Ref ref) {
    return gameConnection(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GameConnection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GameConnection>(value),
    );
  }
}

String _$gameConnectionHash() => r'74d5ace15f98dded9bf11412b173dafe3eab99f8';

@ProviderFor(roomState)
final roomStateProvider = RoomStateProvider._();

final class RoomStateProvider
    extends
        $FunctionalProvider<AsyncValue<RoomState>, RoomState, Stream<RoomState>>
    with $FutureModifier<RoomState>, $StreamProvider<RoomState> {
  RoomStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomStateHash();

  @$internal
  @override
  $StreamProviderElement<RoomState> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<RoomState> create(Ref ref) {
    return roomState(ref);
  }
}

String _$roomStateHash() => r'fd8b0a1263cfca8fea48284017f1b5165ba122f8';

@ProviderFor(connectionStatus)
final connectionStatusProvider = ConnectionStatusProvider._();

final class ConnectionStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionStatus>,
          ConnectionStatus,
          Stream<ConnectionStatus>
        >
    with $FutureModifier<ConnectionStatus>, $StreamProvider<ConnectionStatus> {
  ConnectionStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionStatusHash();

  @$internal
  @override
  $StreamProviderElement<ConnectionStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConnectionStatus> create(Ref ref) {
    return connectionStatus(ref);
  }
}

String _$connectionStatusHash() => r'42509d261d747d49d03743d3abeef5885ed1ca85';

@ProviderFor(roomClosed)
final roomClosedProvider = RoomClosedProvider._();

final class RoomClosedProvider
    extends
        $FunctionalProvider<
          AsyncValue<RoomClosedReason>,
          RoomClosedReason,
          FutureOr<RoomClosedReason>
        >
    with $FutureModifier<RoomClosedReason>, $FutureProvider<RoomClosedReason> {
  RoomClosedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomClosedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomClosedHash();

  @$internal
  @override
  $FutureProviderElement<RoomClosedReason> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RoomClosedReason> create(Ref ref) {
    return roomClosed(ref);
  }
}

String _$roomClosedHash() => r'7678b8b84deb6a1f58b8ba8b25021d8df12ec6d8';

/// `server_time - local_now`, recomputed whenever a new snapshot arrives.

@ProviderFor(serverClockOffset)
final serverClockOffsetProvider = ServerClockOffsetProvider._();

/// `server_time - local_now`, recomputed whenever a new snapshot arrives.

final class ServerClockOffsetProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// `server_time - local_now`, recomputed whenever a new snapshot arrives.
  ServerClockOffsetProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverClockOffsetProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverClockOffsetHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return serverClockOffset(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$serverClockOffsetHash() => r'8da3bd1f1efaeb1c9bb505c9af02cb65d10d5445';
