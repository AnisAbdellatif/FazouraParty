import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/update_providers.dart';
import '../theme/fz_theme.dart';
import 'fz.dart';

/// Offers the newer APK on the home screen, once, until it is waved away.
///
/// Shows nothing at all when there is nothing to offer — which is every web
/// build, every development build, and every Android build that is already
/// current (`core/update/app_version.dart`). It is a `SizedBox.shrink` in
/// those cases rather than a conditional at the call site, so the home screen
/// does not have to know any of that.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fz = FzTheme.of(context);
    // An automatic check that failed or is still running is not worth a
    // placeholder: there is nothing to say yet.
    final status = ref.watch(availableUpdateProvider).value;
    final release = status?.release;
    if (release == null || status!.dismissed) return const SizedBox.shrink();

    final size = release.sizeLabel;

    // Sits above the home screen's buttons, spaced like one of them.
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: FzPanel(
        borderColor: FzColors.ac,
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FzEyebrow('New version', color: FzColors.ac),
                  const SizedBox(height: 4),
                  Text(
                    size == null
                        ? release.version
                        : '${release.version} · $size',
                    style: fz.m(12.5, color: FzColors.dim),
                  ),
                ],
              ),
            ),
            FzButton(
              key: const Key('updateDownloadButton'),
              label: 'Get it',
              expand: false,
              height: 40,
              fontSize: 13,
              onPressed: () => _download(context, ref),
            ),
            IconButton(
              key: const Key('updateDismissButton'),
              tooltip: 'Not now',
              onPressed: () =>
                  ref.read(availableUpdateProvider.notifier).dismiss(),
              icon: const Icon(Icons.close, size: 18),
              color: FzColors.dim,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(availableUpdateProvider.notifier).download();
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the download.')),
      );
    }
  }
}
