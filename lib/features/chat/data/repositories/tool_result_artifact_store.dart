import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/tool_call_info.dart';

final toolResultArtifactStoreProvider = Provider<ToolResultArtifactStore>(
  (ref) => ToolResultArtifactStore(),
);

class ToolResultArtifactStore {
  ToolResultArtifactStore({Directory? baseDirectory, DateTime Function()? now})
    : _baseDirectory = baseDirectory,
      _now = now ?? DateTime.now;

  static const defaultPersistenceThresholdChars = 50000;
  static const defaultRetention = Duration(days: 30);
  static const previewChars = 6000;

  final Directory? _baseDirectory;
  final DateTime Function() _now;

  Future<ToolResultInfo> persistIfLarge(
    ToolResultInfo toolResult, {
    String? conversationId,
    int thresholdChars = defaultPersistenceThresholdChars,
  }) async {
    if (toolResult.result.length <= thresholdChars ||
        _containsImagePayload(toolResult.result)) {
      return toolResult;
    }

    final directory = await _toolResultDirectory(conversationId);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/${_buildFileName(toolResult)}');
    await file.writeAsString(toolResult.result, flush: true);

    return ToolResultInfo(
      id: toolResult.id,
      name: toolResult.name,
      arguments: toolResult.arguments,
      result: _buildPersistedResultPayload(toolResult: toolResult, file: file),
    );
  }

  Future<List<ToolResultInfo>> persistLargeResults(
    List<ToolResultInfo> toolResults, {
    String? conversationId,
    int thresholdChars = defaultPersistenceThresholdChars,
  }) async {
    final persisted = <ToolResultInfo>[];
    for (final toolResult in toolResults) {
      persisted.add(
        await persistIfLarge(
          toolResult,
          conversationId: conversationId,
          thresholdChars: thresholdChars,
        ),
      );
    }
    return persisted;
  }

  Future<void> deleteConversationArtifacts(String? conversationId) async {
    final trimmed = conversationId?.trim() ?? '';
    if (trimmed.isEmpty) {
      return;
    }

    final directory = await _toolResultDirectory(trimmed);
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> deleteAllArtifacts() async {
    final root = await _toolResultsRootDirectory();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }

  Future<int> deleteArtifactsOlderThan(Duration maxAge) async {
    if (maxAge.isNegative) {
      return deleteArtifactsOlderThan(Duration.zero);
    }

    final root = await _toolResultsRootDirectory();
    if (!root.existsSync()) {
      return 0;
    }

    final cutoff = _now().subtract(maxAge);
    var deletedCount = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final modifiedAt = await entity.lastModified();
      if (modifiedAt.isAfter(cutoff)) {
        continue;
      }
      await entity.delete();
      deletedCount += 1;
    }

    await _deleteEmptyDirectories(root);
    return deletedCount;
  }

  Future<Directory> _toolResultDirectory(String? conversationId) async {
    final root = await _toolResultsRootDirectory();
    final session = _safePathSegment(
      conversationId == null || conversationId.trim().isEmpty
          ? 'active-session'
          : conversationId,
    );
    return Directory('${root.path}${Platform.pathSeparator}$session');
  }

  Future<Directory> _toolResultsRootDirectory() async {
    final root = _baseDirectory ?? await getApplicationSupportDirectory();
    return Directory('${root.path}${Platform.pathSeparator}tool-results');
  }

  static Future<void> _deleteEmptyDirectories(Directory root) async {
    final directories = <Directory>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        directories.add(entity);
      }
    }

    directories.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in directories) {
      if (!directory.existsSync()) {
        continue;
      }
      if (directory.listSync(followLinks: false).isEmpty) {
        await directory.delete();
      }
    }
  }

  String _buildFileName(ToolResultInfo toolResult) {
    final timestamp = _now().toUtc().toIso8601String().replaceAll(':', '-');
    final toolName = _safePathSegment(toolResult.name);
    final callId = _safePathSegment(toolResult.id);
    final extension = _looksLikeJson(toolResult.result) ? 'json' : 'txt';
    return '${timestamp}_${toolName}_${callId}_full.$extension';
  }

  String _buildPersistedResultPayload({
    required ToolResultInfo toolResult,
    required File file,
  }) {
    final preview = _preview(toolResult.result);
    return jsonEncode({
      'persisted_output': true,
      'file_path': file.absolute.path,
      'tool': toolResult.name,
      'original_char_count': toolResult.result.length,
      'preview_char_count': preview.length,
      'preview': preview,
      'instruction':
          'The full tool result was saved to file_path. Use read_file on that path if exact omitted content is needed.',
    });
  }

  static String _preview(String value) {
    if (value.length <= previewChars) {
      return value;
    }
    final headChars = (previewChars * 0.7).floor();
    final tailChars = previewChars - headChars;
    final omitted = value.length - previewChars;
    return '${value.substring(0, headChars)}\n\n[Persisted output preview omitted $omitted character(s).]\n\n${value.substring(value.length - tailChars)}';
  }

  static bool _containsImagePayload(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) return false;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map && decoded['imageBase64'] is String;
    } catch (_) {
      return false;
    }
  }

  static bool _looksLikeJson(String value) {
    final trimmed = value.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  static String _safePathSegment(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (sanitized.isEmpty) {
      return 'item';
    }
    return sanitized.substring(0, math.min(sanitized.length, 80));
  }
}
