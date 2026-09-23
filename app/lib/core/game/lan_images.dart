/// Photos of the quiz a LAN room is hosting, held in memory for as long as the
/// room lives.
///
/// Dart counterpart of `Fazoura.Rooms.Images` plus the inline-photo half of
/// `Fazoura.Quizzes.inline_pack/1` (protocol/QUIZ_FORMAT.md §5.7). A LAN host
/// only ever plays quizzes the device already holds, so photos arrive the same
/// way Cloud receives a private quiz: base64 `image.data` inside the document
/// the host sends with `host_select_quiz`. They are stored under a random key
/// and served by [LanHost] at `/api/room-images/<key>`, so the wire carries an
/// ordinary `image_url` and clients cannot tell the two hosts apart.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/quiz.dart';
import 'game.dart';

/// One stored photo: the bytes and the type detected from them.
typedef LanImage = ({String contentType, Uint8List bytes});

/// The photos of the currently selected quiz.
class LanImages {
  LanImages({Random? random}) : _random = random ?? Random.secure();

  /// Largest single photo, and largest total one room may hold. The same
  /// bounds Cloud applies to an inline quiz (`Fazoura.Uploads.max_bytes/0`,
  /// `Fazoura.Quizzes.max_inline_bytes/0`), so a quiz that hosts on one host
  /// hosts on the other.
  static const maxImageBytes = 2 * 1024 * 1024;
  static const maxTotalBytes = 8 * 1024 * 1024;

  final Random _random;
  final Map<String, LanImage> _images = {};

  int get length => _images.length;

  LanImage? fetch(String key) => _images[key];

  void clear() => _images.clear();

  /// Takes the inline photos out of [quiz] and returns the document with each
  /// one replaced by the key it would be served under, alongside the photos
  /// themselves and the bytes the room holds once they are committed. Stores
  /// nothing: the caller [commit]s only once the whole selection has been
  /// accepted, so a refused one leaves the room's photos untouched.
  ///
  /// [spent] is what the rest of the selection already accounts for. A round
  /// may name up to ten quizzes (PROTOCOL.md §6.4) and [maxTotalBytes] bounds
  /// the *room*, so the total is carried across them rather than restarting at
  /// each one — the same budget `Fazoura.Quizzes.inline_pack/2` threads.
  ///
  /// Throws [GameRuleError] with `invalid_quiz` for a photo that is not a
  /// supported image or that pushes the room over the total — the same code
  /// Cloud answers `host_select_quiz` with when it refuses a document.
  ({QuizDocument quiz, Map<String, LanImage> images, int spent}) prepare(
    QuizDocument quiz, {
    int spent = 0,
  }) {
    final stored = <String, LanImage>{};
    final questions = <QuizQuestion>[];
    var total = spent;

    for (final question in quiz.questions ?? const <QuizQuestion>[]) {
      final bytes = _bytesOf(question);
      if (bytes == null) {
        questions.add(question.copyWith(image: null));
        continue;
      }

      // Which of the three, as Cloud says it (`Fazoura.Rooms.Selection`):
      // each is something the host can do something about.
      final detected = detect(bytes);
      total += bytes.length;
      if (detected == null) throw const GameRuleError('unsupported_image');
      if (bytes.length > maxImageBytes) {
        throw const GameRuleError('image_too_large');
      }
      if (total > maxTotalBytes) throw const GameRuleError('quiz_too_large');

      final key = newKey(detected.ext);
      stored[key] = (contentType: detected.contentType, bytes: bytes);
      questions.add(
        question.copyWith(
          image: QuizImage(key: key, alt: question.image?.alt),
        ),
      );
    }

    return (
      quiz: quiz.copyWith(questions: questions),
      images: stored,
      spent: total,
    );
  }

  /// Serves [images] from now on, dropping the previous selection's photos. A
  /// quiz is only ever chosen in the lobby, so the old pack is already
  /// unreachable and its photos are dead weight on a phone.
  void commit(Map<String, LanImage> images) {
    _images
      ..clear()
      ..addAll(images);
  }

  /// The photo's bytes, or null when the question carries none. A stored
  /// `key` or `url` means nothing to a LAN host — it has no upload directory
  /// and, by definition, no internet — so only `data` counts, exactly as for
  /// an inline quiz on Cloud.
  static Uint8List? _bytesOf(QuizQuestion question) {
    final data = question.image?.data;
    if (!question.hasPhoto || data == null) return null;
    try {
      final bytes = base64.decode(data.replaceAll(RegExp(r'\s'), ''));
      return bytes.isEmpty ? throw const GameRuleError('invalid_quiz') : bytes;
    } on FormatException {
      throw const GameRuleError('invalid_quiz');
    }
  }

  /// Random and unguessable, so a guest cannot enumerate a room's photos.
  String newKey(String ext) {
    final bytes = List.generate(18, (_) => _random.nextInt(256));
    return '${base64Url.encode(bytes).replaceAll('=', '')}.$ext';
  }

  /// Content type and extension from the magic bytes, matching
  /// `Fazoura.Uploads.detect/1` so both hosts accept exactly the same formats.
  ///
  /// Unlike Cloud this does not also validate the header structurally: that
  /// check exists because Cloud stores bytes a stranger uploaded, whereas
  /// these come from the hosting device's own database, having already passed
  /// it when the photo was added or downloaded. The bytes are still served
  /// with the same `nosniff` and sandbox headers.
  static ({String contentType, String ext})? detect(Uint8List bytes) {
    bool startsWith(List<int> magic, {int offset = 0}) {
      if (bytes.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[offset + i] != magic[i]) return false;
      }
      return true;
    }

    if (startsWith([0xFF, 0xD8, 0xFF])) {
      return (contentType: 'image/jpeg', ext: 'jpg');
    }
    if (startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return (contentType: 'image/png', ext: 'png');
    }
    // "RIFF" then four size bytes then "WEBP".
    if (startsWith([0x52, 0x49, 0x46, 0x46]) &&
        startsWith([0x57, 0x45, 0x42, 0x50], offset: 8)) {
      return (contentType: 'image/webp', ext: 'webp');
    }
    return null;
  }
}
