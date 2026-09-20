import 'package:riverpod_annotation/riverpod_annotation.dart';

export '../storage/room_token_store.dart' show RoomToken;

import '../storage/room_token_store.dart';

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
