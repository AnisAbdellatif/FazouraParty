/// Builds a `.fazoura` package from a folder of quiz JSON and photos
/// (protocol/QUIZ_FORMAT.md §5.3b), and reads a quiz from any of the forms one
/// can be kept in.
///
/// A package is one ZIP holding the quiz and the photos its questions use:
///
///     manifest.json        the quiz document, under "quiz"
///     media/<hash>.<ext>   one file per photo
///
/// The folder it is built from is laid out the way `server/priv/quizzes` is — a
/// quiz document with its photos beside it, named by a path relative to the
/// folder (`"image": {"path": "media/matrix.jpg"}`), or carried inline as
/// base64 `"data"`, which is how the app keeps them on the device.
///
/// Every photo is prepared exactly as the app's editor prepares one
/// ([preparePhoto]: at most 1280 px, metadata stripped, PNG only where it has
/// clear pixels), so a quiz is the same size however it was made and nobody in
/// a room downloads pixels their screen cannot show. It is then checked the way
/// the server checks an upload — JPEG, PNG or WebP by content, at most 2 MB — so
/// a package built here is one the server will take. Photos are named exactly
/// as the app names them
/// ([QuizArchive.mediaPath]), and every entry carries the same fixed timestamp,
/// so packing a folder twice gives the same bytes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/quizzes/photo_resize.dart';
import 'package:fazoura_party/core/quizzes/quiz_archive.dart';

/// What `Fazoura.Uploads` accepts.
const maxPhotoBytes = 2 * 1024 * 1024;

/// What `Fazoura.Quizzes.Archive` reads back.
const maxPackageBytes = 32 * 1024 * 1024;

/// The document contract this packer writes (QUIZ_FORMAT.md §2.1).
const formatVersion = '1.0';

/// Something about the folder or the document that the user has to fix.
class PackError implements Exception {
  const PackError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A quiz document ready to be written: photos named by `media/…` paths, and
/// the bytes behind each path.
class PackedQuiz {
  const PackedQuiz(this.document, this.photos);

  /// The document exactly as written into the manifest. Keys the packer does
  /// not know are kept: a newer minor may have added them.
  final Map<String, dynamic> document;
  final Map<String, Uint8List> photos;

  int get questionCount => (document['questions'] as List).length;

  /// The `.fazoura` bytes.
  Uint8List encode() {
    final manifest = const JsonEncoder.withIndent(
      '  ',
    ).convert({'quiz': _sorted(document)});
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('manifest.json', utf8.encode(manifest)));
    for (final path in photos.keys.toList()..sort()) {
      archive.addFile(ArchiveFile.bytes(path, photos[path]!));
    }
    final bytes = Uint8List.fromList(
      ZipEncoder().encodeBytes(archive, modified: QuizArchive.packageTimestamp),
    );
    if (bytes.length > maxPackageBytes) {
      throw PackError(
        'the package is ${_megabytes(bytes.length)} MB, over the '
        '${maxPackageBytes ~/ 1024 ~/ 1024} MB the server reads — '
        'use fewer or smaller photos',
      );
    }
    return bytes;
  }

  /// The quiz as the app holds a private one: every photo inline as base64,
  /// which is what hosting it sends (QUIZ_FORMAT.md §5.7).
  QuizDocument toInlineDocument() {
    final questions = [
      for (final question in document['questions'] as List)
        _inline(Map<String, dynamic>.from(question as Map)),
    ];
    return QuizDocument.fromJson({...document, 'questions': questions});
  }

  Map<String, dynamic> _inline(Map<String, dynamic> question) {
    final image = question['image'];
    if (image is! Map) return question;
    return {
      ...question,
      'image': {
        'alt': ?image['alt'],
        'data': base64Encode(photos[image['path']]!),
      },
    };
  }
}

