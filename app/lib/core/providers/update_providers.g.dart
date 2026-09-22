// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(urlOpener)
final urlOpenerProvider = UrlOpenerProvider._();

final class UrlOpenerProvider
    extends $FunctionalProvider<UrlOpener, UrlOpener, UrlOpener>
    with $Provider<UrlOpener> {
  UrlOpenerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'urlOpenerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$urlOpenerHash();

  @$internal
  @override
  $ProviderElement<UrlOpener> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UrlOpener create(Ref ref) {
    return urlOpener(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UrlOpener value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UrlOpener>(value),
    );
  }
}

String _$urlOpenerHash() => r'd2502ceeca87dbac1517b37cb66a60198f971d01';

@ProviderFor(updateApi)
final updateApiProvider = UpdateApiProvider._();

final class UpdateApiProvider
    extends $FunctionalProvider<UpdateApi, UpdateApi, UpdateApi>
    with $Provider<UpdateApi> {
  UpdateApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updateApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateApiHash();

  @$internal
  @override
  $ProviderElement<UpdateApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UpdateApi create(Ref ref) {
    return updateApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpdateApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpdateApi>(value),
    );
  }
}

String _$updateApiHash() => r'b8c92baeeb2d262c4176fed795caabeb6bdc2d31';

/// What this build is, as far as updating is concerned
/// (`core/update/app_version.dart`).
///
/// A provider rather than the constants themselves, because `flutter test` is
/// neither Android nor a released build: overriding this is the only way a
/// test gets to be one, and it is what makes the "is this release newer than
/// me" comparison testable at all.

@ProviderFor(installedBuild)
final installedBuildProvider = InstalledBuildProvider._();

/// What this build is, as far as updating is concerned
/// (`core/update/app_version.dart`).
///
/// A provider rather than the constants themselves, because `flutter test` is
/// neither Android nor a released build: overriding this is the only way a
/// test gets to be one, and it is what makes the "is this release newer than
/// me" comparison testable at all.

final class InstalledBuildProvider
    extends
        $FunctionalProvider<
          ({bool supported, String version, int versionCode}),
          ({bool supported, String version, int versionCode}),
          ({bool supported, String version, int versionCode})
        >
    with $Provider<({bool supported, String version, int versionCode})> {
  /// What this build is, as far as updating is concerned
  /// (`core/update/app_version.dart`).
  ///
  /// A provider rather than the constants themselves, because `flutter test` is
  /// neither Android nor a released build: overriding this is the only way a
  /// test gets to be one, and it is what makes the "is this release newer than
  /// me" comparison testable at all.
  InstalledBuildProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'installedBuildProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$installedBuildHash();

  @$internal
  @override
  $ProviderElement<({bool supported, String version, int versionCode})>
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  ({bool supported, String version, int versionCode}) create(Ref ref) {
    return installedBuild(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    ({bool supported, String version, int versionCode}) value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<
            ({bool supported, String version, int versionCode})
          >(value),
    );
  }
}

String _$installedBuildHash() => r'b0a4cc4e7b0350b931e8dd069e059f72389b3ee7';

/// Whether a newer APK has been published, and whether this device has already
/// waved it away.
///
/// Null release means "nothing to offer": this build is current, it is the web
/// app or a development build, or the check has never succeeded. The check is
/// deliberately quiet — it runs itself on first read and says nothing when it
/// fails, because nobody asked for it. Only [check] called by hand reports an
/// error, by letting it reach the `AsyncValue`.

@ProviderFor(AvailableUpdate)
final availableUpdateProvider = AvailableUpdateProvider._();

/// Whether a newer APK has been published, and whether this device has already
/// waved it away.
///
/// Null release means "nothing to offer": this build is current, it is the web
/// app or a development build, or the check has never succeeded. The check is
/// deliberately quiet — it runs itself on first read and says nothing when it
/// fails, because nobody asked for it. Only [check] called by hand reports an
/// error, by letting it reach the `AsyncValue`.
final class AvailableUpdateProvider
    extends $AsyncNotifierProvider<AvailableUpdate, UpdateStatus> {
  /// Whether a newer APK has been published, and whether this device has already
  /// waved it away.
  ///
  /// Null release means "nothing to offer": this build is current, it is the web
  /// app or a development build, or the check has never succeeded. The check is
  /// deliberately quiet — it runs itself on first read and says nothing when it
  /// fails, because nobody asked for it. Only [check] called by hand reports an
  /// error, by letting it reach the `AsyncValue`.
  AvailableUpdateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableUpdateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableUpdateHash();

  @$internal
  @override
  AvailableUpdate create() => AvailableUpdate();
}

String _$availableUpdateHash() => r'b5e728979b906be4a21ee7d2ed33ad8660138d47';

/// Whether a newer APK has been published, and whether this device has already
/// waved it away.
///
/// Null release means "nothing to offer": this build is current, it is the web
/// app or a development build, or the check has never succeeded. The check is
/// deliberately quiet — it runs itself on first read and says nothing when it
/// fails, because nobody asked for it. Only [check] called by hand reports an
/// error, by letting it reach the `AsyncValue`.

abstract class _$AvailableUpdate extends $AsyncNotifier<UpdateStatus> {
  FutureOr<UpdateStatus> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<UpdateStatus>, UpdateStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<UpdateStatus>, UpdateStatus>,
              AsyncValue<UpdateStatus>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
