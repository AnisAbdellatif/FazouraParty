import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'player_tokens.g.dart';

/// `player_token` per room code, kept in memory for this app session
/// (PROTOCOL.md §3.3).
@Riverpod(keepAlive: true)
class PlayerTokens extends _$PlayerTokens {
  @override
  Map<String, String> build() => const {};

  String? tokenFor(String roomCode) => state[roomCode];

  void save(String roomCode, String token) {
    state = {...state, roomCode: token};
  }

  void drop(String roomCode) {
    if (!state.containsKey(roomCode)) return;
    state = Map.of(state)..remove(roomCode);
  }
}
