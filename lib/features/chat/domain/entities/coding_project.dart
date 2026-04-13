import 'package:freezed_annotation/freezed_annotation.dart';

part 'coding_project.freezed.dart';
part 'coding_project.g.dart';

@freezed
abstract class CodingProject with _$CodingProject {
  const CodingProject._();

  const factory CodingProject({
    required String id,
    required String name,
    required String rootPath,
    String? securityScopedBookmark,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _CodingProject;

  factory CodingProject.fromJson(Map<String, dynamic> json) =>
      _$CodingProjectFromJson(json);

  String get normalizedRootPath => rootPath.trim();
}
