import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_release.dart';

/// Reads the release manifest published beside the newest APK.
///
/// Nothing here is part of the game protocol: it is one small `GET` against a
/// static file, deliberately separate from `RoomApi` and `QuizApi` because it
/// does not talk to the Fazoura server at all (README, "Releasing the Android
/// app").
class UpdateApi {
  UpdateApi({required this.manifestUrl, http.Client? client})
    : _client = client ?? http.Client();

  /// Absolute URL of the `android.json` manifest.
  final String manifestUrl;
  final http.Client _client;

  /// A check runs on a cold start, so it must not hold anything up; the app
  /// simply goes without a result when the network is slow.
  static const timeout = Duration(seconds: 8);

  /// The newest published release, or null when the manifest is missing,
  /// unreadable, or points somewhere this app will not send a user.
  ///
  /// Never throws for a network or parsing failure — a silent no is the right
  /// answer for something nobody asked for. The caller decides whether to say
  /// anything about it.
  Future<AppRelease?> latest() async {
    final manifest = Uri.tryParse(manifestUrl);
    if (manifest == null) return null;

    final http.Response response;
    try {
      response = await _client
          .get(manifest, headers: const {'accept': 'application/json'})
          .timeout(timeout);
    } catch (_) {
      return null;
    }

    if (response.statusCode != 200) return null;

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final release = AppRelease.fromJson(body);
      return isTrustedDownload(release.url, manifest) ? release : null;
    } catch (_) {
      return null;
    }
  }
}

/// Whether a download URL out of the manifest is one the app will hand to the
/// browser.
///
/// The manifest is remote content, and the app's response to it is to open a
/// URL — so the URL has to be constrained rather than trusted. It must be
/// `https`, on the same host the manifest itself came from, and under the same
/// repository's releases: a manifest that has been tampered with can then still
/// only point at this project's own release files — never at another scheme
/// (`intent://`, `market://`), another site, or another repository on the same
/// host, which on github.com is anybody's.
///
/// The repository is everything in the manifest's path up to `releases`
/// (`/<owner>/<repo>/releases/latest/download/android.json`); a manifest served
/// from somewhere without one pins downloads to its own folder instead.
bool isTrustedDownload(String url, Uri manifest) {
  final target = Uri.tryParse(url);
  if (target == null) return false;
  if (target.scheme != 'https' ||
      target.host.isEmpty ||
      target.host.toLowerCase() != manifest.host.toLowerCase()) {
    return false;
  }

  final path = target.pathSegments;
  if (path.any((segment) => segment == '..' || segment == '.')) return false;

  final from = manifest.pathSegments;
  final releases = from.indexOf('releases');
  final root = releases >= 0
      ? from.sublist(0, releases + 1)
      : from.sublist(0, from.isEmpty ? 0 : from.length - 1);
  if (path.length <= root.length) return false;
  for (var i = 0; i < root.length; i++) {
    if (path[i] != root[i]) return false;
  }
  return true;
}
