/// What the device still remembers after the host walks out.
///
/// A host never types a room code, so the only way back is the token this
/// device kept (PROTOCOL.md §3.3), offered as "Back to room" on the home
/// screen. Once the host has left, that token is dead — the room is gone, or
/// the server has bumped which host token it accepts because the role moved to
/// someone else — so keeping it leaves a button that can only produce an error.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/core/providers/room_tokens.dart';
import 'package:fazoura_party/features/host/host_screen.dart';
import 'package:fazoura_party/shared/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

void main() {
  late FakeGameConnection fake;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'fazoura.room_tokens': jsonEncode([
        {
          'code': 'K7QX2M',
          'player_token': null,
          'host_token': 'host-tok',
          'saved_at': DateTime.now().toUtc().toIso8601String(),
        },
      ]),
    });
  });

  Future<void> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection(
      initialState: questionStateForHost(playing: false),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: HostScreen(roomCode: 'K7QX2M'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Read from storage rather than from the provider's cache, so a test cannot
  /// pass on a value that was only ever in memory.
  Future<List<RoomToken>> remembered() =>
      container.read(roomTokenStoreProvider).list();

  Future<void> openExitDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Leave'));
    await tester.pumpAndSettle();
  }

  testWidgets('ending the party forgets the room', (tester) async {
    await pumpHost(tester);
    expect(await remembered(), hasLength(1), reason: 'kept on the way in');

    await openExitDialog(tester);
    await tester.tap(find.byKey(const Key('hostExitCloseButton')));
    await tester.pumpAndSettle();

    expect(fake.closeCalls, 1);
    expect(await remembered(), isEmpty);
  });

  testWidgets('handing the room over forgets it', (tester) async {
    await pumpHost(tester);

    await openExitDialog(tester);
    await tester.tap(find.byKey(const Key('handOver-p_3f9a')));
    await tester.pumpAndSettle();

    // The server accepts one host token at a time and bumps it whenever the
    // role moves, so this device's is dead the moment Sam holds it.
    expect(fake.transfers, ['p_3f9a']);
    expect(await remembered(), isEmpty);
  });

  testWidgets('a room that ends underneath the host forgets it', (
    tester,
  ) async {
    await pumpHost(tester);
    expect(await remembered(), hasLength(1));

    fake.closedCompleter.complete(RoomClosedReason.finished);
    await tester.pumpAndSettle();

    expect(await remembered(), isEmpty);
  });

  testWidgets('leaving with the back gesture forgets it', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection(
      initialState: questionStateForHost(playing: false),
    );
    final navigator = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(navigatorKey: navigator, home: const SizedBox());
          },
        ),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        // The route the app really pushes this screen with (AGENTS.md §7), so
        // popping it here pops what a back gesture pops in the app.
        FzPageRoute<void>(builder: (_) => const HostScreen(roomCode: 'K7QX2M')),
      ),
    );
    await tester.pumpAndSettle();
    expect(await remembered(), hasLength(1));

    // The browser's back button, or Android's. It does not go through the exit
    // dialog at all, so nothing along that path can be what forgets the room.
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(await remembered(), isEmpty);
  });

  testWidgets('staying keeps the room', (tester) async {
    await pumpHost(tester);

    await openExitDialog(tester);
    await tester.tap(find.byKey(const Key('hostExitStayButton')));
    await tester.pumpAndSettle();

    expect(fake.closeCalls, 0);
    expect(fake.transfers, isEmpty);
    expect(await remembered(), hasLength(1));
  });
}
