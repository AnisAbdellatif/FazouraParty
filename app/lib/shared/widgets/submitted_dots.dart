import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../theme/fz_theme.dart';
import 'fz_motion.dart';

/// One dot per player, green once they have answered the current question.
class SubmittedDots extends StatelessWidget {
  const SubmittedDots({super.key, required this.players});

  final List<PlayerSummary> players;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        alignment: WrapAlignment.end,
        children: [
          for (final player in players)
            Tooltip(
              message:
                  '${player.name}: '
                  '${player.hasSubmitted ? 'answered' : 'thinking'}',
              // The room watching itself fill in. A pop as each answer lands
              // is the only sign a player who has already answered gets that
              // anything is still happening.
              child: FzPop(
                trigger: player.hasSubmitted ? player.id : null,
                child: AnimatedContainer(
                  key: ValueKey('submitted-${player.id}'),
                  duration: const Duration(milliseconds: 220),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: player.hasSubmitted
                        ? FzColors.ok
                        : const Color(0x2EFBF6EC),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
