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
/// `https`, and it must be on the same host the manifest itself came from: a
/// manifest that has been tampered with can then still only point at the
/// release host it was served by, never at another scheme (`intent://`,
/// `market://`) or another site.
bool isTrustedDownload(String url, Uri manifest) {
  final target = Uri.tryParse(url);
  if (target == null) return false;
  return target.scheme == 'https' &&
      target.host.isNotEmpty &&
      target.host.toLowerCase() == manifest.host.toLowerCase();
}
