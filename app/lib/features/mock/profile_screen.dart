// MOCK: there are no accounts or game history yet (Phase 2). Every value on
// this screen is sample data from design/FazouraParty.dc.html.

import 'package:flutter/material.dart';

import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _stats = [
    (value: '34', label: 'PARTIES PLAYED', color: FzColors.ink),
    (value: '9', label: 'FIRST PLACES', color: FzColors.ac),
    (value: '11', label: 'BEST STREAK', color: FzColors.ok),
    (value: '72%', label: 'ANSWER ACCURACY', color: FzColors.ink),
  ];

  static const _history = [
    (
      place: '1ST',
      pack: 'General Knowledge',
      meta: 'Sat · 6 players',
      score: '41',
    ),
    (place: '4TH', pack: 'House Rules', meta: 'Thu · 5 players', score: '12'),
    (
      place: '2ND',
      pack: 'Guess the Decade',
      meta: 'Tue · 8 players',
      score: '33',
    ),
  ];

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
        footer: FzButton(
          label: 'Back home',
          kind: FzButtonKind.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const FzEyebrow(
              'Sample profile · accounts coming soon',
              color: FzColors.ac2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: FzColors.ac,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: FzColors.ac.withValues(alpha: .3),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Text(
                    'Y',
                    style: fz.h(
                      24,
                      weight: FontWeight.w900,
                      color: FzColors.bg,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You', style: fz.t(26)),
                    const SizedBox(height: 6),
                    Text(
                      '@you · sample data',
                      style: fz.m(11.5, color: FzColors.dim),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            for (var row = 0; row < _stats.length; row += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (final (i, stat)
                        in _stats.skip(row).take(2).indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: FzPanel(
                          radius: 15,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stat.value,
                                style: fz.m(30, color: stat.color),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                stat.label,
                                style: fz.m(
                                  9.5,
                                  color: FzColors.dim,
                                  tracking: .12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text('Recent parties', style: fz.h(17)),
            const SizedBox(height: 12),
            for (final (i, party) in _history.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: FzPanel(
                  radius: 13,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == 0 ? FzColors.ac : FzColors.panel,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          party.place,
                          style: fz.m(
                            11,
                            color: i == 0 ? FzColors.bg : FzColors.dim,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              party.pack,
                              style: fz.h(14, weight: FontWeight.w600),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              party.meta,
                              style: fz.m(10.5, color: FzColors.dim),
                            ),
                          ],
                        ),
                      ),
                      Text(party.score, style: fz.m(13, color: FzColors.dim)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
