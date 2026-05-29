import 'package:freezed_annotation/freezed_annotation.dart';

part 'skill.freezed.dart';
part 'skill.g.dart';

@freezed
abstract class Skill with _$Skill {
  const Skill._();

  const factory Skill({
    required String id,
    required String name,
    @Default('') String description,
    @Default('') String whenToUse,
    @Default('') String content,
    @Default(true) bool enabled,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Skill;

  factory Skill.fromJson(Map<String, dynamic> json) => _$SkillFromJson(json);

  String get normalizedName => name.trim();

  String get normalizedDescription => description.trim();

  String get normalizedWhenToUse => whenToUse.trim();

  String get normalizedContent => content.trim();

  bool get isUsable => enabled && normalizedName.isNotEmpty;
}
