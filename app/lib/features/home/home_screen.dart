import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../host/host_screen.dart';
import '../host/host_setup_dialog.dart';
import '../join/join_screen.dart';
import '../quizzes/quiz_browser_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _creating = false;

  Future<void> _hostGame() async {
    final choice = await showQuizBrowser(context);
    if (choice == null || !mounted) return;
    final setup = await showHostSetupDialog(context);
    if (setup == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final api = ref.read(roomApiProvider);
      final created = await switch (choice) {
        PublicQuizChoice(:final quiz) => api.createRoom(quizId: quiz.hostId),
        LocalQuizChoice(:final quiz)
            when quiz.isPublished && quiz.wantsPublic =>
          api.createRoom(quizId: quiz.publishedId!),
        // Private quizzes are sent whole each time (QUIZ_FORMAT.md §5.7).
        LocalQuizChoice(:final quiz) => api.createRoom(inlineQuiz: quiz.quiz),
      };
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

    return Scaffold(
      body: FzPage(
        // No profile entry point: there are no accounts and no game history
        // (AGENTS.md §2), so features/mock/profile_screen.dart would show
        // invented numbers. It stays as the Phase 2 design reference.
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
          padding: const EdgeInsets.only(top: 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The app's own icon is the wordmark, so it stands in for the
              // design's text lockup rather than repeating it.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: FzColors.ac.withValues(alpha: .22),
                      blurRadius: 52,
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/icon.png',
                    key: const Key('appIcon'),
                    width: 148,
                    height: 148,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: 'Fazoura Party',
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(width: 78, height: 5, color: FzColors.ac2),
              const SizedBox(height: 22),
              Text(
                'فزورة  fazoura (n.) — a riddle.\n'
                'one phone each, one wager each,\n'
                'ten questions of shouting.',
                style: fz.m(
                  15,
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
