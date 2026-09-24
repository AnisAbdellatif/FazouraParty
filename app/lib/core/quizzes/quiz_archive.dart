import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../models/models.dart';

/// Reads and writes the portable `.fazoura` ZIP format:
/// `manifest.json` contains the full quiz document and question images live
/// under `media/`.
class QuizArchive {
  const QuizArchive({required this.quiz});

  final QuizDocument quiz;

  /// Packs [quiz] and its photos into one `.fazoura` binary.
  ///
  /// This is what publishing sends (QUIZ_FORMAT.md §5.4): a submission *is* the
  /// package, so the photos travel inside it rather than being uploaded first.
  /// Nothing anybody writes reaches the server's uploads volume before somebody
  /// has approved it, which is the whole point of the queue.
  ///
  /// Throws [FormatException] when a photo question has no photo data to pack:
  /// a package is meant to be self-contained, and a partial one would publish a
  /// question with a hole in it.
  static Uint8List encode(QuizDocument quiz) {
    final media = <String, Uint8List>{};
    final questions = [
      for (final question in quiz.questions ?? const <QuizQuestion>[])
        _packQuestion(question, media),
    ];

    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'quiz': {...quiz.toJson(), 'questions': questions},
          }),
        ),
      );
    // Sorted, and every entry stamped with one fixed time, so packing the same
    // quiz twice gives the same bytes. The clock would otherwise make every
    // package unique. ZIP cannot store a year before 1980.
    for (final path in media.keys.toList()..sort()) {
      archive.addFile(ArchiveFile.bytes(path, media[path]!));
    }
    return Uint8List.fromList(
      ZipEncoder().encodeBytes(archive, modified: packageTimestamp),
    );
  }

  static Map<String, dynamic> _packQuestion(
    QuizQuestion question,
    Map<String, Uint8List> media,
  ) {
    final json = question.toJson();
    final image = question.image;
    if (!question.hasPhoto || image == null) {
      json.remove('image');
      return json;
    }
    final data = image.data;
    if (data == null) {
      throw FormatException('No photo to pack for "${question.prompt}".');
    }
    final bytes = base64Decode(data);
    final path = mediaPath(bytes);
    media[path] = bytes;
    // `path` replaces `key` and `url`: inside a package a photo is a file, and
    // there is no upload of it for the server to point at yet.
    json['image'] = {'path': path, if (image.alt != null) 'alt': image.alt};
    return json;
  }

  /// A photo is named by a digest of its own bytes, so the same picture on two
  /// questions is carried once. The shape matches a key the server would
  /// generate — 24 hex characters and an extension — because on approval the
  /// photo is stored through exactly that path. Public so that
  /// `tools/fazoura-cli` names photos exactly as the app does.
  ///
  /// An unrecognised format is called `jpg`: everything the editor produces is
  /// JPEG or PNG (`preparePhoto`), and an extension that turns out wrong costs
  /// nothing, since the server reads the bytes, not the name.
  static String mediaPath(List<int> bytes) =>
      'media/${sha256.convert(bytes).toString().substring(0, 24)}'
      '.${photoExtension(bytes) ?? 'jpg'}';

  /// `jpg`, `png` or `webp` by magic bytes, or null for anything else. Never by
  /// a filename: the server sniffs the same three formats and refuses
  /// everything else (`Fazoura.Uploads.detect/1`).
  static String? photoExtension(List<int> bytes) {
    bool starts(List<int> magic, [int offset = 0]) {
      if (bytes.length < offset + magic.length) return false;
      for (var index = 0; index < magic.length; index++) {
        if (bytes[offset + index] != magic[index]) return false;
      }
      return true;
    }

    if (starts(const [0xFF, 0xD8, 0xFF])) return 'jpg';
    if (starts(const [0x89, 0x50, 0x4E, 0x47])) return 'png';
    if (starts(const [0x52, 0x49, 0x46, 0x46]) &&
        starts(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return 'webp';
    }
    return null;
  }

  /// The modification time every entry of a package carries.
  static final packageTimestamp = DateTime(1980);

  /// The server's limits on a package (`Fazoura.Quizzes.Archive`): what it may
  /// weigh, and what it may say it unpacks into.
  static const maxBytes = 32 * 1024 * 1024;
  static const maxUnpackedBytes = 48 * 1024 * 1024;

  static QuizArchive decode(List<int> bytes) {
    // Only ever handed a package the server built or this device wrote, but a
    // decoder is no place to find out otherwise by running out of memory.
    if (bytes.length > maxBytes) {
      throw const FormatException('Quiz archive is too large.');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final unpacked = archive.files.fold<int>(0, (sum, file) => sum + file.size);
    if (unpacked > maxUnpackedBytes) {
      throw const FormatException('Quiz archive unpacks into too much.');
    }
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const FormatException('Quiz archive has no manifest.');
    }
    final raw = jsonDecode(utf8.decode(manifestFile.readBytes()!));
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Quiz archive manifest is invalid.');
    }
    final document = raw['quiz'];
    if (document is! Map<String, dynamic>) {
      throw const FormatException('Quiz archive manifest has no quiz.');
    }

    final media = <String, Uint8List>{
      for (final file in archive.files)
        if (file.isFile && file.name.startsWith('media/'))
          file.name: file.readBytes()!,
    };
    final questions = (document['questions'] as List<dynamic>? ?? const []).map(
      (item) {
        final question = Map<String, dynamic>.from(item as Map);
        final image = question['image'];
        if (image is Map) {
          final imageMap = Map<String, dynamic>.from(image);
          final path = imageMap['path'];
          final imageBytes = path is String ? media[path] : null;
          if (imageBytes == null) {
            throw FormatException('Missing quiz image: $path');
          }
          question['image'] = {
            'alt': imageMap['alt'],
            'data': base64Encode(imageBytes),
          };
        }
        return question;
      },
    ).toList();

    return QuizArchive(
      quiz: QuizDocument.fromJson({...document, 'questions': questions}),
    );
  }
}
