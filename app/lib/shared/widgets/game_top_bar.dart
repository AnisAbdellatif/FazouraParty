import 'package:flutter/material.dart';

import 'fz.dart';

/// Top row of the in-room screens: leave button, eyebrow label, optional
/// trailing widget.
class GameTopBar extends StatelessWidget {
  const GameTopBar({
    super.key,
    required this.label,
    required this.onLeave,
    this.trailing,
  });

  final String label;
  final VoidCallback onLeave;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
          child: Row(
            children: [
              FzCircleButton(
                icon: Icons.close,
                tooltip: 'Leave',
                onPressed: onLeave,
              ),
              const SizedBox(width: 12),
              Expanded(child: FzEyebrow(label)),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
