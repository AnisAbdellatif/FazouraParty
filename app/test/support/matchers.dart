import 'package:fazoura_party/core/game/game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails unless the call throws the protocol error code `code` (PROTOCOL.md §4).
///
/// Four test files had written this out, so a change to how a rule error carries its
/// code meant finding all four — and the one that spelled it `_throwsCode` was the one
/// a search would miss.
Matcher throwsCode(String code) =>
    throwsA(isA<GameRuleError>().having((error) => error.code, 'code', code));
