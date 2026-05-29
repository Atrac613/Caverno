import 'package:freezed_annotation/freezed_annotation.dart';

part 'turn_diff.freezed.dart';
part 'turn_diff.g.dart';

enum TurnDiffSource { tool, git }

@freezed
abstract class TurnDiffFile with _$TurnDiffFile {
  const TurnDiffFile._();

  const factory TurnDiffFile({
    required String filePath,
    @Default(false) bool isNewFile,
    @Default(false) bool isDeletedFile,
    @Default(false) bool isBinary,
    @Default(false) bool isLargeFile,
    @Default(false) bool isTruncated,
    @Default(false) bool isUntracked,
    @Default(0) int linesAdded,
    @Default(0) int linesRemoved,
    @Default('') String unifiedPatch,
    @Default('') String note,
  }) = _TurnDiffFile;

  factory TurnDiffFile.fromJson(Map<String, dynamic> json) =>
      _$TurnDiffFileFromJson(json);

  bool get hasRenderablePatch =>
      unifiedPatch.trim().isNotEmpty && !isBinary && !isLargeFile;

  bool get hasChanges =>
      linesAdded > 0 ||
      linesRemoved > 0 ||
      isNewFile ||
      isDeletedFile ||
      isUntracked ||
      isBinary ||
      isLargeFile ||
      unifiedPatch.trim().isNotEmpty;
}

@freezed
abstract class TurnDiff with _$TurnDiff {
  const TurnDiff._();

  const factory TurnDiff({
    required String id,
    required String assistantMessageId,
    required String userPromptPreview,
    required DateTime timestamp,
    @Default(TurnDiffSource.tool) TurnDiffSource source,
    @Default(<TurnDiffFile>[]) List<TurnDiffFile> files,
    @Default(0) int filesChanged,
    @Default(0) int linesAdded,
    @Default(0) int linesRemoved,
    @Default(<String>[]) List<String> changedFilePaths,
  }) = _TurnDiff;

  factory TurnDiff.fromJson(Map<String, dynamic> json) =>
      _$TurnDiffFromJson(json);

  bool get hasChanges =>
      filesChanged > 0 ||
      linesAdded > 0 ||
      linesRemoved > 0 ||
      files.any((file) => file.hasChanges);

  String get summaryLabel =>
      '$filesChanged ${filesChanged == 1 ? 'file' : 'files'} changed '
      '+$linesAdded -$linesRemoved';
}
