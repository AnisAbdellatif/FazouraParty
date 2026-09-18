import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/home_screen.dart';
import 'shared/theme/fz_theme.dart';

void main() {
  runApp(const ProviderScope(child: FazouraPartyApp()));
}

class FazouraPartyApp extends StatelessWidget {
  const FazouraPartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fazoura Party',
      debugShowCheckedModeBanner: false,
      // The fonts are bundled (pubspec `fonts:`), so FzTheme's own family names
      // are the real thing rather than a fallback: nothing is fetched at
      // runtime, and the design survives a party with no internet.
      theme: buildFzTheme(
        fz: FzTheme.fallback,
        applyTextFont: (base) => base.apply(fontFamily: 'Figtree'),
      ),
      home: const HomeScreen(),
    );
  }
}
