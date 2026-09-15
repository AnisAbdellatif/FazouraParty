import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sembast/sembast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/quiz_api.dart';
import '../models/models.dart';
import '../quizzes/quiz_library.dart';
import '../storage/local_database.dart';
import '../storage/local_quiz_store.dart';
import 'config_providers.dart';

part 'quiz_providers.g.dart';

const _ownerKeyPref = 'fazoura.owner_key';

/// 32 random bytes, base64url without padding (43 chars, QUIZ_FORMAT.md §4).
String generateOwnerKey([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// This device's secret publisher key, created once and kept in local
/// storage. Not an account: it only lets this device update or unpublish the
/// quizzes it published.
@Riverpod(keepAlive: true)
Future<String> ownerKey(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_ownerKeyPref);
  if (existing != null && existing.length >= 32) return existing;
  final key = generateOwnerKey();
  await prefs.setString(_ownerKeyPref, key);
  return key;
}

/// Picks a photo from the device and returns its bytes, or null if cancelled.
typedef PhotoPicker = Future<Uint8List?> Function();

/// Gallery picker (file chooser on web). Overridden in tests.
@Riverpod(keepAlive: true)
PhotoPicker photoPicker(Ref ref) => () async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
  );
  return file?.readAsBytes();
};

@Riverpod(keepAlive: true)
QuizApi quizApi(Ref ref) {
  final api = QuizApi(
    baseUrl: ref.watch(serverBaseUrlProvider),
    ownerKey: () => ref.read(ownerKeyProvider.future),
  );
  ref.onDispose(api.close);
  return api;
}

/// Tag quick picks, maintained by an admin on the server. Falls back to the
/// built-in list when the server can't be reached (QUIZ_FORMAT.md §2.3).
@Riverpod(keepAlive: true)
Future<List<String>> suggestedTags(Ref ref) async {
  try {
    final tags = await ref.watch(quizApiProvider).tags();
    return tags.suggested.isEmpty ? defaultQuizTags : tags.suggested;
  } catch (_) {
    return defaultQuizTags;
  }
}

/// On-device database. Overridden with an in-memory one in tests.
@Riverpod(keepAlive: true)
Future<Database> localDatabase(Ref ref) => openLocalDatabase();

@Riverpod(keepAlive: true)
QuizLibrary quizLibrary(Ref ref) => QuizLibrary(
  store: LocalQuizStore(ref.watch(localDatabaseProvider.future)),
  api: ref.watch(quizApiProvider),
);
