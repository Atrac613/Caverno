// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'turn_diff.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TurnDiffFile _$TurnDiffFileFromJson(Map<String, dynamic> json) =>
    _TurnDiffFile(
      filePath: json['filePath'] as String,
      isNewFile: json['isNewFile'] as bool? ?? false,
      isDeletedFile: json['isDeletedFile'] as bool? ?? false,
      isBinary: json['isBinary'] as bool? ?? false,
      isLargeFile: json['isLargeFile'] as bool? ?? false,
      isTruncated: json['isTruncated'] as bool? ?? false,
      isUntracked: json['isUntracked'] as bool? ?? false,
      linesAdded: (json['linesAdded'] as num?)?.toInt() ?? 0,
      linesRemoved: (json['linesRemoved'] as num?)?.toInt() ?? 0,
      unifiedPatch: json['unifiedPatch'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );

Map<String, dynamic> _$TurnDiffFileToJson(_TurnDiffFile instance) =>
    <String, dynamic>{
      'filePath': instance.filePath,
      'isNewFile': instance.isNewFile,
      'isDeletedFile': instance.isDeletedFile,
      'isBinary': instance.isBinary,
      'isLargeFile': instance.isLargeFile,
      'isTruncated': instance.isTruncated,
      'isUntracked': instance.isUntracked,
      'linesAdded': instance.linesAdded,
      'linesRemoved': instance.linesRemoved,
      'unifiedPatch': instance.unifiedPatch,
      'note': instance.note,
    };

_TurnDiff _$TurnDiffFromJson(Map<String, dynamic> json) => _TurnDiff(
  id: json['id'] as String,
  assistantMessageId: json['assistantMessageId'] as String,
  userPromptPreview: json['userPromptPreview'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  source:
      $enumDecodeNullable(_$TurnDiffSourceEnumMap, json['source']) ??
      TurnDiffSource.tool,
  files:
      (json['files'] as List<dynamic>?)
          ?.map((e) => TurnDiffFile.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <TurnDiffFile>[],
  filesChanged: (json['filesChanged'] as num?)?.toInt() ?? 0,
  linesAdded: (json['linesAdded'] as num?)?.toInt() ?? 0,
  linesRemoved: (json['linesRemoved'] as num?)?.toInt() ?? 0,
  changedFilePaths:
      (json['changedFilePaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
);

Map<String, dynamic> _$TurnDiffToJson(_TurnDiff instance) => <String, dynamic>{
  'id': instance.id,
  'assistantMessageId': instance.assistantMessageId,
  'userPromptPreview': instance.userPromptPreview,
  'timestamp': instance.timestamp.toIso8601String(),
  'source': _$TurnDiffSourceEnumMap[instance.source]!,
  'files': instance.files,
  'filesChanged': instance.filesChanged,
  'linesAdded': instance.linesAdded,
  'linesRemoved': instance.linesRemoved,
  'changedFilePaths': instance.changedFilePaths,
};

const _$TurnDiffSourceEnumMap = {
  TurnDiffSource.tool: 'tool',
  TurnDiffSource.git: 'git',
};
