import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/fz_theme.dart';

/// A question's photo from a [url] (in a room) or [bytes] (on the device),
/// rounded and capped in height (text+photo questions, QUIZ_FORMAT.md §2.2).
class QuestionPhoto extends StatelessWidget {
  const QuestionPhoto({
    super.key,
    this.url,
    this.bytes,
    this.maxHeight = 240,
    this.semanticLabel,
  }) : assert(url != null || bytes != null);

  final String? url;
  final Uint8List? bytes;
  final double maxHeight;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    // Everything drawn here sits on the light mat, not on the page, so it takes
    // the page's own dark teal rather than the usual pale ink — which would be
    // invisible against it.
    Widget error(BuildContext context, Object error, StackTrace? stack) =>
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Photo unavailable',
            style: fz.m(11, color: FzColors.bg.withValues(alpha: .55)),
          ),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, minHeight: 80),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Decode to the size it is drawn at, not the size it was saved at.
            // `preparePhoto` caps a photo at 1280px, and the mat is a few
            // hundred wide: without this the full-size bitmap is decoded and
            // held in the image cache, costing several times the memory and
            // the decode time for pixels that are thrown away on the way to
            // the screen. Null when the width is unbounded, which leaves
            // Flutter's own behaviour.
            final width = constraints.maxWidth.isFinite
                ? (constraints.maxWidth *
                          MediaQuery.devicePixelRatioOf(context))
                      .round()
                : null;

            return Container(
              key: const Key('photoMat'),
              width: double.infinity,
              color: FzColors.photoMat,
              alignment: Alignment.center,
              child: bytes != null
                  ? Image.memory(
                      bytes!,
                      fit: BoxFit.contain,
                      cacheWidth: width,
                      semanticLabel: semanticLabel,
                      errorBuilder: error,
                    )
                  : Image.network(
                      url!,
                      fit: BoxFit.contain,
                      cacheWidth: width,
                      semanticLabel: semanticLabel,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const Padding(
                              padding: EdgeInsets.all(28),
                              child: CircularProgressIndicator(
                                color: FzColors.bg,
                              ),
                            ),
                      errorBuilder: error,
                    ),
            );
          },
        ),
      ),
    );
  }
}
