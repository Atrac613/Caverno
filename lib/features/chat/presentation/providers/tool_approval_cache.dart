import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/tool_call_execution_policy.dart';

/// Cached approval decision for one normalized tool call.
class ToolApprovalCacheEntry {
  const ToolApprovalCacheEntry.approved()
    : isApproved = true,
      denialResult = null;

  const ToolApprovalCacheEntry.denied(this.denialResult) : isApproved = false;

  final bool isApproved;
  final McpToolResult? denialResult;
}

/// Caches approval decisions within a single assistant turn.
///
/// This prevents the model from re-triggering the same confirmation flow
/// when it repeats an identical tool call after the user already approved
/// or denied it.
class ToolApprovalCache {
  // Shares the loop's non-semantic key set so approval caching and tool-loop
  // dedup cannot disagree on whether `reason` is meaningful.
  static const Set<String> _nonSemanticArgumentKeys =
      ToolCallExecutionPolicy.nonSemanticArgumentKeys;

  final Map<String, ToolApprovalCacheEntry> _entriesByKey = {};

  ToolApprovalCacheEntry? lookup(
    String toolName,
    Map<String, dynamic> arguments, {
    String? stateFingerprint,
  }) {
    return _entriesByKey[_buildKey(
      toolName,
      arguments,
      stateFingerprint: stateFingerprint,
    )];
  }

  void rememberApproval(
    String toolName,
    Map<String, dynamic> arguments, {
    String? stateFingerprint,
  }) {
    _entriesByKey[_buildKey(
          toolName,
          arguments,
          stateFingerprint: stateFingerprint,
        )] =
        const ToolApprovalCacheEntry.approved();
  }

  McpToolResult rememberDenial(
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result, {
    String? stateFingerprint,
  }) {
    _entriesByKey[_buildKey(
      toolName,
      arguments,
      stateFingerprint: stateFingerprint,
    )] = ToolApprovalCacheEntry.denied(
      result,
    );
    return result;
  }

  void clear() => _entriesByKey.clear();

  String _buildKey(
    String toolName,
    Map<String, dynamic> arguments, {
    String? stateFingerprint,
  }) {
    final normalizedArguments = _normalizeValue(arguments);
    return jsonEncode({
      'tool': toolName,
      'arguments': normalizedArguments,
      'state': ?stateFingerprint,
    });
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
