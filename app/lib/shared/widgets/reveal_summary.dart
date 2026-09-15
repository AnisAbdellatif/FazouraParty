import 'package:flutter/material.dart';

import '../theme/fz_theme.dart';
import 'fz.dart';

/// The question that just ended and its accepted answers as green pills.
class RevealSummary extends StatelessWidget {
  const RevealSummary({
    super.key,
    required this.prompt,
    required this.acceptedAnswers,
  });

  final String prompt;
  final List<String> acceptedAnswers;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(prompt, style: fz.h(18, height: 1.25, tracking: -.02)),
        const SizedBox(height: 12),
        const FzEyebrow('Correct answer', color: FzColors.ok),
        const SizedBox(height: 8),
        Wrap(
          key: const Key('acceptedAnswers'),
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final answer in acceptedAnswers)
              FzEnter(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: FzColors.ok.withValues(alpha: .15),
                    border: Border.all(color: FzColors.ok),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(answer, style: fz.m(12.5, color: FzColors.ok)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
