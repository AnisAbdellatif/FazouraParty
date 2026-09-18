/// Automatic answer matching for a LAN-hosted room (PROTOCOL.md §8).
///
/// Dart port of `server/lib/fazoura/game/answer.ex`. Normalized exact match
/// only — no fuzzy matching; the host override is the second pass. Both hosts
/// are held to `protocol/fixtures/normalize.json`.
library;

/// NFD, strip combining marks, lower-case, trim, collapse internal whitespace.
///
/// Punctuation is deliberately **not** stripped (§8), so "USA" does not match
/// "U.S.A.".
String normalizeAnswer(String text) {
  final decomposed = _toNfd(text);
  final withoutMarks = decomposed.replaceAll(_combiningMarks, '');
  return withoutMarks.toLowerCase().trim().replaceAll(_whitespaceRun, ' ');
}

bool answerIsCorrect(String answer, List<String> acceptedAnswers) {
  final normalized = normalizeAnswer(answer);
  return acceptedAnswers.any((a) => normalizeAnswer(a) == normalized);
}

/// Unicode combining marks (category `Mn`), the ranges that matter for the
/// Latin, Greek and Cyrillic text a quiz answer realistically contains.
///
/// Dart's regex has no `\p{Mn}` (unlike Elixir's), so the ranges are spelled
/// out: U+0300–U+036F combining diacriticals, U+1AB0–U+1AFF extended,
/// U+1DC0–U+1DFF supplement, U+20D0–U+20F0 for symbols, U+FE20–U+FE2F halves.
final _combiningMarks = RegExp(
  r'[\u0300-\u036F\u1AB0-\u1AFF\u1DC0-\u1DFF\u20D0-\u20F0\uFE20-\uFE2F]',
);

final _whitespaceRun = RegExp(r'\s+');

/// Canonical decomposition (NFD).
///
/// Dart has no Unicode normalization in its core libraries, so this decomposes
/// the precomposed Latin letters a quiz answer is likely to contain. Anything
/// not in the table is passed through unchanged, which is safe: an unlisted
/// character simply compares as itself on both sides of the match.
String _toNfd(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final decomposition = _decompositions[rune];
    if (decomposition == null) {
      buffer.writeCharCode(rune);
    } else {
      buffer.write(decomposition);
    }
  }
  return buffer.toString();
}

