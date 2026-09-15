import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Material button inside a keyed `FzButton` / `FzPill`.
ButtonStyleButton buttonByKey(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(
      find.descendant(
        of: find.byKey(key),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );

bool isEnabled(WidgetTester tester, Key key) =>
    buttonByKey(tester, key).onPressed != null;
