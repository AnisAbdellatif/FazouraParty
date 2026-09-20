/// Reading direction for text people wrote, rather than for the app's chrome.
///
/// The interface is English and lays out left to right, but the content never
/// has to be: a quiz, a name, an answer typed into a phone. Flutter shapes a
/// mixed paragraph correctly on its own; what it cannot guess is the
/// paragraph's *base* direction, which decides which edge the text starts at,
/// where trailing punctuation lands, and which end a wrapped line hangs from.
/// Left as the ambient LTR, an Arabic question reads with its full stop on the
/// wrong side and hugs the wrong margin.
library;

import 'package:flutter/widgets.dart';

/// The direction to lay [text] out in, from its first strong character —
/// the rule Unicode itself uses (UAX #9, rule P2) and the one a browser
/// applies for `dir="auto"`.
///
/// Digits, punctuation and spaces are neutral and skipped: `"?12 ماذا"` is
/// Arabic, and a room code is not a language at all. Nothing strong either way
/// — a score, an empty field — stays with the interface.
TextDirection directionOf(String text) {
  for (final rune in text.runes) {
    if (_isRtl(rune)) return TextDirection.rtl;
    if (_isLtr(rune)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

/// Hebrew, Arabic and the scripts written with them, including the legacy
/// presentation forms a copy-paste can still carry.
bool _isRtl(int rune) =>
    (rune >= 0x0590 && rune <= 0x08FF) ||
    (rune >= 0xFB1D && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF) ||
    (rune >= 0x10800 && rune <= 0x10FFF) ||
    (rune >= 0x1E800 && rune <= 0x1EFFF);

/// Everything else that is a letter. Checking the Latin, Greek and Cyrillic
/// ranges plus CJK covers what this app will ever be handed, and treating an
/// unknown script as strong-LTR is the same answer the fallback gives anyway.
bool _isLtr(int rune) =>
    (rune >= 0x0041 && rune <= 0x005A) ||
    (rune >= 0x0061 && rune <= 0x007A) ||
    (rune >= 0x00C0 && rune <= 0x058F) ||
    (rune >= 0x0900 && rune <= 0x1FFF) ||
    (rune >= 0x2C00 && rune <= 0xD7FF) ||
    (rune >= 0xF900 && rune <= 0xFB17) ||
    (rune >= 0x10000 && rune <= 0x107FF);

/// Lays [child] out in the direction of [text].
///
/// For a block that is all one person's writing — a question with its answers,
/// a quiz with its blurb — so that rows, padding and alignment inside it turn
/// round together instead of one label at a time.
class FzDirection extends StatelessWidget {
  const FzDirection({super.key, required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: directionOf(text), child: child);
  }
}

/// Lays a field out in the direction of what is currently typed into it.
///
/// It follows the text as it is written, so the first Arabic letter moves the
/// cursor to the right-hand side and the hint keeps the interface's direction
/// while the field is still empty.
class FzTypingDirection extends StatelessWidget {
  const FzTypingDirection({
    super.key,
    required this.controller,
    required this.child,
  });

  final TextEditingController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, child) =>
          Directionality(textDirection: directionOf(value.text), child: child!),
      child: child,
    );
  }
}