/// Precomposed character → base letter + combining mark(s).
///
/// Latin-1 Supplement and Latin Extended-A, which covers every accented letter
/// in the languages the quiz format supports. The combining mark is stripped
/// immediately afterwards, so only the base letter survives.
const _decompositions = <int, String>{
  // Latin-1 Supplement, upper case.
  0xC0: 'A\u0300', 0xC1: 'A\u0301', 0xC2: 'A\u0302', 0xC3: 'A\u0303',
  0xC4: 'A\u0308', 0xC5: 'A\u030A', 0xC7: 'C\u0327', 0xC8: 'E\u0300',
  0xC9: 'E\u0301', 0xCA: 'E\u0302', 0xCB: 'E\u0308', 0xCC: 'I\u0300',
  0xCD: 'I\u0301', 0xCE: 'I\u0302', 0xCF: 'I\u0308', 0xD1: 'N\u0303',
  0xD2: 'O\u0300', 0xD3: 'O\u0301', 0xD4: 'O\u0302', 0xD5: 'O\u0303',
  0xD6: 'O\u0308', 0xD9: 'U\u0300', 0xDA: 'U\u0301', 0xDB: 'U\u0302',
  0xDC: 'U\u0308', 0xDD: 'Y\u0301',
  // Latin-1 Supplement, lower case.
  0xE0: 'a\u0300', 0xE1: 'a\u0301', 0xE2: 'a\u0302', 0xE3: 'a\u0303',
  0xE4: 'a\u0308', 0xE5: 'a\u030A', 0xE7: 'c\u0327', 0xE8: 'e\u0300',
  0xE9: 'e\u0301', 0xEA: 'e\u0302', 0xEB: 'e\u0308', 0xEC: 'i\u0300',
  0xED: 'i\u0301', 0xEE: 'i\u0302', 0xEF: 'i\u0308', 0xF1: 'n\u0303',
  0xF2: 'o\u0300', 0xF3: 'o\u0301', 0xF4: 'o\u0302', 0xF5: 'o\u0303',
  0xF6: 'o\u0308', 0xF9: 'u\u0300', 0xFA: 'u\u0301', 0xFB: 'u\u0302',
  0xFC: 'u\u0308', 0xFD: 'y\u0301', 0xFF: 'y\u0308',
  // Latin Extended-A.
  0x100: 'A\u0304', 0x101: 'a\u0304', 0x102: 'A\u0306', 0x103: 'a\u0306',
  0x104: 'A\u0328', 0x105: 'a\u0328', 0x106: 'C\u0301', 0x107: 'c\u0301',
  0x108: 'C\u0302', 0x109: 'c\u0302', 0x10A: 'C\u0307', 0x10B: 'c\u0307',
  0x10C: 'C\u030C', 0x10D: 'c\u030C', 0x10E: 'D\u030C', 0x10F: 'd\u030C',
  0x112: 'E\u0304', 0x113: 'e\u0304', 0x114: 'E\u0306', 0x115: 'e\u0306',
  0x116: 'E\u0307', 0x117: 'e\u0307', 0x118: 'E\u0328', 0x119: 'e\u0328',
  0x11A: 'E\u030C', 0x11B: 'e\u030C', 0x11C: 'G\u0302', 0x11D: 'g\u0302',
  0x11E: 'G\u0306', 0x11F: 'g\u0306', 0x120: 'G\u0307', 0x121: 'g\u0307',
  0x122: 'G\u0327', 0x123: 'g\u0327', 0x124: 'H\u0302', 0x125: 'h\u0302',
  0x128: 'I\u0303', 0x129: 'i\u0303', 0x12A: 'I\u0304', 0x12B: 'i\u0304',
  0x12C: 'I\u0306', 0x12D: 'i\u0306', 0x12E: 'I\u0328', 0x12F: 'i\u0328',
  0x130: 'I\u0307', 0x134: 'J\u0302', 0x135: 'j\u0302', 0x136: 'K\u0327',
  0x137: 'k\u0327', 0x139: 'L\u0301', 0x13A: 'l\u0301', 0x13B: 'L\u0327',
  0x13C: 'l\u0327', 0x13D: 'L\u030C', 0x13E: 'l\u030C', 0x143: 'N\u0301',
  0x144: 'n\u0301', 0x145: 'N\u0327', 0x146: 'n\u0327', 0x147: 'N\u030C',
  0x148: 'n\u030C', 0x14C: 'O\u0304', 0x14D: 'o\u0304', 0x14E: 'O\u0306',
  0x14F: 'o\u0306', 0x150: 'O\u030B', 0x151: 'o\u030B', 0x154: 'R\u0301',
  0x155: 'r\u0301', 0x156: 'R\u0327', 0x157: 'r\u0327', 0x158: 'R\u030C',
  0x159: 'r\u030C', 0x15A: 'S\u0301', 0x15B: 's\u0301', 0x15C: 'S\u0302',
  0x15D: 's\u0302', 0x15E: 'S\u0327', 0x15F: 's\u0327', 0x160: 'S\u030C',
  0x161: 's\u030C', 0x162: 'T\u0327', 0x163: 't\u0327', 0x164: 'T\u030C',
  0x165: 't\u030C', 0x168: 'U\u0303', 0x169: 'u\u0303', 0x16A: 'U\u0304',
  0x16B: 'u\u0304', 0x16C: 'U\u0306', 0x16D: 'u\u0306', 0x16E: 'U\u030A',
  0x16F: 'u\u030A', 0x170: 'U\u030B', 0x171: 'u\u030B', 0x172: 'U\u0328',
  0x173: 'u\u0328', 0x174: 'W\u0302', 0x175: 'w\u0302', 0x176: 'Y\u0302',
  0x177: 'y\u0302', 0x178: 'Y\u0308', 0x179: 'Z\u0301', 0x17A: 'z\u0301',
  0x17B: 'Z\u0307', 0x17C: 'z\u0307', 0x17D: 'Z\u030C', 0x17E: 'z\u030C',
};
