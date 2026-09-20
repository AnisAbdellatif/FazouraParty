import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/models.dart';

/// Reads the portable `.fazoura` ZIP format:
/// `manifest.json` contains the full quiz document and question images live
/// under `media/`.
class QuizArchive {
  const QuizArchive({required this.quiz});

  final QuizDocument quiz;

  static QuizArchive decode(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
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
