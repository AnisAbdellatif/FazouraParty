import 'package:flutter/material.dart';

import '../join/join_screen.dart' show validateDisplayName;

/// Result of [showHostSetupDialog]: [displayName] is null when the host does
/// not play along.
typedef HostSetup = ({String? displayName});

/// Asks the host whether to play along and under which name.
/// Returns null if cancelled.
Future<HostSetup?> showHostSetupDialog(BuildContext context) {
  return showDialog<HostSetup>(
    context: context,
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
    return AlertDialog(
      title: const Text('Host a game'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              key: const Key('playAlongSwitch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Play along'),
              subtitle: const Text('Answer questions yourself too'),
              value: _playAlong,
              onChanged: (value) => setState(() => _playAlong = value),
            ),
            TextFormField(
              key: const Key('hostDisplayNameField'),
              controller: _nameController,
              enabled: _playAlong,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Your display name',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _confirm(),
              validator: _playAlong ? validateDisplayName : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('createRoomButton'),
          onPressed: _confirm,
          child: const Text('Create room'),
        ),
      ],
    );
  }
}
