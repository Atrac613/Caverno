import 'dart:convert';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/chat_turn_owner.dart';
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

/// Caches approval decisions independently for each assistant-turn owner.
///
/// This prevents the model from re-triggering the same confirmation flow
/// when it repeats an identical tool call after the user already approved
/// or denied it.
class ToolApprovalCache {
  // Shares the loop's non-semantic key set so approval caching and tool-loop
  // dedup cannot disagree on whether `reason` is meaningful.
  static const Set<String> _nonSemanticArgumentKeys =
      ToolCallExecutionPolicy.nonSemanticArgumentKeys;

  final Map<ChatTurnOwner, Map<String, ToolApprovalCacheEntry>>
  _entriesByOwner = {};
  final Map<ChatTurnOwner, OwnerToolApprovalCache> _scopesByOwner = {};

  ToolApprovalCacheEntry? lookup(
    ChatTurnOwner owner,
    String toolName,
    Map<String, dynamic> arguments, {
    String? stateFingerprint,
  }) {
    return _entriesByOwner[owner]?[_buildKey(
      toolName,
      arguments,
      stateFingerprint: stateFingerprint,
    )];
  }

  void rememberApproval(
    ChatTurnOwner owner,
    String toolName,
    Map<String, dynamic> arguments, {
    String? stateFingerprint,
  }) {
    _entriesFor(owner)[_buildKey(
          toolName,
          arguments,
          stateFingerprint: stateFingerprint,
        )] =
        const ToolApprovalCacheEntry.approved();
  }

  McpToolResult rememberDenial(
    ChatTurnOwner owner,
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result, {
    String? stateFingerprint,
  }) {
    _entriesFor(owner)[_buildKey(
      toolName,
      arguments,
      stateFingerprint: stateFingerprint,
    )] = ToolApprovalCacheEntry.denied(
      result,
    );
    return result;
  }

  OwnerToolApprovalCache forOwner(ChatTurnOwner owner) => _scopesByOwner
      .putIfAbsent(owner, () => OwnerToolApprovalCache._(this, owner));

  bool clear(ChatTurnOwner owner) {
    final scope = _scopesByOwner.remove(owner);
    scope?._dispose();
    return _entriesByOwner.remove(owner) != null || scope != null;
  }

  void clearAll() {
    for (final scope in _scopesByOwner.values) {
      scope._dispose();
    }
    _scopesByOwner.clear();
    _entriesByOwner.clear();
  }

  Map<String, ToolApprovalCacheEntry> _entriesFor(ChatTurnOwner owner) =>
      _entriesByOwner.putIfAbsent(owner, () => {});

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

/// Approval cache capability bound to one exact assistant-turn owner.
final class OwnerToolApprovalCache {
  OwnerToolApprovalCache._(this._cache, this.owner);

  final ToolApprovalCache _cache;
  final ChatTurnOwner owner;
  bool _isDisposed = false;

  ToolApprovalCacheEntry? lookup(
    String toolName,
    Map<String, dynamic> arguments, {
    String? stateFingerprint,
  }) => _isDisposed
      ? null
      : _cache.lookup(
          owner,
          toolName,
          arguments,
          stateFingerprint: stateFingerprint,
        );

  McpToolResult? lookupDenial(
    String toolName,
    Map<String, dynamic> arguments, {
    String? stateFingerprint,
  }) {
    final cached = lookup(
      toolName,
      arguments,
      stateFingerprint: stateFingerprint,
    );
    if (cached?.denialResult != null) {
      appLog(
        '[Tool] Reusing cached approval denial for $toolName: '
        '${jsonEncode(arguments)}',
      );
    }
    return cached?.denialResult;
  }

  McpToolResult rememberResult(
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result, {
    String? stateFingerprint,
  }) {
    if (!_isDisposed) {
      _cache.rememberApproval(
        owner,
        toolName,
        arguments,
        stateFingerprint: stateFingerprint,
      );
    }
    return result;
  }

  McpToolResult rememberDenial(
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result, {
    String? stateFingerprint,
  }) => _isDisposed
      ? result
      : _cache.rememberDenial(
          owner,
          toolName,
          arguments,
          result,
          stateFingerprint: stateFingerprint,
        );

  void _dispose() => _isDisposed = true;
}
