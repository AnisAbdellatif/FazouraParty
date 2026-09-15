import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/game_connection.dart';
import '../../core/providers/connection_providers.dart';

/// Thin banner shown while the socket is reconnecting or lost.
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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.wifi_off, size: 18, color: colors.onErrorContainer),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: colors.onErrorContainer)),
          ],
        ),
      ),
    );
  }
}
