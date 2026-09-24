import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers/config_providers.dart';
import '../core/providers/update_providers.dart';
import 'theme/fz_theme.dart';
import 'widgets/fz.dart';

/// Which version of the rules this device agreed to. Bump it when the rules
/// change in a way people should see again; the page itself is
/// `server/priv/pages/rules.html`, at `/rules`.
const communityRulesVersion = 1;

const _acceptedKey = 'fazoura.community_rules_accepted';

/// True once this device has agreed to the community rules, asking first if it
/// has not.
///
/// Google Play requires users to accept the rules before they create content
/// others see (User Generated Content policy). Here that is publishing a quiz,
/// and playing in a public room — where the name you type and the answers you
/// give are read by strangers. Asked once per [communityRulesVersion], never
/// for a room joined by code among friends.
Future<bool> ensureRulesAccepted(BuildContext context, WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getInt(_acceptedKey) == communityRulesVersion) return true;
  if (!context.mounted) return false;

  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _RulesSheet(),
  );
  if (agreed != true) return false;
  await prefs.setInt(_acceptedKey, communityRulesVersion);
  return true;
}

/// Opens the full rules page on the server the app talks to.
Future<void> openCommunityRules(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final base = Uri.parse(ref.read(serverBaseUrlProvider));
  final opened = await ref.read(urlOpenerProvider)(base.resolve('/rules'));
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open the community rules.')),
    );
  }
}

class _RulesSheet extends ConsumerWidget {
  const _RulesSheet();

  static const _rules = [
    'For ages 13 and over.',
    'No hate, harassment, slurs or bullying.',
    'Nothing sexual, violent, dangerous or illegal.',
    "Nobody's personal details — yours included. Play under a nickname.",
    'No spam, and nothing meant to wreck the game.',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fz = FzTheme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FzEyebrow('Before you go on'),
            const SizedBox(height: 8),
            Text('Community rules', style: fz.t(26)),
            const SizedBox(height: 10),
            Text(
              'What you publish, the name you play under and the answers you '
              'give can be seen by people you don’t know.',
              style: fz.m(12, color: FzColors.dim, height: 1.5),
            ),
            const SizedBox(height: 14),
            for (final rule in _rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: fz.h(14, color: FzColors.ac)),
                    Expanded(child: Text(rule, style: fz.h(14, height: 1.35))),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Hosts can remove players, anyone can report a quiz or a player, '
              'and we can keep a connection out of public rooms for a while.',
              style: fz.m(11.5, color: FzColors.dim, height: 1.5),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('readFullRulesButton'),
                onPressed: () => openCommunityRules(context, ref),
                child: Text(
                  'Read the full rules',
                  style: fz.m(12, color: FzColors.ac),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FzButton(
              key: const Key('acceptRulesButton'),
              label: 'I agree',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Not now', style: fz.m(12, color: FzColors.dim)),
            ),
          ],
        ),
      ),
    );
  }
}
