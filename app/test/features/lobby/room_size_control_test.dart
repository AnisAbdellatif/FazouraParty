import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/features/lobby/room_size_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RoomState _state({int size = 4, int limit = 32, int players = 2}) =>
    RoomState.fromJson({
      'protocol_version': 9,
      'room_code': 'K7QX2M',
      'mode': 'cloud',
      'phase': 'lobby',
      'server_time': 0,
      'question_count': 0,
      'room_size': size,
      'room_size_limit': limit,
      'players': [
        for (var i = 0; i < players; i++)
          {
            'id': 'p$i',
            'name': 'Player $i',
            'score': 0,
            'connected': true,
            'has_submitted': false,
          },
      ],
      'you': {'role': 'host'},
    });

void main() {
  Future<void> pump(
    WidgetTester tester,
    RoomState state, {
    List<int>? sizes,
    Future<void> Function(String code)? redeem,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RoomSizeControl(
          state: state,
          onSetSize: (size) async => sizes?.add(size),
          onRedeem: redeem,
        ),
      ),
    ),
  );

  testWidgets('steps the size between the players here and the limit', (
    tester,
  ) async {
    final sizes = <int>[];
    await pump(tester, _state(size: 2, limit: 3, players: 2), sizes: sizes);

    expect(find.text('2'), findsOneWidget);
    expect(find.text('Up to 3 players'), findsOneWidget);

    await tester.tap(find.byKey(const Key('roomSizeLess')));
    await tester.tap(find.byKey(const Key('roomSizeMore')));
    expect(sizes, [3], reason: 'no fewer than the two players already in');

    await pump(tester, _state(size: 3, limit: 3, players: 2), sizes: sizes);
    await tester.tap(find.byKey(const Key('roomSizeMore')));
    expect(sizes, [3], reason: 'no more than the limit');
  });

  testWidgets('quick taps count from the size asked for, not the snapshot', (
    tester,
  ) async {
    final sizes = <int>[];
    await pump(tester, _state(size: 10, players: 1), sizes: sizes);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('roomSizeLess')));
      await tester.pump();
    }
    expect(sizes, [9, 8, 7]);
    expect(find.text('7'), findsOneWidget);

    // The snapshot catches up, and then it is the one shown.
    await pump(tester, _state(size: 7, players: 1), sizes: sizes);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('a refused size goes back to what the room says', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomSizeControl(
            state: _state(size: 10, players: 1),
            onSetSize: (_) async =>
                throw const GameError(code: 'invalid_room_size'),
            onRedeem: null,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('roomSizeLess')));
    await tester.pump();
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('no code button where there are no codes', (tester) async {
    await pump(tester, _state());
    expect(find.byKey(const Key('roomSizeCodeButton')), findsNothing);
  });

  testWidgets('a code is sent, and a refusal is shown in the dialog', (
    tester,
  ) async {
    final sent = <String>[];
    await pump(
      tester,
      _state(),
      redeem: (code) async {
        sent.add(code);
        if (code == 'BAD') throw const GameError(code: 'invalid_code');
      },
    );

    await tester.tap(find.byKey(const Key('roomSizeCodeButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('roomSizeCodeField')), 'BAD');
    await tester.tap(find.byKey(const Key('roomSizeCodeSubmit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('roomSizeCodeError')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('roomSizeCodeField')),
      ' abcd-efgh-jkmn ',
    );
    await tester.tap(find.byKey(const Key('roomSizeCodeSubmit')));
    await tester.pumpAndSettle();

    expect(sent, ['BAD', 'abcd-efgh-jkmn']);
    expect(find.byKey(const Key('roomSizeCodeField')), findsNothing);
    expect(find.text('Room size unlocked.'), findsOneWidget);
  });
}
