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

  /// A `media/` entry we will actually read back. A prefix check alone is not
  /// enough: `media/../..` still starts with `media/`, so an entry whose name
  /// climbs out of the package — an absolute path, or a `..` segment — is dropped
  /// rather than followed. The entries only ever live in memory as map keys here,
  /// but the check mirrors the server's `climbs_out?/1` so both readers agree.
  static bool _isSafeMediaPath(String name) {
    if (!name.startsWith('media/')) return false;
    if (name.startsWith('/')) return false;
    return !name.split('/').contains('..');
  }

  /// The modification time every entry of a package carries.
  static final packageTimestamp = DateTime(1980);

  /// A quiz is at most 1024 questions (QUIZ_FORMAT.md §2.1), each carrying at
  /// most one photo, so an honest package is a manifest plus up to ~1024 photos.
  /// This leaves generous headroom for that and a stray readme while refusing a
  /// member list so long that merely walking it is the attack.
  static const int _maxEntries = 2048;

  /// What a package is allowed to expand to. Photos are already-compressed
  /// formats, so an honest package barely shrinks and stays well under this; one
  /// that claims to expand many times over is a decompression bomb. Mirrors the
  /// server's `@max_unpacked_bytes` (`Fazoura.Quizzes.Archive`).
  static const int _maxUnpackedBytes = 48 * 1024 * 1024;

  /// What a package may weigh before it is parsed at all. Mirrors the server's
  /// `@max_bytes`.
  static const int _maxBytes = 32 * 1024 * 1024;

  static QuizArchive decode(List<int> bytes) {
    // A `.fazoura` read here is a local file the user chose (an offline
    // community-quiz download, or `fazoura quiz`), not the remote-unauthenticated
    // surface the server guards. These caps are defence-in-depth so a malformed
    // or hostile package fails cleanly instead of OOM-ing the app or the CLI;
    // they mirror the ceilings in `Fazoura.Quizzes.Archive`.
    if (bytes.length > _maxBytes) {
      throw const FormatException('Quiz archive is too large.');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    if (archive.files.length > _maxEntries) {
      throw const FormatException('Quiz archive has too many entries.');
    }

    // Bound both what an entry's header *claims* (cheap, caught before it is
    // inflated) and what inflating actually produces (a "lying" entry that
    // under-declares its size). The `archive` package inflates a member in one
    // shot — it exposes no streaming inflate with a running counter the way the
    // server's `:zlib.safeInflate` does — so a single under-declaring member is
    // still materialised in full before its real length can be checked; the
    // declared-size check keeps an honestly-sized bomb from getting even that
    // far, and the running total bounds the package as a whole.
    var unpacked = 0;
    Uint8List readCapped(ArchiveFile file) {
      if (file.size > _maxUnpackedBytes - unpacked) {
        throw const FormatException('Quiz archive expands too far.');
      }
      final content = file.readBytes();
      if (content == null) {
        throw const FormatException('Quiz archive entry is unreadable.');
      }
      unpacked += content.length;
      if (unpacked > _maxUnpackedBytes) {
        throw const FormatException('Quiz archive expands too far.');
      }
      return content;
    }

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const FormatException('Quiz archive has no manifest.');
    }
    final raw = jsonDecode(utf8.decode(readCapped(manifestFile)));
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Quiz archive manifest is invalid.');
    }
    final document = raw['quiz'];
    if (document is! Map<String, dynamic>) {
      throw const FormatException('Quiz archive manifest has no quiz.');
    }

    final media = <String, Uint8List>{
      for (final file in archive.files)
        if (file.isFile && _isSafeMediaPath(file.name))
          file.name: readCapped(file),
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
