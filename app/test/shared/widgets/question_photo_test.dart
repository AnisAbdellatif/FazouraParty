import 'dart:typed_data';

import 'package:fazoura_party/shared/theme/fz_theme.dart';
import 'package:fazoura_party/shared/widgets/question_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Not an image, so `Image.memory` takes the error path — which is the case
/// where the mat is all there is to look at.
final _notAnImage = Uint8List.fromList(List.filled(32, 7));

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

Color _matColour(WidgetTester tester) =>
    tester.widget<Container>(find.byKey(const Key('photoMat'))).color!;

void main() {
  testWidgets('the mat behind a photo is light and close to opaque', (
    tester,
  ) async {
    await _pump(tester, QuestionPhoto(bytes: _notAnImage));

    final mat = _matColour(tester);
    expect(mat, FzColors.photoMat);
    // Photos are letterboxed onto this, so a light ground is the point: a
    // diagram or a product shot must not read as a hole in the page.
    expect(mat.a, greaterThan(0.9));
    expect(mat.computeLuminance(), greaterThan(0.8));
  });

  testWidgets('the fallback text stays readable against it', (tester) async {
    await _pump(tester, QuestionPhoto(bytes: _notAnImage));

    expect(find.text('Photo unavailable'), findsOneWidget);
    final style = tester.widget<Text>(find.text('Photo unavailable')).style!;

    // The usual pale ink would vanish on a near-white mat. This is the one
    // place in the app that draws on a light ground, so it is also the one
    // place that has to go dark.
    expect(style.color!.computeLuminance(), lessThan(0.3));
  });
}
