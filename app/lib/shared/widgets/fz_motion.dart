import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Whether this device has asked for less motion.
///
/// Every animation in `Fz*` checks it and renders the settled state instead.
/// A party game leans on movement, which is exactly why it has to be possible
/// to turn off: the setting is usually on because motion makes somebody ill.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// The design's `shake`: a short sideways wobble, run once whenever [trigger]
/// changes to a new non-null value.
///
/// Used for an answer the host would not take — the field says no by moving,
/// which is read before any error text is (design `@keyframes shake`).
class FzShake extends StatefulWidget {
  const FzShake({
    super.key,
    required this.child,
    required this.trigger,
    this.distance = 5,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;

  /// Shakes when this changes. Null never shakes, so a widget can start life
  /// settled.
  final Object? trigger;
  final double distance;
  final Duration duration;

  @override
  State<FzShake> createState() => _FzShakeState();
}

class _FzShakeState extends State<FzShake> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didUpdateWidget(FzShake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != null &&
        widget.trigger != old.trigger &&
        !reduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // Two full cycles that die away, rather than the design's single
      // there-and-back: on a phone one pass reads as a layout glitch. The
      // decay is what keeps it from ending anywhere but centred.
      builder: (context, child) {
        final t = _controller.value;
        return Transform.translate(
          offset: Offset(
            widget.distance * (1 - t) * math.sin(t * math.pi * 4),
            0,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A quick overshoot, run once whenever [trigger] changes.
///
/// The design's `pop` is an entrance; this is the same gesture for something
/// already on screen that just became true — a dot turning green, a second
/// falling off the clock.
class FzPop extends StatefulWidget {
  const FzPop({
    super.key,
    required this.child,
    required this.trigger,
    this.scale = 1.35,
    this.duration = const Duration(milliseconds: 260),
  });

  final Widget child;
  final Object? trigger;
  final double scale;
  final Duration duration;

  @override
  State<FzPop> createState() => _FzPopState();
}

class _FzPopState extends State<FzPop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didUpdateWidget(FzPop old) {
    super.didUpdateWidget(old);
    // Null is the resting state, not an event: a dot going back to grey for
    // the next question should not pop on its way out.
    if (widget.trigger != null &&
        widget.trigger != old.trigger &&
        !reduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // Out and back within the one controller, so nothing is left scaled up
      // if the widget is disposed mid-pop.
      builder: (context, child) {
        final t = _controller.value;
        final swell = t < .5 ? t * 2 : (1 - t) * 2;
        return Transform.scale(
          scale: 1 + (widget.scale - 1) * Curves.easeOut.transform(swell),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Eases between colours when [color] changes, instead of snapping — a clock
/// warming from amber to red. The first build shows [color] as it is.
class FzTint extends StatelessWidget {
  const FzTint({
    super.key,
    required this.color,
    required this.builder,
    this.duration = const Duration(milliseconds: 450),
  });

  final Color color;
  final Widget Function(BuildContext context, Color color) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: reduceMotion(context) ? Duration.zero : duration,
      curve: Curves.easeOut,
      builder: (context, value, _) => builder(context, value ?? color),
    );
  }
}

/// A glow that flares around [child] and fades, once whenever [trigger]
/// changes to a new non-null value — a heartbeat for the last seconds on the
/// clock. [child] should fill a rounded box of [radius]; the glow follows it.
class FzFlash extends StatefulWidget {
  const FzFlash({
    super.key,
    required this.child,
    required this.trigger,
    required this.color,
    this.radius = 999,
    this.duration = const Duration(milliseconds: 650),
  });

  final Widget child;
  final Object? trigger;
  final Color color;
  final double radius;
  final Duration duration;

  @override
  State<FzFlash> createState() => _FzFlashState();
}

class _FzFlashState extends State<FzFlash> with SingleTickerProviderStateMixin {
  // Starts spent, so nothing glows until the first trigger.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  @override
  void didUpdateWidget(FzFlash old) {
    super.didUpdateWidget(old);
    if (widget.trigger != null &&
        widget.trigger != old.trigger &&
        !reduceMotion(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = 1 - Curves.easeOut.transform(_controller.value);
        if (glow == 0) return child!;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: .85 * glow),
                blurRadius: 22 * glow,
                spreadRadius: 4 * glow,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A number that runs up (or down) to its new value instead of snapping.
///
/// [from] and [to] are given rather than inferred from rebuilds, because the
/// interesting case — a score after a question — appears on a screen that was
/// just built, and a widget seeing its value for the first time has nothing to
/// count from. The caller knows: it is the score minus what the question paid.
class FzCountUp extends StatelessWidget {
  const FzCountUp({
    super.key,
    required this.from,
    required this.to,
    required this.style,
    this.textAlign,
    this.signed = false,
    this.duration = const Duration(milliseconds: 750),
  });

  final int from;
  final int to;
  final TextStyle style;
  final TextAlign? textAlign;

  /// Writes a leading `+` for a positive number, as a score change does.
  final bool signed;
  final Duration duration;

  String _label(int value) =>
      signed && value > 0 ? '+$value' : value.toString();

  @override
  Widget build(BuildContext context) {
    if (from == to || reduceMotion(context)) {
      return Text(_label(to), style: style, textAlign: textAlign);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from.toDouble(), end: to.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) =>
          Text(_label(value.round()), style: style, textAlign: textAlign),
    );
  }
}

/// Slides children to their new places when the order changes.
///
/// Flutter animates a list's contents but never its order: a `Column` lays the
/// rows out where they now belong and they jump. Overtaking somebody is the
/// most satisfying thing that happens in a trivia game, and a jump throws it
/// away.
///
/// This measures where each keyed child sat on the last frame and where it
/// sits now, then draws it at the old offset and slides it to the new one — the
/// "FLIP" technique. Every child must carry a stable [Key], or there is nothing
/// to recognise it by between frames.
class FzReorder extends StatefulWidget {
  const FzReorder({
    super.key,
    required this.children,
    this.duration = const Duration(milliseconds: 520),
  });

  final List<Widget> children;
  final Duration duration;

  @override
  State<FzReorder> createState() => _FzReorderState();
}

class _FzReorderState extends State<FzReorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  final _itemKeys = <Key, GlobalKey>{};

  /// Where each child was, relative to this widget, after the last frame.
  final _lastTop = <Key, double>{};

  /// How far each child has to travel this time, from its old place to its new
  /// one. Drawn as `shift * controller.value`, so 1 is "still where it was".
  var _shift = <Key, double>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Key _keyOf(Widget child) =>
      child.key ??
      (throw ArgumentError('FzReorder children must each carry a Key'));

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_measure);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in widget.children)
            Builder(
              builder: (context) {
                final key = _keyOf(child);
                final shift = _shift[key] ?? 0;
                return Transform.translate(
                  offset: Offset(0, shift * _controller.value),
                  child: KeyedSubtree(
                    key: _itemKeys.putIfAbsent(key, GlobalKey.new),
                    child: child,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _measure(Duration _) {
    if (!mounted) return;
    final self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize) return;

    final tops = <Key, double>{};
    for (final child in widget.children) {
      final key = _keyOf(child);
      final box = _itemKeys[key]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      // Undo the displacement currently being drawn, so what is recorded is
      // where the row belongs rather than where it happens to be mid-slide.
      tops[key] =
          box.localToGlobal(Offset.zero, ancestor: self).dy -
          (_shift[key] ?? 0) * _controller.value;
    }

    final moved = <Key, double>{};
    for (final entry in tops.entries) {
      final was = _lastTop[entry.key];
      // A row that was not there a frame ago has not moved; it arrived, and
      // its own entrance animation is what should play.
      if (was != null && (was - entry.value).abs() > 0.5) {
        moved[entry.key] = was - entry.value;
      }
    }

    _lastTop
      ..clear()
      ..addAll(tops);

    if (moved.isEmpty || reduceMotion(context)) return;
    setState(() => _shift = moved);
    // Backwards on purpose: 1 is "still in the old place", 0 is "arrived", so
    // the row is drawn where it was and slides to where it now belongs.
    _controller.reverse(from: 1);
  }
}
