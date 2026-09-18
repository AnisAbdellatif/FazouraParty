import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/features/host/host_exit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Leaving is the one action a host can take that ends everyone else's game,
/// so it is never silent (PROTOCOL.md §3.4).
void main() {
  const host = PlayerSummary(
    id: 'p_host',
    name: 'Hana',
    score: 0,
    connected: true,
    hasSubmitted: false,
    isHost: true,
  );
  const sam = PlayerSummary(
    id: 'p_sam',
    name: 'Sam',
    score: 3,
    connected: true,
    hasSubmitted: false,
  );
  const gone = PlayerSummary(
    id: 'p_gone',
    name: 'Alex',
    score: 1,
    connected: false,
    hasSubmitted: false,
  );

  Future<HostExit?> open(
    WidgetTester tester,
    List<PlayerSummary> players, {
    bool allowHandOver = true,
  }) async {
    HostExit? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showHostExitDialog(
                  context,
                  players: players,
                  hostPlayerId: 'p_host',
                  allowHandOver: allowHandOver,
                );
              },
              child: const Text('leave'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('offers each connected player as a successor', (tester) async {
    await open(tester, const [host, sam, gone]);

    expect(find.text('Who takes over?'), findsOneWidget);
    expect(find.byKey(const ValueKey('handOver-p_sam')), findsOneWidget);

    // Not the host themselves, and not someone who has already left — handing
    // the room to either would leave it hostless.
    expect(find.byKey(const ValueKey('handOver-p_host')), findsNothing);
    expect(find.byKey(const ValueKey('handOver-p_gone')), findsNothing);
  });

  testWidgets('picking a player hands them the room', (tester) async {
    HostExit? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                choice = await showHostExitDialog(
                  context,
                  players: const [host, sam],
                  hostPlayerId: 'p_host',
                );
              },
              child: const Text('leave'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('handOver-p_sam')));
    await tester.pumpAndSettle();

    expect(choice, isA<HostExitHandOver>());
    expect((choice! as HostExitHandOver).playerId, 'p_sam');
  });

  testWidgets('a host alone is told the room will close', (tester) async {
    await open(tester, const [host]);

    expect(find.text('End the party?'), findsOneWidget);
    expect(find.textContaining('Nobody else is here'), findsOneWidget);
    expect(find.byKey(const Key('hostExitCloseButton')), findsOneWidget);
  });

  testWidgets('a LAN host cannot hand over the server', (tester) async {
    await open(tester, const [host, sam], allowHandOver: false);

    expect(find.text('End the LAN party?'), findsOneWidget);
    expect(find.textContaining('server cannot be handed over'), findsOneWidget);
    expect(find.byKey(const ValueKey('handOver-p_sam')), findsNothing);
    expect(find.byKey(const Key('hostExitCloseButton')), findsOneWidget);
  });

  testWidgets('staying returns nothing, so the host does not leave', (
    tester,
  ) async {
    HostExit? choice = const HostExitClose();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                choice = await showHostExitDialog(
                  context,
                  players: const [host, sam],
                  hostPlayerId: 'p_host',
                );
              },
              child: const Text('leave'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('hostExitStayButton')));
    await tester.pumpAndSettle();

    expect(choice, isNull);
  });
}
