import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../update/app_release.dart';
import '../update/app_version.dart';
import '../update/update_api.dart';
import 'config_providers.dart';

part 'update_providers.g.dart';

const _manifestPref = 'fazoura.update.manifest';
const _checkedAtPref = 'fazoura.update.checked_at';
const _dismissedPref = 'fazoura.update.dismissed';

/// How long a fetched manifest stands in for a fresh one. Long enough that
/// launching the app four times in an evening costs one request, short enough
/// that a release published this morning is offered tonight.
const updateCheckInterval = Duration(hours: 6);

/// What the app knows about updating itself right now.
///
/// One record rather than the `AsyncValue` loading and error arms, because the
/// interesting states overlap: a check can be running, or have just failed,
/// while an update found earlier is still worth offering. Folding those into
/// `AsyncLoading`/`AsyncError` throws the release away at exactly the moment it
/// matters — tap "check again" in a tunnel and the download button vanishes.
///
/// [failure] is only ever set by a check somebody asked for. The automatic one
/// stays silent (see [AvailableUpdate]).
typedef UpdateStatus = ({
  AppRelease? release,
  bool dismissed,
  bool checking,
  Object? failure,
});

const _nothing = (
  release: null,
  dismissed: false,
  checking: false,
  failure: null,
);

/// Opens a URL outside the app. A typedef with a provider so tests can watch
/// what would have been launched, the same way `photoPicker` works.
typedef UrlOpener = Future<bool> Function(Uri url);

@Riverpod(keepAlive: true)
UrlOpener urlOpener(Ref ref) =>
    (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

@Riverpod(keepAlive: true)
UpdateApi updateApi(Ref ref) => UpdateApi(manifestUrl: updateManifestUrl);

/// What this build is, as far as updating is concerned
/// (`core/update/app_version.dart`).
///
/// A provider rather than the constants themselves, because `flutter test` is
/// neither Android nor a released build: overriding this is the only way a
/// test gets to be one, and it is what makes the "is this release newer than
/// me" comparison testable at all.
@Riverpod(keepAlive: true)
({bool supported, String version, int versionCode}) installedBuild(Ref ref) => (
  supported: updatesSupported,
  version: appVersion,
  versionCode: appVersionCode,
);

/// Whether a newer APK has been published, and whether this device has already
/// waved it away.
///
/// Null release means "nothing to offer": this build is current, it is the web
/// app or a development build, or the check has never succeeded. The check is
/// deliberately quiet — it runs itself on first read and says nothing when it
/// fails, because nobody asked for it. Only [check] called by hand reports an
/// error, by letting it reach the `AsyncValue`.
@Riverpod(keepAlive: true)
class AvailableUpdate extends _$AvailableUpdate {
  @override
  Future<UpdateStatus> build() async {
    if (!ref.watch(installedBuildProvider).supported) return _nothing;

    final prefs = await SharedPreferences.getInstance();
    final checkedAt = prefs.getInt(_checkedAtPref) ?? 0;
    final now = ref.read(clockProvider)().millisecondsSinceEpoch;

    if (now - checkedAt < updateCheckInterval.inMilliseconds) {
      return _status(prefs, _cached(prefs));
    }
    // Falling back to the cache is the whole point of keeping one: a check that
    // could not run is not news, and an update found yesterday is still waiting.
    return _status(prefs, await _fetch(prefs, now) ?? _cached(prefs));
  }

  /// Asks now, whatever the last check said or when it happened. Unlike the
  /// automatic check this one surfaces its failure, because someone is
  /// watching for an answer — and it does not quietly answer out of the cache,
  /// which would show a stale release as a fresh one.
  Future<void> check() async {
    if (!ref.read(installedBuildProvider).supported) return;

    final known = state.value ?? _nothing;
    state = AsyncValue.data(_keeping(known, checking: true));

    try {
      final prefs = await SharedPreferences.getInstance();
      final now = ref.read(clockProvider)().millisecondsSinceEpoch;
      final release = await _fetch(prefs, now);
      state = AsyncValue.data(
        release == null
            ? _keeping(known, failure: const UpdateCheckFailed())
            : _status(prefs, release),
      );
    } catch (error) {
      state = AsyncValue.data(_keeping(known, failure: error));
    }
  }

  /// [known] again, with the check's own outcome written over it. What was
  /// already found stays found.
  UpdateStatus _keeping(
    UpdateStatus known, {
    bool checking = false,
    Object? failure,
  }) => (
    release: known.release,
    dismissed: known.dismissed,
    checking: checking,
    failure: failure,
  );

  /// Stops offering this release on the home screen. Settings still shows it:
  /// dismissing is "not now", not "never".
  Future<void> dismiss() async {
    final release = state.value?.release;
    if (release == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedPref, release.versionCode);
    state = AsyncValue.data((
      release: release,
      dismissed: true,
      checking: false,
      failure: null,
    ));
  }

  /// Hands the APK to the browser, which downloads it and offers to install
  /// it. The app never installs anything itself: that would mean holding the
  /// `REQUEST_INSTALL_PACKAGES` permission and a file provider to do what the
  /// browser already does well.
  ///
  /// False when nothing could be opened, which on Android means no browser
  /// took the URL.
  Future<bool> download() async {
    final release = state.value?.release;
    if (release == null) return false;
    final url = Uri.tryParse(release.url);
    if (url == null) return false;
    try {
      return await ref.read(urlOpenerProvider)(url);
    } catch (_) {
      return false;
    }
  }

  /// The manifest as it is right now, or null when it could not be read. Only
  /// a successful read is remembered — a failed one must not push the next
  /// check six hours out.
  Future<AppRelease?> _fetch(SharedPreferences prefs, int now) async {
    final release = await ref.read(updateApiProvider).latest();
    if (release == null) return null;
    await prefs.setString(_manifestPref, jsonEncode(release.toJson()));
    await prefs.setInt(_checkedAtPref, now);
    return release;
  }

  /// The last manifest that was read, so a phone with no signal still knows an
  /// update is waiting.
  AppRelease? _cached(SharedPreferences prefs) {
    final stored = prefs.getString(_manifestPref);
    if (stored == null) return null;
    try {
      return AppRelease.fromJson(jsonDecode(stored) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  UpdateStatus _status(SharedPreferences prefs, AppRelease? release) {
    if (release == null ||
        release.versionCode <= ref.read(installedBuildProvider).versionCode) {
      return _nothing;
    }
    return (
      release: release,
      dismissed: prefs.getInt(_dismissedPref) == release.versionCode,
      checking: false,
      failure: null,
    );
  }
}

/// A hand-triggered check that came back with nothing. Carries no detail
/// because [UpdateApi.latest] deliberately keeps none: to the person waiting,
/// an unreachable GitHub and a malformed manifest are the same answer.
class UpdateCheckFailed implements Exception {
  const UpdateCheckFailed();

  @override
  String toString() => 'Could not reach the update server.';
}
