import 'package:args/command_runner.dart';
import 'package:fazoura_party/core/models/models.dart';

import '../context.dart';

/// `GET /api/rooms` (PROTOCOL.md §3.5).
class RoomsCommand extends Command<int> {
  RoomsCommand(this._context);

  final Context _context;

  @override
  String get name => 'rooms';

  @override
  String get description => 'Public rooms anyone can join.';

  @override
  Future<int> run() async {
    final rooms = await _context.rooms.listRooms();
    _context.output.result(
      [for (final room in rooms) room.toJson()],
      () => [
        for (final room in rooms)
          '${room.roomCode}  ${_where(room).padRight(18)}'
              ' ${room.playerCount.toString().padLeft(3)} in'
              '  ${room.packTitles.isEmpty ? '(choosing quizzes)' : room.packTitles.join(' · ')}',
        if (rooms.isEmpty) 'no public rooms right now',
      ].join('\n'),
    );
    return 0;
  }

  static String _where(PublicRoom room) => switch (room.phase) {
    Phase.lobby => 'waiting to start',
    Phase.finished => 'between games',
    _ when room.questionIndex != null =>
      'question ${room.questionIndex! + 1}/${room.questionCount}',
    _ => 'playing',
  };
}
