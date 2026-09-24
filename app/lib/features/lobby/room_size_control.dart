import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

/// The host's room size (PROTOCOL.md §6.5): how many players the room lets in,
/// from the players already here up to the room's limit, and — online — a
/// room size code to raise that limit.
class RoomSizeControl extends StatefulWidget {
  const RoomSizeControl({
    super.key,
    required this.state,
    required this.onSetSize,
    required this.onRedeem,
  });

  final RoomState state;
  final Future<void> Function(int size) onSetSize;

  /// Null where there are no codes to redeem: a LAN host keeps none.
  final Future<void> Function(String code)? onRedeem;

  @override
  State<RoomSizeControl> createState() => _RoomSizeControlState();
}

class _RoomSizeControlState extends State<RoomSizeControl> {
  // The size last asked for, until a snapshot says it. Taps count from it, so
  // three quick taps are three players, not the same request three times.
  int? _asked;

  @override
  void didUpdateWidget(RoomSizeControl old) {
    super.didUpdateWidget(old);
    if (widget.state.roomSize == _asked) _asked = null;
  }

  // Held until a snapshot shows it — which can come after the reply, since
  // snapshots are paced (PROTOCOL.md §5.1) — or dropped if it is refused.
  Future<void> _ask(int size) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _asked = size);
    try {
      await widget.onSetSize(size);
    } catch (error) {
      if (mounted && _asked == size) setState(() => _asked = null);
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final state = widget.state;
    final limit = state.roomSizeLimit;
    final size = _asked ?? state.roomSize;
    if (size == null || limit == null) return const SizedBox.shrink();
    final smallest = state.players.isEmpty ? 1 : state.players.length;
    final redeem = widget.onRedeem;

    return FzPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FzEyebrow('Room size', size: 10.5),
          const SizedBox(height: 8),
          Row(
            children: [
              FzCircleButton(
                key: const Key('roomSizeLess'),
                icon: Icons.remove,
                tooltip: 'Fewer players',
                onPressed: size > smallest ? () => _ask(size - 1) : null,
              ),
              Expanded(
                child: Text(
                  '$size',
                  key: const Key('roomSizeValue'),
                  textAlign: TextAlign.center,
                  style: fz.m(26, color: FzColors.ac),
                ),
              ),
              FzCircleButton(
                key: const Key('roomSizeMore'),
                icon: Icons.add,
                tooltip: 'More players',
                onPressed: size < limit ? () => _ask(size + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Up to $limit players',
                  key: const Key('roomSizeLimit'),
                  style: fz.m(11, color: FzColors.dim),
                ),
              ),
              if (redeem != null)
                FzPill(
                  key: const Key('roomSizeCodeButton'),
                  label: 'Have a code?',
                  icon: Icons.key,
                  onPressed: () => _askForCode(context, redeem),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _askForCode(
    BuildContext context,
    Future<void> Function(String code) redeem,
  ) async {
    final unlocked = await showDialog<bool>(
      context: context,
      builder: (_) => _CodeDialog(redeem: redeem),
    );
    if ((unlocked ?? false) && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Room size unlocked.')));
    }
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.redeem});

  final Future<void> Function(String code) redeem;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.redeem(code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return AlertDialog(
      title: const Text('Unlock a bigger room'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter the room size code you were given.',
            style: fz.m(12, color: FzColors.dim, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('roomSizeCodeField'),
            controller: _code,
            autofocus: true,
            enabled: !_sending,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            style: fz.m(17, tracking: .08),
            decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX'),
            onSubmitted: (_) => _send(),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 10),
            Text(
              error,
              key: const Key('roomSizeCodeError'),
              style: fz.m(12, color: FzColors.ac2, height: 1.4),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: FzColors.dim),
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('roomSizeCodeSubmit'),
          onPressed: _sending ? null : _send,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}
