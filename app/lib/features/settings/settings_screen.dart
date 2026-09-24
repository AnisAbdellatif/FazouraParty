import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/config_providers.dart';
import '../../core/providers/update_providers.dart';
import '../../core/update/app_release.dart';
import '../../shared/community_rules.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _serverController;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: ref.read(serverBaseUrlProvider),
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _serverController.text.trim();
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !const ['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        setState(() => _error = 'Enter a valid http:// or https:// URL.');
        return;
      }
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref
          .read(serverBaseUrlProvider.notifier)
          .setDebugOverride(value.isEmpty ? null : value);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save this setting.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);

    final build = ref.watch(installedBuildProvider);
    final named = build.version.isNotEmpty;

    final sections = <Widget>[
      // Only a build that came through `scripts/ci.sh apk` knows its own
      // version; everything else would be naming a number it never got.
      if (named) ...[
        Text('This build', style: fz.h(17)),
        const SizedBox(height: 6),
        Text(
          'Version ${build.version} (build ${build.versionCode})',
          key: const Key('appVersionLabel'),
          style: fz.m(13, color: FzColors.dim, height: 1.4),
        ),
      ],
      if (build.supported) ...[
        if (named) const SizedBox(height: 14),
        const _UpdateSection(),
      ],
      if (named || build.supported) const SizedBox(height: 28),
      const _PrivacySection(),
      if (kDebugMode) ...[
        const SizedBox(height: 28),
        Text('Development server', style: fz.h(17)),
        const SizedBox(height: 6),
        Text(
          'Used for local development and Android emulator testing.',
          style: fz.m(11.5, color: FzColors.dim, height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('debugServerUrlField'),
          controller: _serverController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: fz.m(14),
          decoration: InputDecoration(
            hintText: 'http://10.0.2.2:4000',
            errorText: _error,
          ),
        ),
      ],
    ];

    return Scaffold(
      body: FzPage(
        header: Row(
          children: [
            IconButton(
              key: const Key('settingsBackButton'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              color: FzColors.ink,
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            Text('Settings', style: fz.t(25)),
          ],
        ),
        // Only the development server is a *setting*; everything else on this
        // screen is something to read or a one-off action, so a release build
        // has nothing to save and is not offered a button that does nothing.
        footer: kDebugMode
            ? FzButton(
                key: const Key('settingsSaveButton'),
                label: _saving ? 'Saving…' : 'Save settings',
                onPressed: _saving ? null : _save,
              )
            : null,
        // FzBody already scrolls; a ListView here would be a viewport inside
        // a viewport.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const SizedBox(height: 24), ...sections],
        ),
      ),
    );
  }
}

/// The privacy policy, served by the same server the app talks to
/// (`FazouraWeb.PageController`). Every build has one, which is why this
/// screen is never empty.
class _PrivacySection extends ConsumerWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fz = FzTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Privacy', style: fz.h(17)),
        const SizedBox(height: 6),
        Text(
          'No accounts, ads or tracking. Games are forgotten when the room '
          'closes; only quizzes you publish are kept.',
          style: fz.m(11.5, color: FzColors.dim, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FzPill(
              key: const Key('privacyPolicyButton'),
              label: 'Privacy policy',
              icon: Icons.open_in_new,
              onPressed: () => _open(context, ref),
            ),
            FzPill(
              key: const Key('communityRulesButton'),
              label: 'Community rules',
              icon: Icons.open_in_new,
              onPressed: () => openCommunityRules(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final base = Uri.parse(ref.read(serverBaseUrlProvider));
    final opened = await ref.read(urlOpenerProvider)(base.resolve('/privacy'));
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the privacy policy.')),
      );
    }
  }
}

/// Version state and the one action that changes it. Shown only where a build
/// can replace itself — an Android APK that came from a release.
class _UpdateSection extends ConsumerWidget {
  const _UpdateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fz = FzTheme.of(context);
    final async = ref.watch(availableUpdateProvider);
    final status = async.value;
    final release = status?.release;
    final failure = status?.failure;
    // The provider is `AsyncLoading` only for the very first read; after that a
    // check running announces itself inside the status.
    final checking = async.isLoading || (status?.checking ?? false);

    return FzPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(key: const Key('updateStatusLabel'), switch ((
            checking,
            failure,
            release,
          )) {
            (true, _, _) => 'Checking…',
            (_, final Object error, _) => describeError(error),
            (_, _, final AppRelease found) =>
              'Version ${found.version} is ready.',
            _ => 'You have the latest version.',
          }, style: fz.m(13, color: FzColors.dim, height: 1.4)),
          if (release?.notes case final notes?
              when notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              notes.trim(),
              style: fz.h(13, weight: FontWeight.w500, height: 1.45),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (release != null) ...[
                FzButton(
                  key: const Key('settingsDownloadButton'),
                  label: 'Download',
                  expand: false,
                  height: 40,
                  fontSize: 13,
                  onPressed: () => _download(context, ref),
                ),
                const SizedBox(width: 10),
              ],
              FzPill(
                key: const Key('checkForUpdatesButton'),
                label: 'Check again',
                icon: Icons.refresh,
                onPressed: checking
                    ? null
                    : () => ref.read(availableUpdateProvider.notifier).check(),
              ),
            ],
          ),
          if (release != null) ...[
            const SizedBox(height: 10),
            Text(
              // The browser downloads the APK; Android then asks whether to
              // trust it. Saying so up front keeps that prompt from looking
              // like something went wrong.
              'Opens in your browser. Android will ask you to allow the '
              'install once.${release.sizeLabel == null ? '' : ' ${release.sizeLabel} download.'}',
              style: fz.m(11, color: FzColors.faint, height: 1.4),
            ),
          ],
        ],
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
