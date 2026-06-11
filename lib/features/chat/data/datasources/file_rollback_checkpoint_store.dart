import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'filesystem_tools.dart';

class FileRollbackPreview {
  const FileRollbackPreview({
    required this.path,
    required this.preview,
    required this.summary,
  });

  final String path;
  final String preview;
  final String summary;
}

class FileTurnRollbackPreview {
  const FileTurnRollbackPreview({
    required this.turnId,
    required this.paths,
    required this.preview,
    required this.summary,
  });

  final String turnId;
  final List<String> paths;
  final String preview;
  final String summary;
}

class FileRollbackCheckpointStore {
  final List<_FileRollbackEntry> _fileRollbackStack = [];
  final List<_FileTurnCheckpoint> _fileTurnCheckpointStack = [];
  _FileTurnCheckpoint? _activeFileTurnCheckpoint;

  void push(TextFileSnapshot snapshot) {
    if (snapshot.exists && snapshot.error != null) {
      return;
    }

    final entry = _FileRollbackEntry(
      path: snapshot.path,
      existedBefore: snapshot.exists,
      previousContent: snapshot.content,
    );
    _fileRollbackStack.add(entry);
    _activeFileTurnCheckpoint?.addFirstEntryForPath(entry);

    if (_fileRollbackStack.length > 20) {
      _fileRollbackStack.removeAt(0);
    }
  }

  Future<FileRollbackPreview?> previewLastFileRollbackChange() async {
    final entry = _fileRollbackStack.isEmpty ? null : _fileRollbackStack.last;
    if (entry == null) return null;

    final currentSnapshot = await FilesystemTools.captureTextSnapshot(
      entry.path,
    );
    final summary = entry.existedBefore
        ? 'Restore the previous contents of this file.'
        : 'Delete the newly created file.';

    if (currentSnapshot.error != null) {
      return FileRollbackPreview(
        path: entry.path,
        preview:
            'Diff preview unavailable: ${currentSnapshot.error}\n\n'
            'Rollback target: ${entry.path}\n'
            '$summary',
        summary: summary,
      );
    }

    return FileRollbackPreview(
      path: entry.path,
      preview: FilesystemTools.buildUnifiedDiff(
        path: entry.path,
        oldContent: currentSnapshot.exists ? currentSnapshot.content : null,
        newContent: entry.existedBefore ? (entry.previousContent ?? '') : null,
      ),
      summary: summary,
    );
  }

  Future<McpToolResult> rollbackLastFileChange({
    required String toolName,
  }) async {
    final entry = _fileRollbackStack.isEmpty
        ? null
        : _fileRollbackStack.removeLast();
    if (entry == null) {
      return McpToolResult(
        toolName: toolName,
        result: '',
        isSuccess: false,
        errorMessage: 'No recent file change is available to roll back',
      );
    }

    final result = await FilesystemTools.restoreTextSnapshot(
      path: entry.path,
      existedBefore: entry.existedBefore,
      content: entry.previousContent,
    );
    if (!_isFilesystemPayloadSuccess(result)) {
      _fileRollbackStack.add(entry);
      return McpToolResult(
        toolName: toolName,
        result: result,
        isSuccess: false,
        errorMessage: 'Failed to roll back the last file change',
      );
    }

    return McpToolResult(toolName: toolName, result: result, isSuccess: true);
  }

  void beginFileTurnCheckpoint(String turnId) {
    final normalizedTurnId = turnId.trim();
    if (normalizedTurnId.isEmpty) {
      return;
    }
    if (_activeFileTurnCheckpoint?.turnId == normalizedTurnId) {
      return;
    }
    endFileTurnCheckpoint();
    _activeFileTurnCheckpoint = _FileTurnCheckpoint(
      turnId: normalizedTurnId,
      entries: <_FileRollbackEntry>[],
    );
  }

  void endFileTurnCheckpoint() {
    final checkpoint = _activeFileTurnCheckpoint;
    _activeFileTurnCheckpoint = null;
    if (checkpoint == null || checkpoint.entries.isEmpty) {
      return;
    }

    _fileTurnCheckpointStack.add(checkpoint.toImmutable());
    if (_fileTurnCheckpointStack.length > 10) {
      _fileTurnCheckpointStack.removeAt(0);
    }
  }

