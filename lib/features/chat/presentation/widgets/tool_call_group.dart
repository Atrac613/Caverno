import 'dart:convert';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Arguments whose value best describes what a call acted on, most specific
/// first. Drawn from the real built-in schemas: the filesystem tools key on
/// `path`, the local-command tools on `command` / `working_directory` /
/// `test_path` / `job_id`.
const List<String> _salientArgumentKeys = <String>[
  'command',
  // Search terms outrank the path they search: `grep · lib` says far less
  // than `grep · emitRuntimeToolLifecycle`.
  'pattern',
  'query',
  'expression',
  'path',
  'file_path',
  'test_path',
  'url',
  'job_id',
];

/// Arguments that describe the call's *intent* rather than its target. They are
/// approval-dialog copy, so they make a poor headline suffix and are skipped by
/// the generic fallback.
const Set<String> _nonTargetArgumentKeys = <String>{'reason', 'label'};

const int _headlineArgumentMaxLength = 60;

/// Icon for [toolName], falling back to a generic tool glyph.
IconData toolIconFor(String toolName) {
  switch (toolName.toLowerCase()) {
    case 'web_search':
      return Icons.search;
    case 'get_current_datetime':
      return Icons.schedule;
    case 'memory_update':
      return Icons.psychology_alt_outlined;
    case 'calculator':
      return Icons.calculate;
    case 'code':
      return Icons.code;
    case 'rollback_last_file_change':
      return Icons.undo_rounded;
    default:
      return Icons.build;
  }
}

/// Localized label for [toolName], falling back to the raw tool name.
String toolDisplayNameFor(String toolName) {
  switch (toolName.toLowerCase()) {
    case 'web_search':
      return 'content.tool_web_search'.tr();
    case 'get_current_datetime':
      return 'content.tool_datetime'.tr();
    case 'memory_update':
      return 'content.tool_memory_update'.tr();
    case 'calculator':
      return 'content.tool_calculator'.tr();
    case 'code':
      return 'content.tool_code'.tr();
    case 'rollback_last_file_change':
      return 'rollback_last_file_change';
    default:
      return toolName;
  }
}

/// `read_file · lib/main.dart` — the tool name plus the one argument that says
/// what it acted on.
///
/// Synthesized here because nothing upstream produces a prose label:
/// `ToolCallInfo` is `{id, name, arguments}`, and `reason` is documented as
/// approval-dialog copy and is absent for read-only calls, so it cannot carry
/// this on its own.
String toolCallHeadline(ToolCallData? toolCall) {
  final name = toolDisplayNameFor(
    toolCall?.name ?? 'content.tool_default'.tr(),
  );
  final target = _salientArgument(toolCall?.arguments ?? const {});
  return target == null ? name : '$name · $target';
}

String? _salientArgument(Map<String, dynamic> arguments) {
  for (final key in _salientArgumentKeys) {
    final value = arguments[key];
    if (value is String && value.trim().isNotEmpty) {
      return _condense(value);
    }
  }
  for (final entry in arguments.entries) {
    if (_nonTargetArgumentKeys.contains(entry.key)) continue;
    final value = entry.value;
    if (value is String && value.trim().isNotEmpty) {
      return _condense(value);
    }
  }
  return null;
}

String _condense(String value) {
  final flattened = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (flattened.length <= _headlineArgumentMaxLength) return flattened;
  return '${flattened.substring(0, _headlineArgumentMaxLength)}…';
}

/// Renders every argument as a `key: value` line, the full detail the old
/// always-expanded tool card used to show inline.
String formatToolArguments(Map<String, dynamic> arguments) {
  if (arguments.isEmpty) return '';
  return arguments.entries
      .map((entry) => '${entry.key}: ${_formatArgumentValue(entry.value)}')
      .join('\n');
}

