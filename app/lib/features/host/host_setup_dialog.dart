import 'package:flutter/material.dart';

import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../join/join_screen.dart' show validateDisplayName;

/// Result of [showHostSetupDialog]: [displayName] is null when the host does
/// not play along.
typedef HostSetup = ({String? displayName});

/// Bottom sheet asking whether the host plays along and under which name.
/// Returns null if dismissed.
Future<HostSetup?> showHostSetupDialog(BuildContext context) {
  return showModalBottomSheet<HostSetup>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const HostSetupDialog(),
  );
}

class HostSetupDialog extends StatefulWidget {
  const HostSetupDialog({super.key});

  @override
  State<HostSetupDialog> createState() => _HostSetupDialogState();
}

class _HostSetupDialogState extends State<HostSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _playAlong = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_playAlong && !(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop<HostSetup>((
      displayName: _playAlong ? _nameController.text.trim() : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        0,
        22,
        22 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FzEyebrow('New party'),
            const SizedBox(height: 8),
            Text(
              'Host tonight',
              style: fz.h(28, weight: FontWeight.w900, tracking: -.03),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('playAlongSwitch'),
              contentPadding: EdgeInsets.zero,
              title: Text('Play along', style: fz.h(16)),
              subtitle: Text(
                'Answer questions yourself too',
                style: fz.m(11.5, color: FzColors.dim),
              ),
              value: _playAlong,
              onChanged: (value) => setState(() => _playAlong = value),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('hostDisplayNameField'),
              controller: _nameController,
              enabled: _playAlong,
              autofocus: true,
              style: fz.h(18, weight: FontWeight.w700),
              decoration: const InputDecoration(hintText: 'Your display name'),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _confirm(),
              validator: _playAlong ? validateDisplayName : null,
            ),
            const SizedBox(height: 20),
            FzButton(
              key: const Key('createRoomButton'),
              label: 'Create room',
              onPressed: _confirm,
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: fz.m(12, color: FzColors.dim)),
            ),
          ],
        ),
      ),
    );
  }
}
