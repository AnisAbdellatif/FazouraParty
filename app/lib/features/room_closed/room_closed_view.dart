import 'package:flutter/material.dart';

import '../../core/connection/game_connection.dart';
import '../../shared/navigation.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

class RoomClosedView extends StatelessWidget {
  const RoomClosedView({super.key, required this.reason});

  final RoomClosedReason reason;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final text = switch (reason) {
      RoomClosedReason.empty => 'Everyone left, so the room closed.',
      RoomClosedReason.closed => 'The host ended the party.',
      RoomClosedReason.finished => 'The game is over.',
      RoomClosedReason.shutdown => 'The server closed the room.',
      RoomClosedReason.notFound => 'This room no longer exists.',
    };
    return FzBody(
      footer: FzButton(
        key: const Key('backHomeButton'),
        label: 'Back home',
        onPressed: () => goHome(context),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: FzEnter(
          rise: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FzEyebrow('Room closed', color: FzColors.ac2),
              const SizedBox(height: 12),
              Text("That's a wrap", style: fz.t(32)),
              const SizedBox(height: 10),
              Text(text, style: fz.m(12.5, color: FzColors.dim, height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }
}
