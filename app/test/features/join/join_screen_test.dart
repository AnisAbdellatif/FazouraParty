import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/core/providers/room_tokens.dart';
import 'package:fazoura_party/features/join/join_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/buttons.dart';
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

    test('RoomCodeInputFormatter keeps 6 upper-case letters/digits', () {
      final formatted = RoomCodeInputFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: ' k7-qx 2m9z'),
      );
      expect(formatted.text, 'K7QX2M');
      expect(formatted.selection, const TextSelection.collapsed(offset: 6));
    });
  });

  group('JoinScreen', () {
    late FakeGameConnection fake;
    late ProviderContainer container;

    const joinButton = Key('joinButton');
    const codeField = Key('roomCodeField');
    const nameField = Key('displayNameField');

    Future<void> pumpJoin(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      fake = FakeGameConnection();
      // Room tokens live on the device so a refresh does not cost a player
      // their identity (PROTOCOL.md §3.3).
      SharedPreferences.setMockInitialValues({});
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

    testWidgets('join stays disabled until a full code and a name', (
      tester,
    ) async {
      await pumpJoin(tester);
      expect(isEnabled(tester, joinButton), isFalse);

      await tester.enterText(find.byKey(codeField), 'abc');
      await tester.enterText(find.byKey(nameField), 'Sam');
      await tester.pump();
      expect(isEnabled(tester, joinButton), isFalse);

      await tester.enterText(find.byKey(codeField), ' k7qx 2m ');
      await tester.pump();
      expect(isEnabled(tester, joinButton), isTrue);

      // The boxes show the normalized code.
      for (final char in 'K7QX2M'.split('')) {
        expect(find.text(char), findsOneWidget);
      }
    });

    testWidgets('rejects a name longer than 20 characters', (tester) async {
      await pumpJoin(tester);

      await tester.enterText(find.byKey(codeField), 'K7QX2M');
      await tester.enterText(find.byKey(nameField), 'x' * 21);
      await tester.pump();
      await tester.tap(find.byKey(joinButton));
      await tester.pump();

      expect(find.text('Use at most 20 characters'), findsOneWidget);
      expect(fake.joins, isEmpty);
    });

    testWidgets('joins with a normalized code and trimmed name', (
      tester,
    ) async {
      await pumpJoin(tester);

      await tester.enterText(find.byKey(codeField), ' k7qx 2m ');
      await tester.enterText(find.byKey(nameField), '  Sam ');
      await tester.pump();
      await tester.tap(find.byKey(joinButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fake.joins, hasLength(1));
      expect(fake.joins.single.roomCode, 'K7QX2M');
      expect(fake.joins.single.displayName, 'Sam');
      expect(fake.joins.single.playerToken, isNull);
      expect(
        await container
            .read(roomTokensProvider.notifier)
            .playerTokenFor('K7QX2M'),
        'token-1',
      );
      expect(find.text('ROOM K7QX2M'), findsOneWidget);
    });

    testWidgets('shows join errors from the host', (tester) async {
      await pumpJoin(tester);
      fake.joinError = const GameError(code: 'name_taken');

      await tester.enterText(find.byKey(codeField), 'K7QX2M');
      await tester.enterText(find.byKey(nameField), 'Sam');
      await tester.pump();
      await tester.tap(find.byKey(joinButton));
      await tester.pump();

      expect(
        find.text('That name is already taken in this room.'),
        findsOneWidget,
      );
    });
  });
}
