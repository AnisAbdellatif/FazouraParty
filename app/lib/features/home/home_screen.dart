import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../host/host_screen.dart';
import '../host/host_setup_dialog.dart';
import '../join/join_screen.dart';
import '../mock/pack_picker_screen.dart';
import '../mock/profile_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _creating = false;

  Future<void> _hostGame() async {
    final packId = await showPackPicker(context);
    if (packId == null || !mounted) return;
    final setup = await showHostSetupDialog(context);
    if (setup == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final created = await ref
          .read(roomApiProvider)
          .createRoom(packId: packId);
      ref.invalidate(gameConnectionProvider);
      await ref
          .read(gameConnectionProvider)
          .joinAsHost(
            created.roomCode,
            created.hostToken,
            displayName: setup.displayName,
          );
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
    final fz = FzTheme.of(context);
    TextStyle wordmark() => fz.displayFont(
      const TextStyle(
        fontSize: 64,
        fontWeight: FontWeight.w900,
        height: .84,
        letterSpacing: -3.2,
      ),
    );

    return Scaffold(
      body: FzPage(
        header: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FzCircleButton(
              key: const Key('profileButton'),
              icon: Icons.person_outline,
              tooltip: 'Profile (preview)',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              ),
            ),
          ],
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FzButton(
              key: const Key('hostGameButton'),
              label: _creating ? 'Creating…' : 'Start a party',
              trailing: 'host',
              onPressed: _creating ? null : _hostGame,
            ),
            const SizedBox(height: 11),
            FzButton(
              key: const Key('joinGameButton'),
              label: 'Join with a code',
              trailing: '6 chars',
              kind: FzButtonKind.outline,
              onPressed: _creating
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const JoinScreen(),
                      ),
                    ),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FAZOURA',
                      style: wordmark().copyWith(
                        color: FzColors.ac,
                        shadows: [
                          Shadow(
                            color: FzColors.ac.withValues(alpha: .45),
                            blurRadius: 42,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PARTY',
                      style: wordmark().copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 1.8
                          ..color = FzColors.ac2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(width: 52, height: 4, color: FzColors.ac2),
              const SizedBox(height: 18),
              Text(
                'fazoura (n.) — a riddle.\n'
                'one phone each, one wager each,\n'
                'ten questions of shouting.',
                style: fz.m(
                  13,
                  weight: FontWeight.w400,
                  color: FzColors.dim,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
