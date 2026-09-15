import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../host/host_screen.dart';
import '../join/join_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _creating = false;

  Future<void> _hostGame() async {
    setState(() => _creating = true);
    try {
      final created = await ref.read(roomApiProvider).createRoom();
      ref.invalidate(gameConnectionProvider);
      await ref
          .read(gameConnectionProvider)
          .joinAsHost(created.roomCode, created.hostToken);
      if (!mounted) return;
      setState(() => _creating = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HostScreen(roomCode: created.roomCode),
        ),
      );
    } catch (error) {
      ref.invalidate(gameConnectionProvider);
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Fazoura Party',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Trivia with confidence wagers',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    key: const Key('hostGameButton'),
                    onPressed: _creating ? null : _hostGame,
                    icon: _creating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.tv),
                    label: const Text('Host a game'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('joinGameButton'),
                    onPressed: _creating
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const JoinScreen(),
                            ),
                          ),
                    icon: const Icon(Icons.login),
                    label: const Text('Join a game'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
