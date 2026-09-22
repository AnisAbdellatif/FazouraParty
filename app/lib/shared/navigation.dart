import 'package:flutter/material.dart';

import 'widgets/fz_motion.dart';

/// Pops back to the home screen. Room screens leave the room in their
/// `PopScope` callback.
void goHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// The app's own page transition.
///
/// Material's default slides a page in from the right, which is a filing
/// gesture — the right one for a settings app and the wrong one here, where
/// every screen is the next beat of the same evening in the same room. This
/// lifts the new screen in over the old one instead: the design's `rise`,
/// scaled up to a whole page, with the screen underneath easing back rather
/// than sliding away.
///
/// Honours a device that asked for less motion by simply cutting.
class FzPageRoute<T> extends PageRouteBuilder<T> {
  FzPageRoute({required this.builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: _transition,
      );

  final WidgetBuilder builder;

  static Widget _transition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) return child;

    final entering = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // The page this one is covering. Easing it back a little is what makes the
    // new screen read as arriving on top rather than replacing.
    final leaving = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: leaving,
      builder: (context, child) => Transform.scale(
        scale: 1 - .03 * leaving.value,
        child: Opacity(opacity: 1 - .35 * leaving.value, child: child),
      ),
      child: FadeTransition(
        opacity: entering,
        child: AnimatedBuilder(
          animation: entering,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 26 * (1 - entering.value)),
            child: Transform.scale(
              scale: .97 + .03 * entering.value,
              child: child,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
