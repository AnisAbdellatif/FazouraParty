import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/core/providers/player_tokens.dart';
import 'package:fazoura_party/features/join/join_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_game_connection.dart';

void main() {
  group('room code helpers', () {
    test('normalizeRoomCode upper-cases and strips whitespace', () {
      expect(normalizeRoomCode(' k7qx 2m\t'), 'K7QX2M');
    });

    test('validators', () {
      expect(validateRoomCode(''), isNotNull);
      expect(validateRoomCode('k7q'), isNotNull);
      expect(validateRoomCode('K7-X2M'), isNotNull);
      expect(validateRoomCode(' k7qx 2m '), isNull);
      expect(validateDisplayName('   '), isNotNull);
      expect(validateDisplayName('a' * 21), isNotNull);
      expect(validateDisplayName('  ${'a' * 20}  '), isNull);
    });
  });

  group('JoinScreen', () {
    late FakeGameConnection fake;
    late ProviderContainer container;

    Future<void> pumpJoin(WidgetTester tester) async {
      fake = FakeGameConnection();
      container = ProviderContainer.test(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: JoinScreen()),
        ),
      );
    }

    testWidgets('shows validation errors and does not join', (tester) async {
      await pumpJoin(tester);

      await tester.tap(find.byKey(const Key('joinButton')));
      await tester.pump();

      expect(find.text('Enter the room code'), findsOneWidget);
      expect(find.text('Enter a display name'), findsOneWidget);
      expect(fake.joins, isEmpty);

      await tester.enterText(find.byKey(const Key('roomCodeField')), 'abc');
      await tester.enterText(
        find.byKey(const Key('displayNameField')),
        'x' * 21,
      );
      await tester.tap(find.byKey(const Key('joinButton')));
      await tester.pump();

      expect(find.text('Room codes are 6 letters or digits'), findsOneWidget);
      expect(find.text('Use at most 20 characters'), findsOneWidget);
      expect(fake.joins, isEmpty);
    });

    testWidgets('joins with a normalized code and trimmed name', (
      tester,
    ) async {
      await pumpJoin(tester);

      await tester.enterText(
        find.byKey(const Key('roomCodeField')),
        ' k7qx 2m ',
      );
      await tester.enterText(
        find.byKey(const Key('displayNameField')),
        '  Sam ',
      );
      await tester.tap(find.byKey(const Key('joinButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fake.joins, hasLength(1));
      expect(fake.joins.single.roomCode, 'K7QX2M');
      expect(fake.joins.single.displayName, 'Sam');
      expect(fake.joins.single.playerToken, isNull);
      expect(container.read(playerTokensProvider), {'K7QX2M': 'token-1'});
      expect(find.text('Room K7QX2M'), findsOneWidget);
    });

    testWidgets('shows join errors from the host', (tester) async {
      await pumpJoin(tester);
      fake.joinError = const GameError(code: 'name_taken');

      await tester.enterText(find.byKey(const Key('roomCodeField')), 'K7QX2M');
      await tester.enterText(find.byKey(const Key('displayNameField')), 'Sam');
      await tester.tap(find.byKey(const Key('joinButton')));
      await tester.pump();

      expect(
        find.text('That name is already taken in this room.'),
        findsOneWidget,
      );
    });
  });
}