/// The quiz document in [folder], or the one the caller named.
File findDocument(Directory folder, [File? given]) {
  if (given != null) {
    if (!given.existsSync()) throw PackError('${given.path} is not a file');
    return given;
  }
  final candidates =
      folder
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where(
            (file) => !const {
              'manifest.json',
              'package.json',
            }.contains(_basename(file.path)),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (candidates.isEmpty) {
    throw PackError(
      '${folder.path} holds no .json quiz document (use --quiz to name one)',
    );
  }
  if (candidates.length > 1) {
    final names = candidates.map((file) => _basename(file.path)).join(', ');
    throw PackError(
      '${folder.path} holds several documents ($names) — '
      'use --quiz to name one',
    );
  }
  return candidates.single;
}

/// Reads [document] and the photos it names, checked the way the server would
/// check them. Photo paths resolve against [folder].
PackedQuiz packFolder(Directory folder, File document) {
  final json = readDocument(document);
  final questions = checkDocument(json);
  final photos = <String, Uint8List>{};
  final packed = <Map<String, dynamic>>[];

  for (final (index, question) in questions.indexed) {
    final where = 'question ${index + 1}';
    final image = question['image'];
    final photo = question['type'] == 'text_photo';

    if (photo && image is! Map) {
      throw PackError('$where: a text_photo question needs an image');
    }
    if (!photo && image != null && image != false) {
      throw PackError('$where: only a text_photo question may carry an image');
    }
    if (image is! Map) {
      packed.add(question);
      continue;
    }

    final original = _photoBytes(folder, image, where);
    if (QuizArchive.photoExtension(original) == null) {
      throw PackError('$where: the photo is not a JPEG, PNG or WebP');
    }
    final data = preparePhoto(original);
    if (data.length > maxPhotoBytes) {
      throw PackError(
        '$where: the photo is ${_megabytes(data.length)} MB, '
        'over the 2 MB limit',
      );
    }

    final path = QuizArchive.mediaPath(data);
    photos[path] = data;
    // `key` and `url` mean something only on a server, so they never travel.
    packed.add({
      ...question,
      'image': {'path': path, if (image['alt'] is String) 'alt': image['alt']},
    });
  }

  return PackedQuiz({...json, 'questions': packed}, photos);
}

Map<String, dynamic> readDocument(File path) {
  final Object? json;
  try {
    json = jsonDecode(path.readAsStringSync());
  } on FormatException catch (error) {
    throw PackError('${path.path} is not valid JSON: ${error.message}');
  } on FileSystemException catch (error) {
    throw PackError('${path.path}: ${error.message}');
  }
  if (json is! Map<String, dynamic>) {
    throw PackError(
      '${path.path} must hold a quiz document (an object), '
      'not ${json.runtimeType}',
    );
  }
  return json;
}

/// Whether a document written for [version] can be read as [formatVersion].
///
/// The major has to match; the minor need not, because a minor only ever adds
/// keys an older reader ignores. A plain integer is a document from before the
/// format carried a minor at all, and is that major.
bool readableFormat(Object? version) {
  final text = switch (version) {
    int() => '$version.0',
    String() => version,
    _ => null,
  };
  return text != null &&
      text.split('.').first == formatVersion.split('.').first;
}

/// The checks the server would make anyway, made here where they are readable.
List<Map<String, dynamic>> checkDocument(Map<String, dynamic> document) {
  if (!readableFormat(document['format_version'])) {
    throw const PackError(
      'the document needs "format_version": "$formatVersion" '
      '(QUIZ_FORMAT.md §2.1)',
    );
  }
  final title = document['title'];
  if (title is! String || title.trim().isEmpty) {
    throw const PackError('the document needs a title');
  }
  final tags = document['tags'];
  if (tags is! List || tags.isEmpty || tags.length > 10) {
    throw const PackError(
      'the document needs 1 to 10 tags (QUIZ_FORMAT.md §2.3)',
    );
  }
  final questions = document['questions'];
  if (questions is! List || questions.isEmpty) {
    throw const PackError('the document needs at least one question');
  }

  return [
    for (final (index, question) in questions.indexed)
      _checkQuestion(index + 1, question),
  ];
}

Map<String, dynamic> _checkQuestion(int number, Object? question) {
  if (question is! Map<String, dynamic>) {
    throw PackError('question $number is not an object');
  }
  if (!const {'text', 'text_photo'}.contains(question['type'])) {
    throw PackError('question $number: type must be "text" or "text_photo"');
  }
  final prompt = question['prompt'];
  if (prompt is! String || prompt.trim().isEmpty) {
    throw PackError('question $number has no prompt');
  }
  final answers = question['accepted_answers'];
  if (answers is! List ||
      !answers.any((answer) => answer is String && answer.trim().isNotEmpty)) {
    throw PackError('question $number has no accepted answers');
  }
  return question;
}

/// The photo a question names, by a path beside the document or inline base64.
Uint8List _photoBytes(Directory folder, Map image, String where) {
  final path = image['path'];
  final data = image['data'];

  if (path is String) {
    // Resolved and checked afterwards, so `..` in the middle of a path cannot
    // climb out of the folder either.
    final root = folder.absolute.uri.normalizePath();
    final resolved = root.resolve(path).normalizePath();
    if (!resolved.path.startsWith(root.path)) {
      throw PackError('$where: $path is outside ${folder.path}');
    }
    try {
      return File.fromUri(resolved).readAsBytesSync();
    } on FileSystemException catch (error) {
      throw PackError(
        '$where: $path: ${error.osError?.message ?? error.message}',
      );
    }
  }

  if (data is String) {
    try {
      return base64Decode(data);
    } on FormatException catch (error) {
      throw PackError(
        '$where: image.data is not valid base64: ${error.message}',
      );
    }
  }

  throw PackError(
    '$where: a photo question needs an image with a "path" or "data"',
  );
}

/// A quiz from wherever one is kept: a `.fazoura` package, a quiz folder, or a
/// document on its own (photos then resolve beside it).
PackedQuiz loadQuiz(String location) {
  final type = FileSystemEntity.typeSync(location);
  if (type == FileSystemEntityType.directory) {
    final folder = Directory(location);
    return packFolder(folder, findDocument(folder));
  }
  if (type != FileSystemEntityType.file) {
    throw PackError('$location is not a file or a folder');
  }
  final file = File(location);
  if (location.endsWith('.fazoura') || location.endsWith('.zip')) {
    return _unpack(file);
  }
  return packFolder(file.parent, file);
}

/// A package read back into the same shape a folder packs into.
PackedQuiz _unpack(File file) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(file.readAsBytesSync(), verify: true);
  } on Object catch (error) {
    throw PackError('${file.path} is not a .fazoura package ($error)');
  }
  final manifest = archive.findFile('manifest.json');
  if (manifest == null) throw PackError('${file.path} has no manifest.json');
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(manifest.readBytes()!));
  } on FormatException catch (error) {
    throw PackError(
      '${file.path}: manifest.json is not JSON: ${error.message}',
    );
  }
  final document = json is Map ? json['quiz'] : null;
  if (document is! Map<String, dynamic>) {
    throw PackError('${file.path}: manifest.json holds no quiz');
  }
  checkDocument(document);
  final photos = <String, Uint8List>{
    for (final entry in archive.files)
      if (entry.isFile && entry.name.startsWith('media/'))
        entry.name: Uint8List.fromList(entry.readBytes()!),
  };
  for (final question in document['questions'] as List) {
    final image = (question as Map)['image'];
    if (image is Map && !photos.containsKey(image['path'])) {
      throw PackError('${file.path}: missing photo ${image['path']}');
    }
  }
  return PackedQuiz(document, photos);
}

/// Keys in order at every level, so the manifest reads the same every time.
Object? _sorted(Object? value) => switch (value) {
  Map() => {
    for (final key in value.keys.map((key) => '$key').toList()..sort())
      key: _sorted(value[key]),
  },
  List() => [for (final item in value) _sorted(item)],
  _ => value,
};

String _basename(String path) => path.split(Platform.pathSeparator).last;

String _megabytes(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);