String _formatArgumentValue(dynamic value) {
  if (value == null) return 'null';
  if (value is String || value is num || value is bool) {
    return value.toString();
  }
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

/// One tool invocation: the call, plus the result it produced when the
/// transcript carries one.
///
/// The two arrive as separate adjacent segments, so pairing them here is what
/// keeps the header honest — a call and its result are one operation, not two.
class _ToolOperation {
  const _ToolOperation({this.call, this.result});

  final ContentSegment? call;
  final ContentSegment? result;

  ToolCallData? get _identity => call?.toolCall ?? result?.toolCall;

  String get headline => toolCallHeadline(_identity);

  bool get isComplete => result != null;

  /// Whether the tool reported its own failure.
  ///
  /// Only the content path writes a status, so `false` here means "succeeded
  /// or unknown". The row shows a check only for a verified success, never for
  /// a call whose outcome the transcript never carried.
  bool get failed => result?.toolCall?.arguments['status'] == 'error';
}

/// Pairs each result with the call it follows.
///
/// A result attaches to the operation immediately before it when that one is
/// still open and the names agree; anything else stands on its own rather than
/// being mislabelled.
List<_ToolOperation> _operationsFor(List<ContentSegment> segments) {
  final operations = <_ToolOperation>[];
  for (final segment in segments) {
    if (segment.type == ContentType.toolResult && operations.isNotEmpty) {
      final previous = operations.last;
      final callName = previous.call?.toolCall?.name.toLowerCase();
      final resultName = segment.toolCall?.name.toLowerCase();
      final namesAgree =
          callName == null || resultName == null || callName == resultName;
      if (!previous.isComplete && previous.call != null && namesAgree) {
        operations[operations.length - 1] = _ToolOperation(
          call: previous.call,
          result: segment,
        );
        continue;
      }
    }
    operations.add(
      segment.type == ContentType.toolResult
          ? _ToolOperation(result: segment)
          : _ToolOperation(call: segment),
    );
  }
  return operations;
}

/// A run of adjacent tool calls, collapsed to a single header.
///
/// Collapsed is the default: a long agentic turn otherwise buries its answer
/// under one loud card per call. Expansion state is held here rather than in
/// the parent so it survives the streaming rebuilds that append new calls to
/// the run.
class ToolCallGroup extends StatefulWidget {
  const ToolCallGroup({super.key, required this.segments, this.stateId});

  /// Adjacent `toolCall` / `toolResult` segments, in transcript order.
  final List<ContentSegment> segments;

  /// Stable identity for remembering what the user opened.
  ///
  /// The message list has no keep-alive, so this State is destroyed the moment
  /// the bubble scrolls out of view; without this an expanded group silently
  /// closes itself while the user scrolls away to read something. Null falls
  /// back to State-local expansion, for surfaces with no enclosing route.
  final String? stateId;

  @override
  State<ToolCallGroup> createState() => _ToolCallGroupState();
}

class _ToolCallGroupState extends State<ToolCallGroup> {
  bool _expanded = false;
  Set<int> _expandedRows = <int>{};
  bool _restored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored || widget.stateId == null) return;
    _restored = true;
    final open = _read('open');
    if (open is bool) _expanded = open;
    final rows = _read('rows');
    if (rows is List) _expandedRows = rows.whereType<int>().toSet();
  }

  Object? _read(String suffix) => PageStorage.maybeOf(
    context,
  )?.readState(context, identifier: '${widget.stateId}:$suffix');

  void _write(String suffix, Object? value) {
    if (widget.stateId == null) return;
    PageStorage.maybeOf(
      context,
    )?.writeState(context, value, identifier: '${widget.stateId}:$suffix');
  }

  void _toggleGroup() {
    setState(() => _expanded = !_expanded);
    _write('open', _expanded);
  }

  void _toggleRow(int index) {
    setState(() {
      if (!_expandedRows.remove(index)) _expandedRows.add(index);
    });
    _write('rows', _expandedRows.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final operations = _operationsFor(widget.segments);
    final isSingle = operations.length == 1;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme, operations),
          if (_expanded) ...[
            const SizedBox(height: 6),
            if (isSingle)
              _detail(operations.single, theme)
            else
              for (var i = 0; i < operations.length; i++)
                _row(i, operations[i], theme),
          ],
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, List<_ToolOperation> operations) {
    final isSingle = operations.length == 1;
    final failedCount = operations.where((o) => o.failed).length;
    final base = isSingle
        ? operations.single.headline
        : 'content.tool_group_summary'.tr(
            namedArgs: {'count': '${operations.length}'},
          );
    final label = failedCount == 0
        ? base
        : '$base · '
              '${'content.tool_group_failed'.tr(namedArgs: {'count': '$failedCount'})}';
    final iconName = isSingle ? operations.single._identity?.name ?? '' : null;
    final headerColor = failedCount == 0
        ? theme.colorScheme.onSurface.withValues(alpha: 0.72)
        : theme.colorScheme.error;

    return Semantics(
      button: true,
      expanded: _expanded,
      label: label,
      child: GestureDetector(
        onTap: _toggleGroup,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Icon(
              failedCount > 0
                  ? Icons.error_outline
                  : (iconName == null ? Icons.build : toolIconFor(iconName)),
              size: 14,
              color: failedCount == 0
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              // Brighter than the thinking block's header: collapsed is the
              // default, so this line is often the only record of the batch.
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: headerColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int index, _ToolOperation operation, ThemeData theme) {
    final isOpen = _expandedRows.contains(index);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: isOpen,
            label: operation.headline,
            child: GestureDetector(
              onTap: () => _toggleRow(index),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(
                    switch (operation) {
                      final o when o.failed => Icons.error_outline,
                      final o when o.isComplete => Icons.check_circle_outline,
                      _ => toolIconFor(operation._identity?.name ?? ''),
                    },
                    size: 14,
                    color: operation.failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      operation.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: operation.failed
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.8,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.chevron_right,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ),
          ),
          if (isOpen)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2, bottom: 4),
              child: _detail(operation, theme),
            ),
        ],
      ),
    );
  }

  Widget _detail(_ToolOperation operation, ThemeData theme) {
    final argumentText = formatToolArguments(
      operation.call?.toolCall?.arguments ?? const <String, dynamic>{},
    );
    final result = operation.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (argumentText.isNotEmpty)
          Text(
            argumentText,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        if (result != null) ...[
          if (argumentText.isNotEmpty) const SizedBox(height: 4),
          ..._resultLines(result, theme),
        ],
      ],
    );
  }

  List<Widget> _resultLines(ContentSegment result, ThemeData theme) {
    final arguments = result.toolCall?.arguments ?? const <String, dynamic>{};
    final summary =
        arguments['summary'] as String? ?? 'content.tool_result_ready'.tr();
    final details = ((arguments['details'] as List?) ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .take(3)
        .toList();

    return <Widget>[
      Text(
        summary,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
        ),
      ),
      for (final detail in details)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '• $detail',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ),
    ];
  }
}
