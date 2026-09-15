import '../core/models/models.dart';

/// Human-readable text for a [GameError] code (PROTOCOL.md §4).
String describeError(Object error) {
  if (error is! GameError) return 'Something went wrong.';
  return switch (error.code) {
    'room_not_found' => 'That room does not exist or has ended.',
    'name_taken' => 'That name is already taken in this room.',
    'invalid_name' => 'Names must be 1–20 characters.',
    'room_full' => 'That room is full.',
    'invalid_token' => 'Your previous session for this room expired.',
    'unsupported_protocol_version' =>
      'This app version is not compatible with the server.',
    'invalid_phase' => 'That is not allowed right now.',
    'already_submitted' => 'You already answered this question.',
    'invalid_answer' => 'Answers must be 1–100 characters.',
    'invalid_wager' => 'Wager must be between 1 and 10.',
    'paused' => 'The game is paused.',
    'not_paused' => 'The game is not paused.',
    'no_submission' => 'That player did not answer.',
    'not_host' => 'Only the host can do that.',
    'not_player' => 'Only players can do that.',
    GameError.connectionFailed => 'Could not reach the game server.',
    GameError.timeout => 'The game server did not answer.',
    _ => error.message ?? 'Something went wrong (${error.code}).',
  };
}
