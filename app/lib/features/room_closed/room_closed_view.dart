import 'package:flutter/material.dart';

import '../../core/connection/game_connection.dart';
import '../../shared/navigation.dart';

class RoomClosedView extends StatelessWidget {
  const RoomClosedView({super.key, required this.reason});

  final RoomClosedReason reason;

  @override
  Widget build(BuildContext context) {
    final text = switch (reason) {
      RoomClosedReason.hostTimeout => 'The host has been away for too long.',
      RoomClosedReason.finished => 'The game is over.',
      RoomClosedReason.shutdown => 'The server closed the room.',
      RoomClosedReason.notFound => 'This room no longer exists.',
    };
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.door_front_door_outlined, size: 64),
            const SizedBox(height: 16),
            Text('Room closed', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => goHome(context),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}
