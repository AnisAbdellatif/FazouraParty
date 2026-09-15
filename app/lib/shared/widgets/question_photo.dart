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
    Widget error(BuildContext context, Object error, StackTrace? stack) =>
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Photo unavailable',
            style: fz.m(11, color: FzColors.dim),
          ),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, minHeight: 80),
        child: Container(
          width: double.infinity,
          color: FzColors.panel,
          alignment: Alignment.center,
          child: bytes != null
              ? Image.memory(
                  bytes!,
                  fit: BoxFit.contain,
                  semanticLabel: semanticLabel,
                  errorBuilder: error,
                )
              : Image.network(
                  url!,
                  fit: BoxFit.contain,
                  semanticLabel: semanticLabel,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(),
                        ),
                  errorBuilder: error,
                ),
        ),
      ),
    );
  }
}
