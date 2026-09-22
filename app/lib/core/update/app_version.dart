import 'package:flutter/foundation.dart';

/// What this build calls itself, stamped in at build time.
///
/// `scripts/ci.sh apk` reads both out of `pubspec.yaml` and passes them as
/// `--dart-define`s, so they are the same pair Gradle stamps into the APK's
/// manifest — there is no second place to keep in step.
///
/// A build that did not come through that script (`flutter run`, `flutter test`,
/// `dart run tool/build_web.dart`) leaves [appVersionCode] at 0, and that is what
/// switches the update check off: a build with no released version cannot be
/// behind one.
const appVersion = String.fromEnvironment('APP_VERSION');
const appVersionCode = int.fromEnvironment('APP_VERSION_CODE');

/// Where the app looks for the newest release (README, "Releasing the Android
/// app"). `scripts/ci.sh apk` passes this too, derived from the git remote, so
/// the APK and the manifest published beside it can never point at different
/// repositories; the default is what a hand-run `flutter build apk` gets.
const updateManifestUrl = String.fromEnvironment(
  'UPDATE_MANIFEST_URL',
  defaultValue: 'https://github.com/AnisAbdellatif/FazouraParty/releases/latest/download/android.json',
);

/// Whether this build can be updated in place.
///
/// Only the Android APK can: the web app is a PWA and replaces itself through
/// the service worker (`app/tool/build_web.dart`), and a development build has
/// no version to compare against. `kIsWeb` is a compile-time constant, so the
/// whole check folds away in the web bundle.
bool get updatesSupported =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    appVersionCode > 0;
