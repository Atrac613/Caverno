// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coding_project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CodingProject _$CodingProjectFromJson(Map<String, dynamic> json) =>
    _CodingProject(
      id: json['id'] as String,
      name: json['name'] as String,
      rootPath: json['rootPath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$CodingProjectToJson(_CodingProject instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'rootPath': instance.rootPath,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
