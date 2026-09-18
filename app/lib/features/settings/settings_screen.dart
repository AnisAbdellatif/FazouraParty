import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/config_providers.dart';
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
        footer: FzButton(
          key: const Key('settingsSaveButton'),
          label: _saving ? 'Saving…' : 'Save settings',
          onPressed: _saving ? null : _save,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            if (kDebugMode) ...[
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
            ] else
              Text(
                'No configurable settings are available in this build.',
                style: fz.m(13, color: FzColors.dim),
              ),
          ],
        ),
      ),
    );
  }
}
