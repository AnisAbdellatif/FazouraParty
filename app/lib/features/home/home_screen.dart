import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/providers/lan_providers.dart';
import '../../core/providers/room_tokens.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/update_banner.dart';
import '../host/host_setup_dialog.dart';
import '../join/join_screen.dart';

// Everything a guest following a link never opens. Joining a game is the one
// path that has to be quick, and hosting, writing a quiz and settings between
// them account for most of the bundle — the editor alone carries the photo
// pipeline and `package:image`.
import '../host/host_screen.dart' deferred as host_screen;
import '../quizzes/quiz_editor_screen.dart' deferred as editor;
import '../settings/settings_screen.dart' deferred as settings;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _creating = false;

  Future<void> _hostGame() async {
    final setup = await showHostSetupDialog(context);
    if (setup == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final created = setup.overLan
          ? await _createLanRoom()
          : await ref.read(roomApiProvider).createRoom();
      await host_screen.loadLibrary();
      ref.invalidate(gameConnectionProvider);
      // Remembered before the join, not after: a host who closes the tab on
      // the lobby still has a room, and this is the only way back to it — the
      // host never types a code (PROTOCOL.md §3.3).
      if (!setup.overLan) {
        await ref
            .read(roomTokensProvider.notifier)
            .saveHostToken(created.roomCode, created.hostToken);
      }
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
          builder: (_) => host_screen.HostScreen(roomCode: created.roomCode),
        ),
      );
    } catch (error) {
      ref.invalidate(gameConnectionProvider);
      // A LAN room whose host never joined would keep a port open and a party
      // running that nobody is in.
      await ref.read(hostedLanRoomProvider.notifier).stop();
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _openSettings() async {
    await settings.loadLibrary();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => settings.SettingsScreen()));
  }

  /// Opens the quiz editor, which is a chunk of its own: the photo pipeline
  /// and `package:image` live behind it.
  Future<void> _createQuiz() async {
    await editor.loadLibrary();
    if (!mounted) return;
    await editor.showQuizEditor(context);
  }

  /// Takes back a room this device is still the host of. The room may have
  /// ended while the app was away, in which case the host is told and the
  /// tokens are forgotten (§4.1).
  Future<void> _resumeHosting(RoomToken room) async {
    setState(() => _creating = true);
    try {
      await host_screen.loadLibrary();
      ref.read(currentGameTargetProvider.notifier).useCloud();
      ref.invalidate(gameConnectionProvider);
      await ref
          .read(gameConnectionProvider)
          .joinAsHost(room.code, room.hostToken!);
      if (!mounted) return;
      setState(() => _creating = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => host_screen.HostScreen(roomCode: room.code),
        ),
      );
    } catch (error) {
      ref.invalidate(gameConnectionProvider);
      if (error is GameError &&
          (error.code == 'room_not_found' || error.code == 'invalid_token')) {
        await ref.read(roomTokensProvider.notifier).drop(room.code);
      }
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  /// Starts a room on this device. No HTTP call: the host holds the whole game
  /// in process and hands out the same room code and host token shape as the
  /// cloud server (PROTOCOL.md §3.1).
  Future<CreatedRoom> _createLanRoom() async {
    final host = await ref.read(hostedLanRoomProvider.notifier).start();
    return CreatedRoom(roomCode: host.roomCode, hostToken: host.hostToken);
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    // A room this device still holds the host token for, offered until it
    // stops working or ages out (PROTOCOL.md §3.3).
    final hosted = ref
        .watch(roomTokensProvider)
        .value
        ?.where((room) => room.hostToken != null)
        .firstOrNull;

    return Scaffold(
      body: FzPage(
        // No profile entry point: there are no accounts and no game history
        // (AGENTS.md §2), so features/mock/profile_screen.dart would show
        // invented numbers. It stays as the Phase 2 design reference.
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nothing on the web or in a development build; on Android, the
            // one place a newer APK is offered (README, "Releasing the
            // Android app").
            const UpdateBanner(),
            if (hosted != null) ...[
              FzButton(
                key: const Key('resumeHostingButton'),
                label: 'Back to room ${hosted.code}',
                trailing: 'hosting',
                onPressed: _creating ? null : () => _resumeHosting(hosted),
              ),
              const SizedBox(height: 11),
            ],
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
            const SizedBox(height: 11),
            FzButton(
              key: const Key('createQuizButton'),
              label: 'Create a quiz',
              trailing: 'offline',
              kind: FzButtonKind.outline,
              onPressed: _creating ? null : _createQuiz,
            ),
            const SizedBox(height: 11),
            FzButton(
              key: const Key('settingsButton'),
              label: 'Settings',
              trailing: 'app',
              kind: FzButtonKind.outline,
              onPressed: _creating ? null : _openSettings,
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
                'one phone each, one answer each,\n'
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
