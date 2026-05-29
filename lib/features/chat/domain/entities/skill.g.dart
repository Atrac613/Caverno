// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skill.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Skill _$SkillFromJson(Map<String, dynamic> json) => _Skill(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String? ?? '',
  whenToUse: json['whenToUse'] as String? ?? '',
  content: json['content'] as String? ?? '',
  enabled: json['enabled'] as bool? ?? true,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$SkillToJson(_Skill instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'whenToUse': instance.whenToUse,
  'content': instance.content,
  'enabled': instance.enabled,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};
