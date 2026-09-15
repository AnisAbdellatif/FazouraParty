import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/game_connection.dart';
import '../../core/providers/connection_providers.dart';
import '../theme/fz_theme.dart';
import 'fz.dart';

/// Thin pink bar shown while the socket is reconnecting or lost.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider).value;
    final text = switch (status) {
      ConnectionStatus.reconnecting => 'Reconnecting…',
      ConnectionStatus.disconnected => 'Disconnected',
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Container(
      color: FzColors.ac2.withValues(alpha: .14),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Row(
        children: [
          FzBlink(
            period: const Duration(milliseconds: 500),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: FzColors.ac2,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FzEyebrow(text, color: FzColors.ac2),
        ],
      ),
    );
  }
}
