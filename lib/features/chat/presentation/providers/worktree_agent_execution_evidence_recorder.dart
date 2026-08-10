import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/worktree_agent_task.dart';

class WorktreeAgentExecutionEvidenceSnapshot {
  const WorktreeAgentExecutionEvidenceSnapshot({
    required this.changedFiles,
    required this.truncated,
  });

  final List<WorktreeAgentChangedFileEvidence> changedFiles;
  final bool truncated;
}

class WorktreeAgentExecutionEvidenceRecorder {
  WorktreeAgentExecutionEvidenceRecorder({
    required String worktreePath,
    this.maxFiles = 32,
    this.maxContentBytes = 64 * 1024,
    this.maxTotalContentBytes = 256 * 1024,
  }) : assert(maxFiles > 0),
       assert(maxContentBytes > 0),
       assert(maxTotalContentBytes > 0),
       _worktreePath = path.normalize(path.absolute(worktreePath));

  final int maxFiles;
  final int maxContentBytes;
  final int maxTotalContentBytes;
  final String _worktreePath;
  final Set<String> _changedPaths = <String>{};

  void record(McpToolResult result) {
    if (!result.isSuccess) return;
    final mutations = result.outcome?.fileMutations ?? const [];
    for (final mutation in mutations) {
      if (mutation.changed != true) continue;
      final rawPath = mutation.path.trim();
      if (rawPath.isEmpty) continue;
      final absolutePath = path.normalize(
        path.isAbsolute(rawPath) ? rawPath : path.join(_worktreePath, rawPath),
      );
      if (!path.isWithin(_worktreePath, absolutePath)) continue;
      _changedPaths.add(absolutePath);
    }
  }

  Future<WorktreeAgentExecutionEvidenceSnapshot> capture() async {
    final paths = _changedPaths.toList()..sort();
    final selectedPaths = paths.take(maxFiles);
    final changedFiles = <WorktreeAgentChangedFileEvidence>[];
    var remainingContentBytes = maxTotalContentBytes;
    var contentWasTruncated = false;
    for (final absolutePath in selectedPaths) {
      final relativePath = path
          .relative(absolutePath, from: _worktreePath)
          .replaceAll(path.separator, '/');
      try {
        final type = await FileSystemEntity.type(
          absolutePath,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          changedFiles.add(
            WorktreeAgentChangedFileEvidence(path: relativePath, deleted: true),
          );
          continue;
        }
        if (type != FileSystemEntityType.file) continue;
        final bytes = await File(absolutePath).readAsBytes();
        final visibleLimit = maxContentBytes < remainingContentBytes
            ? maxContentBytes
            : remainingContentBytes;
        final truncated = bytes.length > visibleLimit;
        final visibleBytes = truncated ? bytes.sublist(0, visibleLimit) : bytes;
        remainingContentBytes -= visibleBytes.length;
        contentWasTruncated = contentWasTruncated || truncated;
        changedFiles.add(
          WorktreeAgentChangedFileEvidence(
            path: relativePath,
            content: utf8.decode(visibleBytes, allowMalformed: true),
            contentHash: sha256.convert(bytes).toString(),
            byteSize: bytes.length,
            truncated: truncated,
          ),
        );
      } on FileSystemException {
        continue;
      }
    }
    return WorktreeAgentExecutionEvidenceSnapshot(
      changedFiles: List.unmodifiable(changedFiles),
      truncated: paths.length > maxFiles || contentWasTruncated,
    );
  }
}
