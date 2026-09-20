/// Room tokens kept on the device (PROTOCOL.md §3.3).
///
/// The case worth protecting is a browser refresh: the app restarts, the room
/// does not, and without these the player cannot come back as themselves —
/// the room still holds their name, so they cannot even reuse it (§4.1).
@TestOn('vm')
library;

import 'package:fazoura_party/core/storage/room_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var clock = DateTime.utc(2026, 9, 20, 20);

  RoomTokenStore store() => RoomTokenStore(now: () => clock);

  setUp(() {
    clock = DateTime.utc(2026, 9, 20, 20);
    SharedPreferences.setMockInitialValues({});
  });

  test('a token saved by one instance is read by the next', () async {
    await store().save('K7QX2M', playerToken: 'player-1');

    // A new instance is what the app gets after a refresh: nothing is carried
    // over in memory.
    expect((await store().forRoom('K7QX2M'))?.playerToken, 'player-1');
  });

  test('a room can hold both tokens, saved one at a time', () async {
    await store().save('K7QX2M', hostToken: 'host-1');
    await store().save('K7QX2M', playerToken: 'player-1');

    final room = await store().forRoom('K7QX2M');
    expect(room?.hostToken, 'host-1', reason: 'a playing host holds both');
    expect(room?.playerToken, 'player-1');
  });

  test('saving again replaces only what it carries', () async {
    await store().save('K7QX2M', playerToken: 'player-1', hostToken: 'host-1');
    await store().save('K7QX2M', playerToken: 'player-2');

    final room = await store().forRoom('K7QX2M');
    expect((room?.playerToken, room?.hostToken), ('player-2', 'host-1'));
  });

  test('rooms come back newest first', () async {
    await store().save('AAAAAA', playerToken: 'a');
    await store().save('BBBBBB', playerToken: 'b');
    await store().save('CCCCCC', playerToken: 'c');

    expect((await store().list()).map((room) => room.code), [
      'CCCCCC',
      'BBBBBB',
      'AAAAAA',
    ]);
  });

  test('dropping forgets one room and leaves the rest', () async {
    await store().save('AAAAAA', playerToken: 'a');
    await store().save('BBBBBB', playerToken: 'b');

    await store().drop('AAAAAA');

    expect((await store().list()).map((room) => room.code), ['BBBBBB']);
    expect(await store().forRoom('AAAAAA'), isNull);
  });

  test('a room older than the tokens are valid for is forgotten', () async {
    await store().save('K7QX2M', playerToken: 'player-1');

    clock = clock.add(roomTokenLifetime - const Duration(minutes: 1));
    expect(await store().forRoom('K7QX2M'), isNotNull);

    // Past the server's own token lifetime there is no point offering it: the
    // host would refuse it.
    clock = clock.add(const Duration(minutes: 2));
    expect(await store().forRoom('K7QX2M'), isNull);
  });

  test('expired rooms are cleared out on the next read', () async {
    await store().save('K7QX2M', playerToken: 'player-1');
    clock = clock.add(roomTokenLifetime * 2);

    await store().list();

    // Read through a store with a clock back at the original time: the entry
    // is gone from storage, not merely filtered out of that one answer.
    expect(
      await RoomTokenStore(now: () => DateTime.utc(2026, 9, 20, 20))
          .forRoom('K7QX2M'),
      isNull,
    );
  });

  test('unreadable storage reads as nothing remembered', () async {
    SharedPreferences.setMockInitialValues({
      'fazoura.room_tokens': 'not json at all',
    });

    // Losing these costs a re-join; throwing would break every screen that
    // asks whether there is a room to go back to.
    expect(await store().list(), isEmpty);
    await store().save('K7QX2M', playerToken: 'player-1');
    expect((await store().forRoom('K7QX2M'))?.playerToken, 'player-1');
  });

  test('nothing is kept once the last room is dropped', () async {
    final prefs = await SharedPreferences.getInstance();
    await store().save('K7QX2M', playerToken: 'player-1');
    expect(prefs.getString('fazoura.room_tokens'), isNotNull);

    await store().drop('K7QX2M');
    await prefs.reload();
    expect(prefs.getString('fazoura.room_tokens'), isNull);
  });
}
