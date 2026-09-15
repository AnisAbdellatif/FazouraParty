import 'package:flutter/material.dart';

import '../theme/fz_theme.dart';

/// Hue per quiz category, used for card stripes.
const categoryHues = <String, double>{
  'general': 25,
  'science': 200,
  'history': 35,
  'geography': 140,
  'movies': 300,
  'music': 265,
  'sports': 110,
  'food': 12,
  'language': 180,
  'pop_culture': 330,
  'other': 60,
};

/// 74px two-tone 45° stripe band with a small tag in the corner — the design's
/// `repeating-linear-gradient` card header.
class StripeHeader extends StatelessWidget {
  const StripeHeader({super.key, required this.hue, required this.tag});

  final double hue;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: CustomPaint(
        painter: _StripePainter(hue),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xD9FBF6EC),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tag.toUpperCase(),
                style: FzTheme.of(context)
                    .m(9, color: FzColors.bg, tracking: .16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = HSLColor.fromAHSL(1, hue, .9, .72).toColor(),
    );
    final stripe = Paint()
      ..color = HSLColor.fromAHSL(1, hue, .75, .6).toColor()
      ..strokeWidth = 6;
    canvas
      ..save()
      ..clipRect(rect);
    for (var x = -size.height; x < size.width + size.height; x += 12) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => oldDelegate.hue != hue;
}
