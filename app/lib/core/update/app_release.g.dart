// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_release.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AppRelease _$AppReleaseFromJson(Map<String, dynamic> json) => _AppRelease(
  version: json['version'] as String,
  versionCode: (json['version_code'] as num).toInt(),
  url: json['url'] as String,
  size: (json['size'] as num?)?.toInt(),
  sha256: json['sha256'] as String?,
  notes: json['notes'] as String?,
);

Map<String, dynamic> _$AppReleaseToJson(_AppRelease instance) =>
    <String, dynamic>{
      'version': instance.version,
      'version_code': instance.versionCode,
      'url': instance.url,
      'size': instance.size,
      'sha256': instance.sha256,
      'notes': instance.notes,
    };
