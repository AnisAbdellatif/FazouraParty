import 'package:flutter/material.dart';

/// Colour tokens from `design/FazouraParty.dc.html`.
abstract final class FzColors {
  /// Amber, primary.
  static const ac = Color(0xFFFFB000);

  /// Pink, secondary and alerts.
  static const ac2 = Color(0xFFFF2D6F);
  static const ink = Color(0xFFFBF6EC);
  static const dim = Color(0x85FBF6EC);
  static const faint = Color(0x4DFBF6EC);
  static const bg = Color(0xFF0C0A07);
  static const bgDeep = Color(0xFF050403);
  static const bgGlow = Color(0xFF241905);
  static const panel = Color(0x0FFBF6EC);
  static const line = Color(0x24FBF6EC);
  static const ok = Color(0xFFB6F53C);
}

typedef FontApplier = TextStyle Function(TextStyle style);

/// Fonts for the design: Figtree for display and body text, DM Mono for
/// labels, codes and numbers.
///
/// The app wires in Google Fonts; widget tests fall back to [fallback], so
/// nothing is fetched over the network.
@immutable
class FzTheme extends ThemeExtension<FzTheme> {
  const FzTheme({required this.displayFont, required this.monoFont});

  final FontApplier displayFont;
  final FontApplier monoFont;

  static TextStyle _figtree(TextStyle style) =>
      style.copyWith(fontFamily: 'Figtree');

  static TextStyle _dmMono(TextStyle style) => style.copyWith(
    fontFamily: 'DM Mono',
    fontFamilyFallback: const ['monospace'],
  );

  static const fallback = FzTheme(displayFont: _figtree, monoFont: _dmMono);

  static FzTheme of(BuildContext context) =>
      Theme.of(context).extension<FzTheme>() ?? fallback;

  /// Figtree. [tracking] is letter-spacing in em, as in the design's CSS.
  TextStyle h(
    double size, {
    FontWeight weight = FontWeight.w800,
    Color color = FzColors.ink,
    double? height,
    double tracking = 0,
  }) => displayFont(
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size * tracking,
    ),
  );

  /// DM Mono. [tracking] is letter-spacing in em.
  TextStyle m(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = FzColors.ink,
    double? height,
    double tracking = 0,
  }) => monoFont(
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size * tracking,
    ),
  );

  @override
  FzTheme copyWith({FontApplier? displayFont, FontApplier? monoFont}) =>
      FzTheme(
        displayFont: displayFont ?? this.displayFont,
        monoFont: monoFont ?? this.monoFont,
      );

  @override
  FzTheme lerp(FzTheme? other, double t) => this;
}

/// The app's single dark theme.
ThemeData buildFzTheme({
  FzTheme fz = FzTheme.fallback,
  TextTheme Function(TextTheme base)? applyTextFont,
}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: 1.5),
  );
  bool selected(Set<WidgetState> states) =>
      states.contains(WidgetState.selected);

  final baseText = Typography.material2021().white.apply(
    bodyColor: FzColors.ink,
    displayColor: FzColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: FzColors.ac,
      onPrimary: FzColors.bg,
      secondary: FzColors.ac2,
      onSecondary: FzColors.bg,
      tertiary: FzColors.ok,
      onTertiary: FzColors.bg,
      error: FzColors.ac2,
      onError: FzColors.bg,
      surface: FzColors.bg,
      onSurface: FzColors.ink,
      onSurfaceVariant: FzColors.dim,
      outline: FzColors.line,
      outlineVariant: FzColors.line,
    ),
    scaffoldBackgroundColor: FzColors.bgDeep,
    textTheme: applyTextFont == null ? baseText : applyTextFont(baseText),
    extensions: [fz],
    dividerTheme: const DividerThemeData(color: FzColors.line, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: fz.m(15, color: FzColors.faint),
      labelStyle: fz.m(13, color: FzColors.dim),
      floatingLabelStyle: fz.m(13, color: FzColors.ac),
      errorStyle: fz.m(11, color: FzColors.ac2),
      counterStyle: fz.m(10, color: FzColors.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: border(FzColors.line),
      enabledBorder: border(FzColors.line),
      focusedBorder: border(FzColors.ac),
      disabledBorder: border(FzColors.panel),
      errorBorder: border(FzColors.ac2),
      focusedErrorBorder: border(FzColors.ac2),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: FzColors.ac,
      inactiveTrackColor: const Color(0x1AFBF6EC),
      thumbColor: FzColors.ac,
      overlayColor: FzColors.ac.withValues(alpha: .16),
      activeTickMarkColor: FzColors.bg.withValues(alpha: .35),
      inactiveTickMarkColor: FzColors.line,
      disabledActiveTrackColor: FzColors.faint,
      disabledThumbColor: FzColors.faint,
      valueIndicatorColor: FzColors.ac,
      valueIndicatorTextStyle: fz.m(14, color: FzColors.bg),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => selected(states) ? FzColors.bg : FzColors.dim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => selected(states) ? FzColors.ac : FzColors.panel,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => selected(states) ? FzColors.ac : FzColors.line,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1A14),
      contentTextStyle: fz.m(13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: FzColors.ac,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF15120D),
      showDragHandle: true,
      dragHandleColor: FzColors.line,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: FzColors.ac,
      selectionColor: Color(0x55FFB000),
      selectionHandleColor: FzColors.ac,
    ),
  );
}
