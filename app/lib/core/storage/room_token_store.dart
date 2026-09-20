/// The tokens that let this device return to a room it is already in
/// (PROTOCOL.md §3.3).
///
/// Kept on the device rather than in memory because the case that matters is a
/// browser refresh: the app restarts, and without these the player cannot
/// rejoin as themselves — the room still holds their name and their score, so
/// they cannot even rejoin under the same name (§4.1).
///
/// Small and per-room, so `shared_preferences` is the right home — the same
/// place the publisher key lives. It is `localStorage` on Web, which is
/// exactly the storage a refresh must survive.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What this device holds for one room.
typedef RoomToken = ({String code, String? playerToken, String? hostToken});

/// How long a remembered room is worth offering. Matches the server's token
/// lifetime (`@token_max_age_s`), so the app never invites someone back into a
/// room whose tokens it knows the host will refuse.
const roomTokenLifetime = Duration(hours: 24);

class RoomTokenStore {
  RoomTokenStore({
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  static const _key = 'fazoura.room_tokens';

  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;

  /// Every room still worth returning to, newest first. Reading also forgets
  /// the expired ones, so the list never grows without bound.
  Future<List<RoomToken>> list() async {
    final prefs = await _preferences();
    final rooms = _decode(prefs.getString(_key));
    final live = _live(rooms);
    if (live.length != rooms.length) await _write(prefs, live);
    return [
      for (final room in live)
        (
          code: room.code,
          playerToken: room.playerToken,
          hostToken: room.hostToken,
        ),
    ];
  }

  Future<RoomToken?> forRoom(String code) async {
    final rooms = await list();
    for (final room in rooms) {
      if (room.code == code) return room;
    }
    return null;
  }

  /// Remembers a token for [code], keeping whichever of the two this call does
  /// not carry. A host that also plays holds both.
  Future<void> save(
    String code, {
    String? playerToken,
    String? hostToken,
  }) async {
    final prefs = await _preferences();
    final rooms = _live(_decode(prefs.getString(_key)));
    final existing = rooms.where((room) => room.code == code).firstOrNull;

    await _write(prefs, [
      (
        code: code,
        playerToken: playerToken ?? existing?.playerToken,
        hostToken: hostToken ?? existing?.hostToken,
        savedAt: _now(),
      ),
      ...rooms.where((room) => room.code != code),
    ]);
  }

  /// Forgets [code] — the room ended, or the host refused the tokens, and
  /// either way they will never work again (§4.1).
  Future<void> drop(String code) async {
    final prefs = await _preferences();
    final rooms = _live(_decode(prefs.getString(_key)));
    if (!rooms.any((room) => room.code == code)) return;
    await _write(prefs, rooms.where((room) => room.code != code).toList());
  }

  List<_StoredRoom> _live(List<_StoredRoom> rooms) {
    final cutoff = _now().subtract(roomTokenLifetime);
    return [
      for (final room in rooms)
        if (room.savedAt.isAfter(cutoff)) room,
    ];
  }

  Future<void> _write(SharedPreferences prefs, List<_StoredRoom> rooms) async {
    if (rooms.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
      _key,
      jsonEncode([
        for (final room in rooms)
          {
            'code': room.code,
            'player_token': room.playerToken,
            'host_token': room.hostToken,
            'saved_at': room.savedAt.toUtc().toIso8601String(),
          },
      ]),
    );
  }

  /// Anything unreadable is treated as nothing remembered: these are a
  /// convenience, and losing them costs a re-join, whereas throwing here would
  /// break every screen that asks.
  static List<_StoredRoom> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      return [
        for (final entry in jsonDecode(raw) as List)
          if (entry case {
            'code': final String code,
            'saved_at': final String at,
            'player_token': final String? player,
            'host_token': final String? host,
          })
            (
              code: code,
              playerToken: player,
              hostToken: host,
              savedAt: DateTime.parse(at),
            ),
      ];
    } on Object {
      return const [];
    }
  }
}

typedef _StoredRoom = ({
  String code,
  String? playerToken,
  String? hostToken,
  DateTime savedAt,
});
