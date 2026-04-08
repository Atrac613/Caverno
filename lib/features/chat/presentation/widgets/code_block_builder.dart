import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Custom markdown element builder that renders fenced code blocks
/// with a header bar containing the language label and a copy button.
class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder({required this.theme});

  final ThemeData theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Only handle fenced code blocks (pre > code)
    if (element.tag != 'pre') return null;

    final codeElement = element.children?.whereType<md.Element>().firstOrNull;
    if (codeElement == null || codeElement.tag != 'code') return null;

    // Extract language from class attribute (e.g., "language-dart")
    final className = codeElement.attributes['class'] ?? '';
    final language = className.startsWith('language-')
        ? className.substring('language-'.length)
        : '';

    final code = codeElement.textContent.trimRight();

    return _CodeBlockWidget(
      code: code,
      language: language,
      theme: theme,
    );
  }
}

class _CodeBlockWidget extends StatefulWidget {
  const _CodeBlockWidget({
    required this.code,
    required this.language,
    required this.theme,
  });

  final String code;
  final String language;
  final ThemeData theme;

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final outlineColor = theme.colorScheme.outline.withValues(alpha: 0.2);
    final headerColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.6,
    );
    final bgColor = theme.colorScheme.surfaceContainerLow.withValues(
      alpha: 0.8,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: outlineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar with language label and copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
              border: Border(bottom: BorderSide(color: outlineColor)),
            ),
            child: Row(
              children: [
                if (widget.language.isNotEmpty)
                  Text(
                    widget.language,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  height: 24,
                  child: TextButton.icon(
                    onPressed: _copyToClipboard,
                    icon: Icon(
                      _copied ? Icons.check : Icons.content_copy,
                      size: 14,
                    ),
                    label: Text(
                      _copied
                          ? 'content.code_copied'.tr()
                          : 'content.code_copy'.tr(),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: _copied
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(7),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                widget.code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
