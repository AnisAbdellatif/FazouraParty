/// The base direction of text someone wrote (UAX #9 rule P2).
@TestOn('vm')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fazoura_party/shared/widgets/fz_direction.dart';

void main() {
  group('directionOf', () {
    test('plain text in either script', () {
      expect(directionOf('What is the capital of Algeria?'), TextDirection.ltr);
      expect(directionOf('ما هي عاصمة الجزائر؟'), TextDirection.rtl);
    });

    test('the first strong character decides, not the majority', () {
      // An Arabic question that happens to name a Latin thing is still Arabic,
      // and an English question quoting Arabic is still English.
      expect(directionOf('ما هو الـ Matrix؟'), TextDirection.rtl);
      expect(directionOf('What does فزورة mean?'), TextDirection.ltr);
    });

    test('digits, punctuation and spaces are neutral', () {
      // "?12 ماذا" — the strong character is Arabic, several runes in.
      expect(directionOf('  «12» ماذا'), TextDirection.rtl);
      expect(directionOf('"2001" a film'), TextDirection.ltr);
    });

    test('nothing strong stays with the interface', () {
      for (final text in [
        '',
        '   ',
        '42',
        'K7QX2M'.replaceAll(RegExp('[A-Z]'), '9'),
        '· — ·',
      ]) {
        expect(directionOf(text), TextDirection.ltr, reason: 'for "$text"');
      }
    });

    test('a room code is Latin, so it reads left to right', () {
      expect(directionOf('K7QX2M'), TextDirection.ltr);
    });

    test('Hebrew and the Arabic presentation forms count as right to left', () {
      expect(directionOf('שלום'), TextDirection.rtl);
      expect(directionOf('ﻳﺎ'), TextDirection.rtl);
    });

    test('other scripts read left to right', () {
      expect(directionOf('Καλημέρα'), TextDirection.ltr);
      expect(directionOf('Привет'), TextDirection.ltr);
      expect(directionOf('東京'), TextDirection.ltr);
    });
  });

  testWidgets('FzDirection turns a block round', (tester) async {
    Future<TextDirection> directionUnder(String text) async {
      late TextDirection seen;
      await tester.pumpWidget(
        FzDirection(
          text: text,
          child: Builder(
            builder: (context) {
              seen = Directionality.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return seen;
    }

    expect(await directionUnder('ما هي عاصمة مصر؟'), TextDirection.rtl);
    expect(await directionUnder('Capital of Egypt?'), TextDirection.ltr);
  });

  testWidgets('FzTypingDirection follows what is being typed', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    late TextDirection seen;

    await tester.pumpWidget(
      FzTypingDirection(
        controller: controller,
        child: Builder(
          builder: (context) {
            seen = Directionality.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    // Empty: the hint is the interface's, so it keeps the interface's side.
    expect(seen, TextDirection.ltr);

    controller.text = 'القاهرة';
    await tester.pump();
    expect(seen, TextDirection.rtl);

    controller.text = 'Cairo';
    await tester.pump();
    expect(seen, TextDirection.ltr);
  });
}
