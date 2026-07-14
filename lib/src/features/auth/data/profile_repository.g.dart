// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider für ProfileRepository

@ProviderFor(profileRepository)
final profileRepositoryProvider = ProfileRepositoryProvider._();

/// Provider für ProfileRepository

final class ProfileRepositoryProvider
    extends
        $FunctionalProvider<
          ProfileRepository,
          ProfileRepository,
          ProfileRepository
        >
    with $Provider<ProfileRepository> {
  /// Provider für ProfileRepository
  ProfileRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileRepositoryHash();

  @$internal
  @override
  $ProviderElement<ProfileRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProfileRepository create(Ref ref) {
    return profileRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProfileRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProfileRepository>(value),
    );
  }
}

String _$profileRepositoryHash() => r'3aa54b7cf9d7220e922d36cee297e850f9941d06';

@ProviderFor(childrenList)
final childrenListProvider = ChildrenListProvider._();

final class ChildrenListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ChildModel>>,
          List<ChildModel>,
          Stream<List<ChildModel>>
        >
    with $FutureModifier<List<ChildModel>>, $StreamProvider<List<ChildModel>> {
  ChildrenListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'childrenListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$childrenListHash();

  @$internal
  @override
  $StreamProviderElement<List<ChildModel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ChildModel>> create(Ref ref) {
    return childrenList(ref);
  }
}

String _$childrenListHash() => r'e6f7c79e450f4a3865ac85161c98630b1c29f3d2';
