// MOCK: only "General Knowledge" exists on the server (server/priv/packs).
// The other cards are placeholders from design/FazouraParty.dc.html and cannot
// be picked until pack storage lands (Phase 2).

import 'package:flutter/material.dart';

import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

class PackOption {
  const PackOption({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    required this.hue,
    this.available = false,
  });

  final String id;
  final String name;
  final String tag;
  final String description;
  final double hue;
  final bool available;
}

const packOptions = [
  PackOption(
    id: 'general-knowledge',
    name: 'General Knowledge',
    tag: '10 QUESTIONS',
    description: 'Capitals, planets, painters: the classics.',
    hue: 25,
    available: true,
  ),
  PackOption(
    id: 'house-rules',
    name: 'House Rules',
    tag: 'SOON',
    description: 'Written by your group. Inside jokes count.',
    hue: 300,
  ),
  PackOption(
    id: 'guess-the-decade',
    name: 'Guess the Decade',
    tag: 'SOON',
    description: 'One song, four decades, ten seconds.',
    hue: 150,
  ),
];

/// Returns the picked pack id, or null if the host backs out.
Future<String?> showPackPicker(BuildContext context) {
  return Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const PackPickerScreen()));
}

class PackPickerScreen extends StatelessWidget {
  const PackPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Scaffold(
      body: FzPage(
        header: Row(
          children: [
            FzCircleButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(
              "Pick tonight's\npack",
              style: fz.h(
                32,
                weight: FontWeight.w900,
                height: 1.05,
                tracking: -.03,
              ),
            ),
            const SizedBox(height: 22),
            for (final pack in packOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PackCard(pack: pack),
              ),
          ],
        ),
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.pack});

  final PackOption pack;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Opacity(
      opacity: pack.available ? 1 : .45,
      child: Material(
        color: FzColors.panel,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: pack.available ? FzColors.ac : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          key: ValueKey('pack-${pack.id}'),
          onTap: pack.available
              ? () => Navigator.of(context).pop(pack.id)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 74,
                child: CustomPaint(
                  painter: _StripePainter(pack.hue),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD9FBF6EC),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          pack.tag,
                          style: fz.m(9, color: FzColors.bg, tracking: .16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pack.name, style: fz.h(19)),
                    const SizedBox(height: 6),
                    Text(
                      pack.description,
                      style: fz.m(11.5, color: FzColors.dim, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 45° two-tone stripes, the design's `repeating-linear-gradient` header.
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
