import '../core/models/models.dart';
import '../core/providers/update_providers.dart';

/// Human-readable text for a [GameError] code (PROTOCOL.md §4).
String describeError(Object error) {
  if (error is UpdateCheckFailed) {
    return 'Could not check for updates. Try again when you have a connection.';
  }
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
    'invalid_settings' =>
      'Pick 1 question up to the pack size, and 10–120 seconds per question.',
    'quiz_required' => 'Choose a quiz before starting the game.',
    'empty_pack' => 'That quiz has no playable questions.',
    'already_submitted' => 'You already answered this question.',
    'invalid_answer' => 'Answers must be 1–100 characters.',
    'paused' => 'The game is paused.',
    'not_paused' => 'The game is not paused.',
    'no_submission' => 'That player did not answer.',
    'not_host' => 'Only the host can do that.',
    'not_player' => 'Only players can do that.',
    'quiz_not_found' ||
    'pack_not_found' => 'That quiz is gone or no longer shared with you.',
    'owner_key_required' => 'This device could not prove it owns that quiz.',
    'unknown_image' => 'A photo is missing. Pick it again and save.',
    'image_too_large' => 'That photo is too big (2 MB max).',
    'unsupported_image' => 'Use a JPEG, PNG or WebP photo.',
    'invalid_quiz' => error.message ?? 'The quiz has errors.',
    // Also what reporting a question from a quiz nobody published answers, so
    // the server's own words are the right ones in either place.
    'quiz_not_public' =>
      error.message ?? 'A public room plays quizzes from the library only.',
    'cloud_only' => 'Only an online room can be listed publicly.',
    'name_not_allowed' => "That name can't be used in a public room.",
    'banned' => "Public rooms aren't available from this connection for now.",
    'unknown_player' => "That player isn't in the room any more.",
    GameError.connectionFailed => 'Could not reach the game server.',
    GameError.timeout => 'The game server did not answer.',
    _ => error.message ?? 'Something went wrong (${error.code}).',
  };
}
