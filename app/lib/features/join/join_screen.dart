import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/providers/player_tokens.dart';
import '../../shared/describe_error.dart';
import '../player/player_game_screen.dart';

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

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _joining = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_joining) return;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Join a game')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  TextFormField(
                    key: const Key('roomCodeField'),
                    controller: _codeController,
                    enabled: !_joining,
                    decoration: const InputDecoration(
                      labelText: 'Room code',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    validator: validateRoomCode,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('displayNameField'),
                    controller: _nameController,
                    enabled: !_joining,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      border: OutlineInputBorder(),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('joinButton'),
                    onPressed: _joining ? null : _join,
                    child: Text(_joining ? 'Joining…' : 'Join'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
