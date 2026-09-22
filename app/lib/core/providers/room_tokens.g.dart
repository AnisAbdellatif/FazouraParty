// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_tokens.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The store behind [RoomTokens]. Overridden in tests.

@ProviderFor(roomTokenStore)
final roomTokenStoreProvider = RoomTokenStoreProvider._();

/// The store behind [RoomTokens]. Overridden in tests.

final class RoomTokenStoreProvider
    extends $FunctionalProvider<RoomTokenStore, RoomTokenStore, RoomTokenStore>
    with $Provider<RoomTokenStore> {
  /// The store behind [RoomTokens]. Overridden in tests.
  RoomTokenStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomTokenStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomTokenStoreHash();

  @$internal
  @override
  $ProviderElement<RoomTokenStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoomTokenStore create(Ref ref) {
    return roomTokenStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomTokenStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomTokenStore>(value),
    );
  }
}

String _$roomTokenStoreHash() => r'72c688756f5d6ad302323b6d5b0e54e766b6d1e3';

/// The rooms this device can return to, and the tokens that let it
/// (PROTOCOL.md §3.3).
///
/// Held on the device, not in memory: the case that matters is a browser
/// refresh, where the app restarts but the room does not. Without these a
/// player comes back as a stranger — and cannot even reuse their own name,
/// because the room still holds it (§4.1).

@ProviderFor(RoomTokens)
final roomTokensProvider = RoomTokensProvider._();

/// The rooms this device can return to, and the tokens that let it
/// (PROTOCOL.md §3.3).
///
/// Held on the device, not in memory: the case that matters is a browser
/// refresh, where the app restarts but the room does not. Without these a
/// player comes back as a stranger — and cannot even reuse their own name,
/// because the room still holds it (§4.1).
final class RoomTokensProvider
    extends $AsyncNotifierProvider<RoomTokens, List<RoomToken>> {
  /// The rooms this device can return to, and the tokens that let it
  /// (PROTOCOL.md §3.3).
  ///
  /// Held on the device, not in memory: the case that matters is a browser
  /// refresh, where the app restarts but the room does not. Without these a
  /// player comes back as a stranger — and cannot even reuse their own name,
  /// because the room still holds it (§4.1).
  RoomTokensProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomTokensProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomTokensHash();

  @$internal
  @override
  RoomTokens create() => RoomTokens();
}

String _$roomTokensHash() => r'85e39abe80821685aa1f62ba1606f3c3b9f9b74f';

/// The rooms this device can return to, and the tokens that let it
/// (PROTOCOL.md §3.3).
///
/// Held on the device, not in memory: the case that matters is a browser
/// refresh, where the app restarts but the room does not. Without these a
/// player comes back as a stranger — and cannot even reuse their own name,
/// because the room still holds it (§4.1).

abstract class _$RoomTokens extends $AsyncNotifier<List<RoomToken>> {
  FutureOr<List<RoomToken>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<RoomToken>>, List<RoomToken>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<RoomToken>>, List<RoomToken>>,
              AsyncValue<List<RoomToken>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The room the home screen may offer to take back, or null.
///
/// Holding a `host_token` is not the same as still having a room. The token is
/// good for 24 hours; the room it opened may have ended in thirty seconds, and
/// the role moves on the instant the host's connection drops with anybody else
/// connected. The host screen forgets the room on every way out it can see —
/// the room closing, a deliberate leave, a back gesture — but a tab that is
/// closed or an app that is swiped away runs none of that, and the offer then
/// outlives the party by a day.
///
/// So the host asks (PROTOCOL.md §3.1). A definite "no such room" is the only
/// answer that forgets it: a device that could not reach the server keeps the
/// offer, because a remembered room is worth more than a blip on the way to it.

@ProviderFor(resumableRoom)
final resumableRoomProvider = ResumableRoomProvider._();

/// The room the home screen may offer to take back, or null.
///
/// Holding a `host_token` is not the same as still having a room. The token is
/// good for 24 hours; the room it opened may have ended in thirty seconds, and
/// the role moves on the instant the host's connection drops with anybody else
/// connected. The host screen forgets the room on every way out it can see —
/// the room closing, a deliberate leave, a back gesture — but a tab that is
/// closed or an app that is swiped away runs none of that, and the offer then
/// outlives the party by a day.
///
/// So the host asks (PROTOCOL.md §3.1). A definite "no such room" is the only
/// answer that forgets it: a device that could not reach the server keeps the
/// offer, because a remembered room is worth more than a blip on the way to it.

final class ResumableRoomProvider
    extends
        $FunctionalProvider<
          AsyncValue<RoomToken?>,
          RoomToken?,
          FutureOr<RoomToken?>
        >
    with $FutureModifier<RoomToken?>, $FutureProvider<RoomToken?> {
  /// The room the home screen may offer to take back, or null.
  ///
  /// Holding a `host_token` is not the same as still having a room. The token is
  /// good for 24 hours; the room it opened may have ended in thirty seconds, and
  /// the role moves on the instant the host's connection drops with anybody else
  /// connected. The host screen forgets the room on every way out it can see —
  /// the room closing, a deliberate leave, a back gesture — but a tab that is
  /// closed or an app that is swiped away runs none of that, and the offer then
  /// outlives the party by a day.
  ///
  /// So the host asks (PROTOCOL.md §3.1). A definite "no such room" is the only
  /// answer that forgets it: a device that could not reach the server keeps the
  /// offer, because a remembered room is worth more than a blip on the way to it.
  ResumableRoomProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'resumableRoomProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$resumableRoomHash();

  @$internal
  @override
  $FutureProviderElement<RoomToken?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<RoomToken?> create(Ref ref) {
    return resumableRoom(ref);
  }
}

String _$resumableRoomHash() => r'c9fc8d57fd328246784db3e057f9765383ac982c';
