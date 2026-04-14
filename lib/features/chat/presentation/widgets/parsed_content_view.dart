import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/content_parser.dart';
import 'code_block_builder.dart';

/// Renders parsed content segments.
/// `<think>` tags are shown in muted gray and tool tags as compact status cards.
/// Completed thinking blocks are collapsible; streaming ones show live content.
class ParsedContentView extends StatefulWidget {
  const ParsedContentView({
    super.key,
    required this.content,
    required this.textColor,
    this.isStreaming = false,
  });

  final String content;
  final Color textColor;
  final bool isStreaming;

  @override
  State<ParsedContentView> createState() => _ParsedContentViewState();
}

class _ParsedContentViewState extends State<ParsedContentView> {
  final Set<int> _collapsedThinkingBlocks = {};

  @override
  void didUpdateWidget(covariant ParsedContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-collapse all thinking blocks when streaming ends
    if (oldWidget.isStreaming && !widget.isStreaming) {
      final result = ContentParser.parse(widget.content);
      for (var i = 0; i < result.segments.length; i++) {
        if (result.segments[i].type == ContentType.thinking) {
          _collapsedThinkingBlocks.add(i);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = ContentParser.parse(widget.content);
    final theme = Theme.of(context);

    if (result.segments.isEmpty) {
      // Show streaming thinking block even when no completed segments exist
      if (widget.isStreaming &&
          result.hasIncompleteTag &&
          result.incompleteTagType == 'thinking') {
        return SelectionArea(
          child: _buildStreamingThinkingBlock(
            result.incompleteTagContent ?? '',
            theme,
          ),
        );
      }
      // Show streaming tool execution block for incomplete tool tags
      if (widget.isStreaming &&
          result.hasIncompleteTag &&
          result.incompleteTagType == 'tool_call') {
        return _buildStreamingToolBlock(theme);
      }
      if (widget.isStreaming) {
        return Text('...', style: TextStyle(color: widget.textColor));
      }
      return const SizedBox.shrink();
    }

    // Note: each text segment is wrapped individually in a SelectionArea
    // (see _buildSegment). We intentionally avoid wrapping the whole
    // Column in a single SelectionArea because multi-selectable content
    // that is frequently restructured during streaming (text ↔ tool_call
    // segments) can trip Flutter's MultiSelectableSelectionContainer
    // delegate into calling getTransformTo on an unmounted render object.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < result.segments.length; i++)
          _buildSegment(context, result.segments[i], theme, i),
        // Show streaming thinking block with partial content
        if (widget.isStreaming &&
            result.hasIncompleteTag &&
            result.incompleteTagType == 'thinking')
          _buildStreamingThinkingBlock(
            result.incompleteTagContent ?? '',
            theme,
          ),
        // Show streaming tool execution block
        if (widget.isStreaming &&
            result.hasIncompleteTag &&
            result.incompleteTagType == 'tool_call')
          _buildStreamingToolBlock(theme),
      ],
    );
  }

  Widget _buildSegment(
    BuildContext context,
    ContentSegment segment,
    ThemeData theme,
    int index,
  ) {
    switch (segment.type) {
      case ContentType.text:
        return SelectionArea(
          child: MarkdownBody(
            data: _escapeHtmlLikeTags(segment.content),
            selectable: false,
            builders: {
              'pre': CodeBlockBuilder(theme: theme),
            },
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: widget.textColor, fontSize: 14, height: 1.5),
              h1: TextStyle(
                color: widget.textColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              h2: TextStyle(
                color: widget.textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              h3: TextStyle(
                color: widget.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              h4: TextStyle(
                color: widget.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              strong: TextStyle(
                color: widget.textColor,
                fontWeight: FontWeight.bold,
              ),
              em: TextStyle(
                color: widget.textColor,
                fontStyle: FontStyle.italic,
              ),
              code: TextStyle(
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow.withValues(
                  alpha: 0.8,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              codeblockPadding: const EdgeInsets.all(12),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
              ),
              blockquotePadding: const EdgeInsets.only(
                left: 12,
                top: 4,
                bottom: 4,
              ),
              listBullet: TextStyle(color: widget.textColor),
              a: TextStyle(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              tableBorder: TableBorder.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
              tableHead: TextStyle(
                color: widget.textColor,
                fontWeight: FontWeight.bold,
              ),
              tableBody: TextStyle(color: widget.textColor),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            onTapLink: (text, href, title) {
              if (href != null) {
                launchUrl(Uri.parse(href));
              }
            },
          ),
        );

      case ContentType.thinking:
        return _buildThinkingBlock(segment.content, theme, index);

      case ContentType.toolCall:
        return _buildToolCallBlock(segment, theme);

      case ContentType.toolResult:
        return _buildToolResultBlock(segment, theme);
    }
  }

  Widget _buildThinkingBlock(String content, ThemeData theme, int index) {
    final isCollapsed = _collapsedThinkingBlocks.contains(index);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
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
          GestureDetector(
            onTap: () {
              setState(() {
                if (isCollapsed) {
                  _collapsedThinkingBlocks.remove(index);
                } else {
                  _collapsedThinkingBlocks.add(index);
                }
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Text(
                  'content.thinking'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isCollapsed ? Icons.expand_more : Icons.expand_less,
                  size: 14,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 6),
            Text(
              content,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolCallBlock(ContentSegment segment, ThemeData theme) {
    final toolCall = segment.toolCall;
    final toolName = toolCall?.name ?? 'content.tool_default'.tr();
    final arguments = toolCall?.arguments ?? const <String, dynamic>{};
    final argumentText = _formatToolArguments(arguments);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getToolIcon(toolName),
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _getToolDisplayName(toolName),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (argumentText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              argumentText,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolResultBlock(ContentSegment segment, ThemeData theme) {
    final toolResult = segment.toolCall;
    final toolName = toolResult?.name ?? 'content.tool_default'.tr();
    final summary =
        toolResult?.arguments['summary'] as String? ??
        'content.tool_result_ready'.tr();
    final details = ((toolResult?.arguments['details'] as List?) ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .take(3)
        .toList();

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getToolDisplayName(toolName),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    fontSize: 12,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (final detail in details)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• $detail',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.62,
                          ),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Escapes stray HTML-like tags in text before passing to flutter_markdown.
  ///
  /// flutter_markdown 0.7.x trips an `_inlines.isEmpty` assertion when it
  /// encounters inline HTML it cannot reconcile. LLM responses that echo
  /// command output (e.g. SSH results) frequently contain angle-bracket
  /// sequences like `<ip>`, `<user@host>`, or XML fragments that look like
  /// HTML tags. Since the content parser has already stripped our
  /// structural `<think>` / `<tool_call>` / `<tool_use>` tags by the time
  /// we reach a text segment, any remaining `<…>` outside fenced/inline
  /// code can safely be escaped.
  static final _htmlLikeTagPattern = RegExp(r'<(/?[a-zA-Z][^>]*)>');
  static final _fenceLinePattern = RegExp(r'^\s*```');

  String _escapeHtmlLikeTags(String text) {
    final buffer = StringBuffer();
    var insideFence = false;
    // Process line by line so fenced code blocks are preserved verbatim.
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_fenceLinePattern.hasMatch(line)) {
        insideFence = !insideFence;
        buffer.write(line);
      } else if (insideFence) {
        buffer.write(line);
      } else {
        buffer.write(_escapeOutsideInlineCode(line));
      }
      if (i != lines.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  /// Escapes HTML-like tags in a single line while leaving inline
  /// backtick-delimited spans untouched.
  String _escapeOutsideInlineCode(String line) {
    final buffer = StringBuffer();
    var inCode = false;
    var i = 0;
    while (i < line.length) {
      final ch = line[i];
      if (ch == '`') {
        inCode = !inCode;
        buffer.write(ch);
        i++;
        continue;
      }
      if (inCode) {
        buffer.write(ch);
        i++;
        continue;
      }
      // Try matching an HTML-like tag starting at i.
      final match = _htmlLikeTagPattern.matchAsPrefix(line, i);
      if (match != null) {
        buffer.write('&lt;${match.group(1)}&gt;');
        i = match.end;
        continue;
      }
      buffer.write(ch);
      i++;
    }
    return buffer.toString();
  }

  String _formatToolArguments(Map<String, dynamic> arguments) {
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

  Widget _buildStreamingThinkingBlock(String content, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology,
                size: 14,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 4),
              Text(
                'content.thinking_active'.tr(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              content,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStreamingToolBlock(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.build,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            'content.tool_executing'.tr(),
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getToolIcon(String toolName) {
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
      default:
        return Icons.build;
    }
  }

  String _getToolDisplayName(String toolName) {
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
      default:
        return toolName;
    }
  }
}
