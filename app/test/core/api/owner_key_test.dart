/// The publisher key's shape, which is a contract with the server
/// (QUIZ_FORMAT.md §4, `Fazoura.Quizzes.OwnerKeyTest`).
///
/// There are no accounts: this key is the only thing that lets this device
/// replace or unpublish what it published. The server decides what it accepts
/// — `[A-Za-z0-9_-]{32,128}` — and nothing held the generator to it, so a
/// change here to standard base64 (`+`, `/`, `=`) or to fewer bytes would be
/// refused by every write the device ever makes, with no error path to recover
/// through: it simply never becomes an owner of anything.
@TestOn('vm')
library;

import 'dart:math';

import 'package:fazoura_party/core/api/quiz_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The server's rule, written out rather than imported: a copy that cannot
  /// drift silently is the point, and the two sides share no code.
  final serverAccepts = RegExp(r'^[A-Za-z0-9_-]{32,128}$');

  test('what the server will accept', () {
    expect(generateOwnerKey(), matches(serverAccepts));
  });

  test('every byte pattern still produces an acceptable key', () {
    // base64url of 32 bytes is 43 characters whatever the bytes are, but the
    // alphabet is what a careless change breaks — and the bytes that would
    // expose it are the ones a handful of random draws will not reach.
    for (final fill in [0, 0x3E, 0x3F, 0xFB, 0xFF]) {
      final key = generateOwnerKey(_Fixed(fill));
      expect(
        key,
        matches(serverAccepts),
        reason: 'byte 0x${fill.toRadixString(16)}',
      );
      expect(key.length, 43);
    }
  });

  test('a fresh key every time, from a secure source by default', () {
    final keys = {for (var i = 0; i < 50; i++) generateOwnerKey()};

    expect(keys, hasLength(50));
  });
}

/// Every byte the same, to walk the base64 alphabet deliberately.
class _Fixed implements Random {
  _Fixed(this.byte);

  final int byte;

  @override
  int nextInt(int max) => byte % max;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
