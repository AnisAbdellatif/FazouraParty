import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_release.freezed.dart';
part 'app_release.g.dart';

/// The `android.json` published beside every release APK (README, "Releasing
/// the Android app"). Written by `scripts/ci.sh apk`, read by the app.
///
/// [versionCode] is the only field the comparison uses: it is the integer
/// Android itself orders installs by, so a build is out of date exactly when
/// the release's code is higher than its own. [version] is for people.
@freezed
abstract class AppRelease with _$AppRelease {
  const factory AppRelease({
    required String version,
    required int versionCode,
    required String url,

    /// Size of the APK in bytes, shown before the download starts.
    int? size,

    /// SHA-256 of the APK, so a download can be checked by hand. Nothing in
    /// the app verifies it — the browser does the downloading.
    String? sha256,

    /// The tag's message, when it had one.
    String? notes,
  }) = _AppRelease;

  const AppRelease._();

  factory AppRelease.fromJson(Map<String, dynamic> json) =>
      _$AppReleaseFromJson(json);

  /// Rounded to the nearest tenth of a megabyte, which is as much precision as
  /// "how long will this take" needs.
  String? get sizeLabel {
    final bytes = size;
    if (bytes == null || bytes <= 0) return null;
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
