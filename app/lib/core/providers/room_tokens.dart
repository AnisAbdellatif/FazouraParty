import 'package:riverpod_annotation/riverpod_annotation.dart';

export '../storage/room_token_store.dart' show RoomToken;

import '../storage/room_token_store.dart';
import 'connection_providers.dart';

part 'room_tokens.g.dart';

/// The store behind [RoomTokens]. Overridden in tests.
@Riverpod(keepAlive: true)
RoomTokenStore roomTokenStore(Ref ref) => RoomTokenStore();

/// The rooms this device can return to, and the tokens that let it
/// (PROTOCOL.md §3.3).
///
/// Held on the device, not in memory: the case that matters is a browser
/// refresh, where the app restarts but the room does not. Without these a
/// player comes back as a stranger — and cannot even reuse their own name,
/// because the room still holds it (§4.1).
@Riverpod(keepAlive: true)
class RoomTokens extends _$RoomTokens {
  @override
  Future<List<RoomToken>> build() => _store.list();

  RoomTokenStore get _store => ref.read(roomTokenStoreProvider);

  /// The `player_token` for [roomCode], if this device has one.
  Future<String?> playerTokenFor(String roomCode) async =>
      (await _store.forRoom(roomCode))?.playerToken;

  /// The room this device last hosted and can still take back, if any. The
  /// host never types a code, so this is the only way back to it.
  Future<RoomToken?> lastHosted() async {
    for (final room in await _store.list()) {
      if (room.hostToken != null) return room;
    }
    return null;
  }

  Future<void> savePlayerToken(String roomCode, String token) =>
      _remember(() => _store.save(roomCode, playerToken: token));

  Future<void> saveHostToken(String roomCode, String token) =>
      _remember(() => _store.save(roomCode, hostToken: token));

  /// Forgets a room whose tokens will never work again — it closed, or the
  /// host refused them (§4.1).
  Future<void> drop(String roomCode) => _remember(() => _store.drop(roomCode));

  Future<void> _remember(Future<void> Function() write) async {
    await write();
    state = AsyncData(await _store.list());
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
@Riverpod(keepAlive: true)
Future<RoomToken?> resumableRoom(Ref ref) async {
  final rooms = await ref.watch(roomTokensProvider.future);
  final hosted = rooms.where((room) => room.hostToken != null).firstOrNull;
  if (hosted == null) return null;

  final alive = await ref
      .read(roomApiProvider)
      .hostRoomAlive(hosted.code, hosted.hostToken!);
  if (alive == false) {
    // Straight to the store rather than through [RoomTokens]: writing through
    // the provider this build watches would restart the build it is inside,
    // and the two take turns forever. Nothing else reads the list — every
    // other use of [RoomTokens] is a write — so there is no second copy to go
    // stale, and the next launch reads the store anyway.
    await ref.read(roomTokenStoreProvider).drop(hosted.code);
    return null;
  }
  return hosted;
}
