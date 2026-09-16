import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/providers/player_tokens.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../player/player_game_screen.dart';

const roomCodeLength = 6;

/// Upper-cases and strips all whitespace (PROTOCOL.md §3.2).
String normalizeRoomCode(String input) =>
    input.replaceAll(RegExp(r'\s+'), '').toUpperCase();

String? validateRoomCode(String? input) {
  final code = normalizeRoomCode(input ?? '');
  if (code.isEmpty) return 'Enter the room code';
  if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
    return 'Room codes are 6 letters or digits';
  }
  return null;
}

String? validateDisplayName(String? input) {
  final name = (input ?? '').trim();
  if (name.isEmpty) return 'Enter a display name';
  if (name.characters.length > 20) return 'Use at most 20 characters';
  return null;
}

/// Keeps only letters and digits, upper-cased, at most [roomCodeLength].
/// Pasting " k7qx-2m " yields "K7QX2M".
class RoomCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.toUpperCase().replaceAll(
      RegExp('[^A-Z0-9]'),
      '',
    );
    final text = cleaned.substring(0, math.min(cleaned.length, roomCodeLength));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _codeFocus = FocusNode();
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onChanged);
    _nameController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _ready =>
      validateRoomCode(_codeController.text) == null &&
      _nameController.text.trim().isNotEmpty;

  Future<void> _join() async {
    if (_joining || !_ready) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = normalizeRoomCode(_codeController.text);
    final name = _nameController.text.trim();
    final tokens = ref.read(playerTokensProvider.notifier);

    setState(() {
      _joining = true;
      _error = null;
    });
    ref.invalidate(gameConnectionProvider);
    try {
      final result = await ref
          .read(gameConnectionProvider)
          .join(code, name, playerToken: tokens.tokenFor(code));
      final token = result.playerToken;
      if (token != null) tokens.save(code, token);
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PlayerGameScreen(roomCode: code),
          ),
        ),
      );
    } catch (error) {
      if (error is GameError &&
          (error.code == 'room_not_found' || error.code == 'invalid_token')) {
        tokens.drop(code);
      }
      ref.invalidate(gameConnectionProvider);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = describeError(error);
      });
    }
  }

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
          key: const Key('joinButton'),
          label: _joining ? 'Joining…' : 'Join room',
          onPressed: _joining || !_ready ? null : _join,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                'Enter the\nroom code',
                style: fz.t(31, height: 1.16, tracking: -.03),
              ),
              const SizedBox(height: 10),
              Text(
                'The host sees it on their screen.',
                style: fz.m(12, color: FzColors.dim),
              ),
              const SizedBox(height: 28),
              _CodeBoxes(
                controller: _codeController,
                focusNode: _codeFocus,
                enabled: !_joining,
              ),
              const SizedBox(height: 28),
              const FzEyebrow('Your name'),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('displayNameField'),
                controller: _nameController,
                enabled: !_joining,
                style: fz.h(18, weight: FontWeight.w700),
                decoration: const InputDecoration(
                  hintText: 'What should we call you?',
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _join(),
                validator: validateDisplayName,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  key: const Key('joinError'),
                  style: fz.m(12, color: FzColors.ac2, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Six code boxes fed by a transparent text field on top, so the system
/// keyboard, paste and web input all work.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final code = controller.text;
        final activeIndex = focusNode.hasFocus && code.length < roomCodeLength
            ? code.length
            : -1;
        return Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < roomCodeLength; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1 / 1.15,
                      child: _box(
                        fz,
                        i < code.length ? code[i] : null,
                        i == activeIndex,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Positioned.fill(
              child: TextField(
                key: const Key('roomCodeField'),
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                autofocus: true,
                showCursor: false,
                enableInteractiveSelection: false,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                inputFormatters: [RoomCodeInputFormatter()],
                // Invisible input stretched over the boxes: no text, no
                // borders (the theme's outlined borders would otherwise
                // draw a line), and the whole area is tappable.
                expands: true,
                maxLines: null,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _box(FzTheme fz, String? char, bool active) {
    final filled = char != null;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? FzColors.ac.withValues(alpha: .14)
            : const Color(0x0AFBF6EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: 1.5,
          color: filled
              ? FzColors.ac
              : active
              ? FzColors.ink.withValues(alpha: .5)
              : const Color(0x21FBF6EC),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          char ?? '·',
          style: fz.m(
            30,
            color: filled ? FzColors.ink : const Color(0x33FBF6EC),
          ),
        ),
      ),
    );
  }
}
