import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';

/// Caches approval-backed tool results within a single assistant turn.
///
/// This prevents the model from re-triggering the same confirmation flow
/// when it repeats an identical tool call after the user already approved
/// or denied it.
class ToolApprovalCache {
  static const Set<String> _nonSemanticArgumentKeys = {'reason'};

  final Map<String, McpToolResult> _resultsByKey = {};

  McpToolResult? lookup(String toolName, Map<String, dynamic> arguments) {
    return _resultsByKey[_buildKey(toolName, arguments)];
  }

  McpToolResult remember(
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result,
  ) {
    _resultsByKey[_buildKey(toolName, arguments)] = result;
    return result;
  }

  void clear() => _resultsByKey.clear();

  String _buildKey(String toolName, Map<String, dynamic> arguments) {
    final normalizedArguments = _normalizeValue(arguments);
    return '$toolName:${jsonEncode(normalizedArguments)}';
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return <String, dynamic>{
        for (final entry in entries)
          if (!_nonSemanticArgumentKeys.contains(entry.key.toString()))
            entry.key.toString(): _normalizeValue(entry.value),
      };
    }

    if (value is List) {
      return value.map(_normalizeValue).toList(growable: false);
    }

    if (value == null || value is num || value is bool || value is String) {
      return value;
    }

    return value.toString();
  }
}
