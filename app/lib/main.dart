import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/home/home_screen.dart';
import 'shared/theme/fz_theme.dart';

void main() {
  runApp(const ProviderScope(child: FazouraPartyApp()));
}

class FazouraPartyApp extends StatelessWidget {
  const FazouraPartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final fonts = FzTheme(
      displayFont: (style) => GoogleFonts.figtree(textStyle: style),
      monoFont: (style) => GoogleFonts.dmMono(textStyle: style),
      titleFont: (style) => GoogleFonts.reemKufi(textStyle: style),
    );
    return MaterialApp(
      title: 'Fazoura Party',
      debugShowCheckedModeBanner: false,
      theme: buildFzTheme(
        fz: fonts,
        applyTextFont: GoogleFonts.figtreeTextTheme,
      ),
      home: const HomeScreen(),
    );
  }
}
