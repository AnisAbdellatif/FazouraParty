import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/navigation.dart';

import '../../core/lan/lan_host.dart' show defaultLanPort;
import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/providers/lan_providers.dart';
import '../../core/providers/room_tokens.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_direction.dart';
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

/// Default port a LAN host listens on, so a guest types an address, not a URL.
const _lanPort = defaultLanPort;

/// Turns what a guest types for a LAN host into a base URL, or null if it
/// cannot be one. Accepts `192.168.1.20`, `192.168.1.20:4040` and a full
/// `http://192.168.1.20:4040`, because all three are things people will type.
String? lanBaseUrl(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return null;

  final withScheme = text.contains('://') ? text : 'http://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) return null;
  // Only plain http: a LAN host has no certificate, and wss:// to a bare IP
  // cannot work (assessment §4.2).
  if (uri.scheme != 'http') return null;

  return 'http://${uri.host}:${uri.hasPort ? uri.port : _lanPort}';
}

String? validateLanAddress(String? input) =>
    lanBaseUrl(input) == null ? "That doesn't look like a host address" : null;

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
  const JoinScreen({super.key, this.initialCode});

  /// A room picked from the public list (PROTOCOL.md §3.5): the code is
  /// filled in, the name is what is left to type, and there is no LAN to ask
  /// about — a listed room is always online.
  final String? initialCode;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _lanController = TextEditingController();
  final _codeFocus = FocusNode();
  bool _joining = false;
  bool _overLan = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController.text = widget.initialCode ?? '';
    _codeController.addListener(_onChanged);
    _nameController.addListener(_onChanged);
    _lanController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _lanController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _ready =>
      validateRoomCode(_codeController.text) == null &&
      _nameController.text.trim().isNotEmpty &&
      (!_overLan || lanBaseUrl(_lanController.text) != null);

  Future<void> _join() async {
    if (_joining || !_ready) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = normalizeRoomCode(_codeController.text);
    final name = _nameController.text.trim();
    final tokens = ref.read(roomTokensProvider.notifier);

    setState(() {
      _joining = true;
      _error = null;
    });
    // Point the session at the right host *before* the connection is built:
    // gameConnectionProvider reads the target when it constructs.
    final target = ref.read(currentGameTargetProvider.notifier);
    if (_overLan) {
      target.useLan(lanBaseUrl(_lanController.text)!);
    } else {
      target.useCloud();
    }
    ref.invalidate(gameConnectionProvider);
    try {
      final result = await ref
          .read(gameConnectionProvider)
          .join(code, name, playerToken: await tokens.playerTokenFor(code));
      final token = result.playerToken;
      if (token != null) await tokens.savePlayerToken(code, token);
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushReplacement(
          FzPageRoute<void>(builder: (_) => PlayerGameScreen(roomCode: code)),
        ),
      );
    } catch (error) {
      if (error is GameError &&
          (error.code == 'room_not_found' || error.code == 'invalid_token')) {
        await tokens.drop(code);
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
                widget.initialCode == null
                    ? 'Enter the\nroom code'
                    : 'Join the\nroom',
                style: fz.t(31, height: 1.16, tracking: -.03),
              ),
              const SizedBox(height: 10),
              Text(
                widget.initialCode == null
                    ? 'The host sees it on their screen.'
                    : 'A public room. Pick a name and you\u2019re in.',
                style: fz.m(12, color: FzColors.dim),
              ),
              const SizedBox(height: 28),
              _CodeBoxes(
                controller: _codeController,
                focusNode: _codeFocus,
                enabled: !_joining,
                autofocus: widget.initialCode == null,
              ),
              const SizedBox(height: 28),
              const FzEyebrow('Your name'),
              const SizedBox(height: 10),
              FzTypingDirection(
                controller: _nameController,
                child: TextFormField(
                  key: const Key('displayNameField'),
                  controller: _nameController,
                  enabled: !_joining,
                  autofocus: widget.initialCode != null,
                  style: fz.h(18, weight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: 'What should we call you?',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _join(),
                  validator: validateDisplayName,
                ),
              ),
              if (widget.initialCode == null) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('joinOverLanSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('Host is on this Wi-Fi', style: fz.h(16)),
                  subtitle: Text(
                    'For a party with no internet.',
                    style: fz.m(11.5, color: FzColors.dim),
                  ),
                  value: _overLan,
                  onChanged: _joining
                      ? null
                      : (value) => setState(() => _overLan = value),
                ),
                if (_overLan) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    key: const Key('lanAddressField'),
                    controller: _lanController,
                    enabled: !_joining,
                    style: fz.h(18, weight: FontWeight.w700),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText: '192.168.1.20',
                      helperText: 'The address on the host\u2019s screen',
                      helperStyle: fz.m(11, color: FzColors.dim),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _join(),
                    validator: _overLan ? validateLanAddress : null,
                  ),
                ],
              ],
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
    required this.autofocus,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool autofocus;

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
                autofocus: autofocus,
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
