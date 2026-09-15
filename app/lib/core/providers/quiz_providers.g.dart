// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'quiz_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// This device's secret publisher key, created once and kept in local
/// storage. Not an account: it only lets this device update or unpublish the
/// quizzes it published.

@ProviderFor(ownerKey)
final ownerKeyProvider = OwnerKeyProvider._();

/// This device's secret publisher key, created once and kept in local
/// storage. Not an account: it only lets this device update or unpublish the
/// quizzes it published.

final class OwnerKeyProvider
    extends $FunctionalProvider<AsyncValue<String>, String, FutureOr<String>>
    with $FutureModifier<String>, $FutureProvider<String> {
  /// This device's secret publisher key, created once and kept in local
  /// storage. Not an account: it only lets this device update or unpublish the
  /// quizzes it published.
  OwnerKeyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownerKeyProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownerKeyHash();

  @$internal
  @override
  $FutureProviderElement<String> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String> create(Ref ref) {
    return ownerKey(ref);
  }
}

String _$ownerKeyHash() => r'e7214a5236c7853c83be621b4372637b1e7e25eb';

/// Gallery picker (file chooser on web). Overridden in tests.

@ProviderFor(photoPicker)
final photoPickerProvider = PhotoPickerProvider._();

/// Gallery picker (file chooser on web). Overridden in tests.

final class PhotoPickerProvider
    extends $FunctionalProvider<PhotoPicker, PhotoPicker, PhotoPicker>
    with $Provider<PhotoPicker> {
  /// Gallery picker (file chooser on web). Overridden in tests.
  PhotoPickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoPickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoPickerHash();

  @$internal
  @override
  $ProviderElement<PhotoPicker> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoPicker create(Ref ref) {
    return photoPicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoPicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoPicker>(value),
    );
  }
}

String _$photoPickerHash() => r'a19a8539e15a7e6fb01edd2fdba796ba73886a79';

@ProviderFor(quizApi)
final quizApiProvider = QuizApiProvider._();

final class QuizApiProvider
    extends $FunctionalProvider<QuizApi, QuizApi, QuizApi>
    with $Provider<QuizApi> {
  QuizApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'quizApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$quizApiHash();

  @$internal
  @override
  $ProviderElement<QuizApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  QuizApi create(Ref ref) {
    return quizApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(QuizApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<QuizApi>(value),
    );
  }
}

String _$quizApiHash() => r'4bca49f6386e49dbb66aaf46b3755e5c5111a02b';

/// On-device database. Overridden with an in-memory one in tests.

@ProviderFor(localDatabase)
final localDatabaseProvider = LocalDatabaseProvider._();

/// On-device database. Overridden with an in-memory one in tests.

final class LocalDatabaseProvider
    extends
        $FunctionalProvider<AsyncValue<Database>, Database, FutureOr<Database>>
    with $FutureModifier<Database>, $FutureProvider<Database> {
  /// On-device database. Overridden with an in-memory one in tests.
  LocalDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localDatabaseHash();

  @$internal
  @override
  $FutureProviderElement<Database> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Database> create(Ref ref) {
    return localDatabase(ref);
  }
}

String _$localDatabaseHash() => r'2513de8fb699d94abcdc8e01343dea11091a6cb3';

@ProviderFor(quizLibrary)
final quizLibraryProvider = QuizLibraryProvider._();

final class QuizLibraryProvider
    extends $FunctionalProvider<QuizLibrary, QuizLibrary, QuizLibrary>
    with $Provider<QuizLibrary> {
  QuizLibraryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'quizLibraryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$quizLibraryHash();

  @$internal
  @override
  $ProviderElement<QuizLibrary> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  QuizLibrary create(Ref ref) {
    return quizLibrary(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(QuizLibrary value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<QuizLibrary>(value),
    );
  }
}

String _$quizLibraryHash() => r'4fd2a6a48387a26d3ac5e6817b09dc72db45de9c';
