import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/navigation.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_direction.dart';
import '../join/join_screen.dart';

/// Rooms their hosts chose to list, to join without being given a code
/// (PROTOCOL.md §3.5). Tapping one opens [JoinScreen] with the code filled in.
///
/// Refreshes itself while open, since a lobby fills up and a game moves on
/// while somebody is looking at the list.
class PublicRoomsScreen extends ConsumerStatefulWidget {
  const PublicRoomsScreen({super.key});

  /// How often the list is fetched again while it is on screen.
  static const refreshEvery = Duration(seconds: 5);

  @override
  ConsumerState<PublicRoomsScreen> createState() => _PublicRoomsScreenState();
}

class _PublicRoomsScreenState extends ConsumerState<PublicRoomsScreen> {
  List<PublicRoom>? _rooms;
  String? _error;
  bool _loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(PublicRoomsScreen.refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final rooms = await ref.read(roomApiProvider).listRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // A list already on screen stays there: one failed refresh is not a
      // reason to take away rooms that were joinable five seconds ago.
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  void _join(PublicRoom room) {
    Navigator.of(context).push(
      FzPageRoute<void>(builder: (_) => JoinScreen(initialCode: room.roomCode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final rooms = _rooms;

    return Scaffold(
      body: FzPage(
        header: Row(
          children: [
            FzCircleButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Spacer(),
            FzCircleButton(
              key: const Key('refreshRoomsButton'),
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text('Public rooms', style: fz.t(31, tracking: -.03)),
            const SizedBox(height: 10),
            Text(
              'Parties anyone can join. Every quiz here is from the library.',
              style: fz.m(12, color: FzColors.dim, height: 1.5),
            ),
            const SizedBox(height: 24),
            if (_error != null && rooms == null)
              _Message(
                key: const Key('roomsError'),
                text: _error!,
                action: FzButton(
                  label: 'Try again',
                  kind: FzButtonKind.outline,
                  height: 48,
                  fontSize: 15,
                  onPressed: _loading ? null : _load,
                ),
              )
            else if (rooms == null)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rooms.isEmpty)
              const _Message(
                key: Key('noRooms'),
                text:
                    'No public rooms right now.\n'
                    'Start a party and switch on "Show in public rooms".',
              )
            else
              for (final room in rooms) ...[
                _RoomCard(
                  key: ValueKey('publicRoom-${room.roomCode}'),
                  room: room,
                  onTap: () => _join(room),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({super.key, required this.room, required this.onTap});

  final PublicRoom room;
  final VoidCallback onTap;

  /// Where the game is, in words: a lobby is the best room to walk into, so
  /// it says so rather than a question number.
  String get _status {
    final players = room.playerCount == 1
        ? '1 player'
        : '${room.playerCount} players';
    final index = room.questionIndex;
    final where = switch (room.phase) {
      Phase.lobby => 'Waiting to start',
      Phase.finished => 'Between games',
      _ when index != null => 'Question ${index + 1} of ${room.questionCount}',
      _ => 'Playing',
    };
    return '$where · $players';
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final titles = room.packTitles.join(' · ');
    final waiting = room.phase == Phase.lobby;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: FzPanel(
          borderColor: waiting ? FzColors.ac : FzColors.line,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (titles.isEmpty)
                      Text(
                        'Choosing quizzes…',
                        style: fz.h(17, color: FzColors.dim),
                      )
                    else
                      FzDirection(
                        text: titles,
                        child: Text(
                          titles,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: fz.h(17, weight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      _status,
                      style: fz.m(
                        11.5,
                        color: waiting ? FzColors.ac : FzColors.dim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(room.roomCode, style: fz.m(13, color: FzColors.faint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: fz.m(12.5, color: FzColors.dim, height: 1.6),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
