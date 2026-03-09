import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/content_parser.dart';

/// Renders parsed content segments.
/// `<think>` tags are shown in muted gray and `<tool_call>` tags as tool calls.
class ParsedContentView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final result = ContentParser.parse(content);
    final theme = Theme.of(context);

    if (result.segments.isEmpty) {
      if (isStreaming) {
        return Text('...', style: TextStyle(color: textColor));
      }
      return const SizedBox.shrink();
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final segment in result.segments)
            _buildSegment(context, segment, theme),
          // Show an indicator when a streaming response contains an incomplete think tag.
          if (isStreaming &&
              result.hasIncompleteTag &&
              result.incompleteTagType == 'thinking')
            _buildStreamingThinkingIndicator(theme),
        ],
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context,
    ContentSegment segment,
    ThemeData theme,
  ) {
    switch (segment.type) {
      case ContentType.text:
        return MarkdownBody(
          data: segment.content,
          // Keep the entire bubble as a single SelectionArea.
          selectable: false,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: textColor, fontSize: 14, height: 1.5),
            h1: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            h2: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            h3: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            h4: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            em: TextStyle(color: textColor, fontStyle: FontStyle.italic),
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
            listBullet: TextStyle(color: textColor),
            a: TextStyle(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            tableBorder: TableBorder.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
            tableHead: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            tableBody: TextStyle(color: textColor),
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
        );

      case ContentType.thinking:
        return _buildThinkingBlock(segment.content, theme);

      case ContentType.toolCall:
        return _buildToolCallBlock(segment, theme);
    }
  }

  Widget _buildThinkingBlock(String content, ThemeData theme) {
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
                '思考',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
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
      ),
    );
  }

  Widget _buildToolCallBlock(ContentSegment segment, ThemeData theme) {
    final toolCall = segment.toolCall;
    final toolName = toolCall?.name ?? 'ツール';
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

  Widget _buildStreamingThinkingIndicator(ThemeData theme) {
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text(
            '思考中...',
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
        return 'Web検索';
      case 'get_current_datetime':
        return '現在日時取得';
      case 'memory_update':
        return '会話メモリ更新';
      case 'calculator':
        return '計算';
      case 'code':
        return 'コード実行';
      default:
        return toolName;
    }
  }
}
