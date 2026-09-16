import 'package:flutter/material.dart';

import '../theme/fz_theme.dart';

/// Deep teal radial glow with the design's amber lattice woven over it.
class FzBackground extends StatelessWidget {
  const FzBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.3,
          colors: [FzColors.bgGlow, FzColors.bgDeep],
          stops: [0, 0.68],
        ),
      ),
      child: CustomPaint(
        painter: const _LatticePainter(),
        isComplex: true,
        willChange: false,
        child: child,
      ),
    );
  }
}

/// The design's `--lattice`: amber hairlines crossing at 45°, 26px apart.
class _LatticePainter extends CustomPainter {
  const _LatticePainter();

  static const _spacing = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FzColors.lattice
      ..strokeWidth = 1.5;

    for (var x = -size.height; x < size.width + size.height; x += _spacing) {
      canvas
        ..drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint)
        ..drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_LatticePainter oldDelegate) => false;
}

/// Phone-width column: scrolling [child] with an optional [footer] pinned to
/// the bottom. No background; use inside [FzPage] or a game shell.
class FzBody extends StatelessWidget {
  const FzBody({super.key, required this.child, this.footer});

  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: child,
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Full screen: background, safe area, optional [header] row, [FzBody].
class FzPage extends StatelessWidget {
  const FzPage({super.key, required this.child, this.header, this.footer});

  final Widget child;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return FzBackground(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null)
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                    child: header,
                  ),
                ),
              ),
            Expanded(
              child: FzBody(footer: footer, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

enum FzButtonKind { primary, pink, outline }

/// The design's big rounded buttons. Built on Material buttons so disabled
/// state and semantics come for free.
class FzButton extends StatelessWidget {
  const FzButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = FzButtonKind.primary,
    this.trailing,
    this.height = 60,
    this.fontSize = 17,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final FzButtonKind kind;

  /// Small DM Mono hint on the right (e.g. "host").
  final String? trailing;
  final double height;
  final double fontSize;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final enabled = onPressed != null;
    final filled = kind != FzButtonKind.outline;
    final fill = kind == FzButtonKind.pink ? FzColors.ac2 : FzColors.ac;
    final fg = !enabled
        ? FzColors.faint
        : filled
        ? FzColors.bg
        : FzColors.ink;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final minimumSize = Size(expand ? double.infinity : 0, height);
    const padding = EdgeInsets.symmetric(horizontal: 22);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: trailing == null
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: fz.h(fontSize, color: fg),
          ),
        ),
        if (trailing != null)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              trailing!,
              style: fz.m(
                13,
                color: filled ? fg.withValues(alpha: .6) : FzColors.dim,
              ),
            ),
          ),
      ],
    );

    final Widget button = filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: fill,
              foregroundColor: FzColors.bg,
              disabledBackgroundColor: FzColors.panel,
              disabledForegroundColor: FzColors.faint,
              minimumSize: minimumSize,
              padding: padding,
              shape: shape,
              elevation: 0,
            ),
            child: content,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: FzColors.ink,
              minimumSize: minimumSize,
              padding: padding,
              shape: shape,
              side: const BorderSide(color: FzColors.line, width: 1.5),
            ),
            child: content,
          );

    if (!enabled || kind != FzButtonKind.primary) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: fill.withValues(alpha: .45), spreadRadius: 1),
          BoxShadow(
            color: fill.withValues(alpha: .22),
            blurRadius: 34,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: button,
    );
  }
}

/// Small outlined pill ("Share", "Pause").
class FzPill extends StatelessWidget {
  const FzPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = FzColors.dim,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final fg = onPressed == null ? FzColors.faint : color;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: FzColors.faint,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: const StadiumBorder(),
        side: const BorderSide(color: FzColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(label, style: fz.m(11, color: fg, tracking: .04)),
        ],
      ),
    );
  }
}

/// Round 40px outlined icon button (back, leave, profile).
class FzCircleButton extends StatelessWidget {
  const FzCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        foregroundColor: FzColors.dim,
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        side: const BorderSide(color: FzColors.line),
        shape: const CircleBorder(),
      ),
    );
  }
}

/// Small DM Mono uppercase label with wide tracking.
class FzEyebrow extends StatelessWidget {
  const FzEyebrow(
    this.text, {
    super.key,
    this.color = FzColors.dim,
    this.size = 10,
  });

  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: FzTheme.of(context).m(size, color: color, tracking: .2),
    );
  }
}

/// Tiny uppercase tag (YOU, HOST, READY).
class FzTag extends StatelessWidget {
  const FzTag(this.text, {super.key, this.color = FzColors.faint});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: FzTheme.of(context).m(9, color: color, tracking: .14),
    );
  }
}

/// Translucent rounded card.
class FzPanel extends StatelessWidget {
  const FzPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = FzColors.panel,
    this.borderColor,
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 1.5),
      ),
      child: child,
    );
  }
}

/// Circle with the player's initial on their colour.
///
/// [hue] is the server-assigned `avatar_hue` (protocol v4), so every device
/// shows the same colour; the id-derived colour is only a fallback.
class FzAvatar extends StatelessWidget {
  const FzAvatar({
    super.key,
    required this.id,
    required this.name,
    this.hue,
    this.size = 46,
  });

  final String id;
  final String name;
  final int? hue;
  final double size;

  static Color colorForHue(int hue) =>
      HSLColor.fromAHSL(1, (hue % 360).toDouble(), .9, .72).toColor();

  static Color colorFor(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), .9, .72).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hue == null ? colorFor(id) : colorForHue(hue!),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: FzTheme.of(context).h(size * .37, color: FzColors.bg),
      ),
    );
  }
}

/// Endless soft opacity pulse ("locked in — waiting for the room").
class FzBlink extends StatefulWidget {
  const FzBlink({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1100),
  });

  final Widget child;
  final Duration period;

  @override
  State<FzBlink> createState() => _FzBlinkState();
}

class _FzBlinkState extends State<FzBlink> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 1,
        end: .35,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// One-shot entrance: fade + scale from .92 (the design's `pop`), or a 10px
/// rise when [rise] is true.
class FzEnter extends StatelessWidget {
  const FzEnter({super.key, required this.child, this.rise = false});

  final Widget child;
  final bool rise;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: rise
            ? Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child)
            : Transform.scale(scale: .92 + .08 * t, child: child),
      ),
      child: child,
    );
  }
}
