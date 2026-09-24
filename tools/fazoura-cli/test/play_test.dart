import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fazoura_cli/fazoura_cli.dart';
import 'package:fazoura_cli/src/context.dart';
import 'package:fazoura_cli/src/play/bots.dart';
import 'package:fazoura_cli/src/play/narrator.dart';
import 'package:fazoura_cli/src/play/seat.dart';
import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/connection/lan_game_connection.dart';
import 'package:fazoura_party/core/lan/lan_host.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:test/test.dart';

/// Collects what an [Output] prints, one line per entry.
class _Lines implements StreamConsumer<List<int>> {
  final lines = <String>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      lines.addAll(const LineSplitter().convert(utf8.decode(chunk)));
    }
  }

  @override
  Future<void> close() async {}
}

const _quiz = QuizDocument(
  title: 'Capitals',
  tags: ['geography'],
  questions: [
    QuizQuestion(prompt: 'Capital of France?', acceptedAnswers: ['Paris']),
    QuizQuestion(prompt: 'Capital of Japan?', acceptedAnswers: ['Tokyo']),
  ],
);

void main() {
  // The LAN host is the app's own, in this process: the whole game runs
  // without a server, over real sockets, through the same client code.
  test('an automatic host and two bots play a game to the end', () {
    return absorbSocketNoise(() async {
      final lan = await LanHost.start(port: 0);
      addTearDown(lan.stop);
      final url = 'http://127.0.0.1:${lan.port}';
      final printed = _Lines();
      final output = Output(
        json: false,
        out: IOSink(printed),
        err: IOSink(_Lines()),
      );

      Seat seat(String label, {bool narrate = true}) => Seat(
        label: label,
        connection: LanGameConnection(baseUrl: url),
        output: output,
        narrate: narrate,
      )..watch();

      final host = seat('host');
      await host.connection.joinAsHost(lan.roomCode, lan.hostToken);
      const selection = [InlineQuizSelection(_quiz)];
      const configure = Configure(
        questionCount: 2,
        timeLimit: Duration(seconds: 10),
      );
      expect(await prepareLobby(host, selection, configure), isTrue);

      final hostBot = HostBot(
        host,
        const HostPlan(
          selection: selection,
          configure: configure,
          startWhen: 2,
          pace: Duration(milliseconds: 50),
        ),
      )..start();

      final knowledge = AnswerPlan.learn([_quiz]);
      final right = seat('Right', narrate: false);
      final wrong = seat('Wrong', narrate: false);
      await right.connection.join(lan.roomCode, 'Right');
      await wrong.connection.join(lan.roomCode, 'Wrong');
      final bots = [
        PlayerBot(
          right,
          AnswerPlan(
            knowledge: knowledge,
            minDelay: Duration.zero,
            maxDelay: Duration.zero,
          ),
        )..start(),
        PlayerBot(
          wrong,
          AnswerPlan(
            knowledge: knowledge,
            accuracy: 0,
            minDelay: Duration.zero,
            maxDelay: Duration.zero,
          ),
        )..start(),
      ];

      final finished = right.updates.firstWhere(
        (s) => s.phase == Phase.finished,
      );
      await hostBot.done.timeout(const Duration(seconds: 30));
      final last = await finished;

      final scores = {for (final p in last.players) p.name: p.score};
      expect(scores, {'Right': 20, 'Wrong': -20});
      expect(await right.closed, RoomClosedReason.closed);

      // The room's story is told once, by the host, not once per seat.
      expect(printed.lines.where((l) => l.contains('game over')), hasLength(1));
      expect(printed.lines, contains('[Right] answers "Paris"'));

      for (final bot in bots) {
        bot.stop();
      }
      for (final s in [host, right, wrong]) {
        await s.leave();
      }
    });
  });

  test(
    'a slow bot still answers when the host ends the question early',
    () => absorbSocketNoise(() async {
      final lan = await LanHost.start(port: 0);
      addTearDown(lan.stop);
      final url = 'http://127.0.0.1:${lan.port}';
      final output = Output(
        json: false,
        out: IOSink(_Lines()),
        err: IOSink(_Lines()),
      );

      Seat seat(String label) => Seat(
        label: label,
        connection: LanGameConnection(baseUrl: url),
        output: output,
      )..watch();

      final host = seat('host');
      await host.connection.joinAsHost(lan.roomCode, lan.hostToken);
      await prepareLobby(host, const [InlineQuizSelection(_quiz)], null);

      final slow = seat('Slow');
      final other = seat('Other');
      await slow.connection.join(lan.roomCode, 'Slow');
      await other.connection.join(lan.roomCode, 'Other');
      // Means to answer in 30 s; the question gives it far less than that.
      final bot = PlayerBot(
        slow,
        AnswerPlan(
          knowledge: AnswerPlan.learn([_quiz]),
          minDelay: const Duration(seconds: 30),
          maxDelay: const Duration(seconds: 30),
        ),
      )..start();

      await host.connection.hostNext();
      await slow.updates.firstWhere((s) => s.phase == Phase.question);
      // The host ends it: the deadline comes in to the closing window, and the
      // bot's answer comes in with it, as the app's typed answer would.
      await host.connection.hostNext();

      final scored = await slow.updates
          .firstWhere((s) => s.phase == Phase.scoring)
          .timeout(const Duration(seconds: 10));
      expect(scored.you.submission?.correct, isTrue);

      bot.stop();
      for (final s in [host, slow, other]) {
        await s.leave();
      }
    }),
  );

  group('narrator', () {
    RoomState state(Map<String, Object?> overrides) => RoomState.fromJson({
      'protocol_version': 9,
      'room_code': 'K7QX2M',
      'mode': 'cloud',
      'phase': 'lobby',
      'server_time': 1000,
      'question_count': 2,
      'players': <Object>[],
      'you': {'role': 'host'},
      ...overrides,
    });

    Map<String, Object?> player(String id, {bool submitted = false}) => {
      'id': id,
      'name': id,
      'score': 0,
      'connected': true,
      'has_submitted': submitted,
    };

    test('says who joined and who answered, and nothing twice', () {
      final lobby = state({
        'players': [player('Sam')],
      });
      final joined = state({
        'players': [player('Sam'), player('Kim')],
      });
      expect(narrate(lobby, joined), ['+ Kim joined']);
      expect(narrate(joined, joined), isEmpty);

      Map<String, Object?> asking(bool kimAnswered) => {
        'phase': 'question',
        'question_index': 0,
        'deadline': 31000,
        'question': {
          'id': 'q1',
          'type': 'text',
          'prompt': 'Capital of France?',
          'time_limit_ms': 30000,
        },
        'players': [player('Sam'), player('Kim', submitted: kimAnswered)],
      };
      expect(narrate(state(asking(false)), state(asking(true))), [
        'Kim answered (1/2)',
      ]);
    });

    test('notices the host pulling the deadline in', () {
      Map<String, Object?> question(int deadline) => {
        'phase': 'question',
        'question_index': 0,
        'deadline': deadline,
        'question': {
          'id': 'q1',
          'type': 'text',
          'prompt': '?',
          'time_limit_ms': 30000,
        },
      };
      expect(narrate(state(question(31000)), state(question(4000))), [
        'closing · 3s left',
      ]);
    });

    test('says when the room is resized or unlocked', () {
      final usual = state({'room_size': 32, 'room_size_limit': 32});
      expect(narrate(usual, state({'room_size': 8, 'room_size_limit': 32})), [
        'room size 8',
      ]);
      expect(narrate(usual, state({'room_size': 60, 'room_size_limit': 60})), [
        'room size unlocked up to 60',
        'room size 60',
      ]);
    });
  });
}