  Future<FileTurnRollbackPreview?> previewLastFileTurnCheckpoint() async {
    final checkpoint = _fileTurnCheckpointStack.isEmpty
        ? null
        : _fileTurnCheckpointStack.last;
    if (checkpoint == null) return null;

    final previews = <String>[];
    for (final entry in checkpoint.entries) {
      previews.add(await _buildPreviewForEntry(entry));
    }

    final count = checkpoint.entries.length;
    return FileTurnRollbackPreview(
      turnId: checkpoint.turnId,
      paths: checkpoint.entries
          .map((entry) => entry.path)
          .toList(growable: false),
      preview: previews.join('\n\n'),
      summary: count == 1
          ? 'Revert the last agent turn file change.'
          : 'Revert $count file changes from the last agent turn.',
    );
  }

  Future<McpToolResult> rollbackLastFileTurnCheckpoint() async {
    final checkpoint = _fileTurnCheckpointStack.isEmpty
        ? null
        : _fileTurnCheckpointStack.removeLast();
    if (checkpoint == null) {
      return const McpToolResult(
        toolName: 'rollback_last_turn_file_changes',
        result: '',
        isSuccess: false,
        errorMessage:
            'No recent turn file checkpoint is available to roll back',
      );
    }

    final restored = <Map<String, Object?>>[];
    for (final entry in checkpoint.entries.reversed) {
      final result = await FilesystemTools.restoreTextSnapshot(
        path: entry.path,
        existedBefore: entry.existedBefore,
        content: entry.previousContent,
      );
      final ok = _isFilesystemPayloadSuccess(result);
      restored.add({
        'path': entry.path,
        'ok': ok,
        'result': _tryDecodeJson(result) ?? result,
      });
      if (!ok) {
        _fileTurnCheckpointStack.add(checkpoint);
        return McpToolResult(
          toolName: 'rollback_last_turn_file_changes',
          result: jsonEncode({
            'ok': false,
            'turn_id': checkpoint.turnId,
            'restored': restored.reversed.toList(growable: false),
          }),
          isSuccess: false,
          errorMessage: 'Failed to roll back the last turn file checkpoint',
        );
      }
    }

    return McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: jsonEncode({
        'ok': true,
        'turn_id': checkpoint.turnId,
        'restored': restored.reversed.toList(growable: false),
      }),
      isSuccess: true,
    );
  }

  Future<String> _buildPreviewForEntry(_FileRollbackEntry entry) async {
    final currentSnapshot = await FilesystemTools.captureTextSnapshot(
      entry.path,
    );
    final summary = entry.existedBefore
        ? 'Restore the previous contents of this file.'
        : 'Delete the newly created file.';
    if (currentSnapshot.error != null) {
      return 'Diff preview unavailable: ${currentSnapshot.error}\n\n'
          'Rollback target: ${entry.path}\n'
          '$summary';
    }
    return FilesystemTools.buildUnifiedDiff(
      path: entry.path,
      oldContent: currentSnapshot.exists ? currentSnapshot.content : null,
      newContent: entry.existedBefore ? (entry.previousContent ?? '') : null,
    );
  }

  bool _isFilesystemPayloadSuccess(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is! Map<String, dynamic> || decoded['error'] == null;
    } catch (_) {
      return true;
    }
  }

  Object? _tryDecodeJson(String payload) {
    try {
      return jsonDecode(payload);
    } catch (_) {
      return null;
    }
  }
}

class _FileRollbackEntry {
  const _FileRollbackEntry({
    required this.path,
    required this.existedBefore,
    this.previousContent,
  });

  final String path;
  final bool existedBefore;
  final String? previousContent;
}

class _FileTurnCheckpoint {
  _FileTurnCheckpoint({required this.turnId, required this.entries});

  final String turnId;
  final List<_FileRollbackEntry> entries;

  void addFirstEntryForPath(_FileRollbackEntry entry) {
    if (entries.any((existing) => existing.path == entry.path)) {
      return;
    }
    entries.add(entry);
  }

  _FileTurnCheckpoint toImmutable() {
    return _FileTurnCheckpoint(
      turnId: turnId,
      entries: List<_FileRollbackEntry>.unmodifiable(entries),
    );
  }
}
