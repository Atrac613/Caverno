import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../code_block_builder.dart';

class PlanMarkdownPreview extends StatelessWidget {
  const PlanMarkdownPreview({
    super.key,
    required this.markdown,
    required this.maxHeight,
  });

  final String markdown;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        child: SelectionArea(
          child: MarkdownBody(
            data: markdown,
            selectable: false,
            builders: {'pre': CodeBlockBuilder(theme: theme)},
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
              strong: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
              em: TextStyle(
                color: textColor,
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
              listBullet: TextStyle(color: textColor),
              a: TextStyle(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              tableBorder: TableBorder.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
              tableHead: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
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
              if (href == null) {
                return;
              }
              launchUrl(Uri.parse(href));
            },
          ),
        ),
      ),
    );
  }
}
