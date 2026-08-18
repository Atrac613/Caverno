import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/services/html_project_detector.dart';

/// Picker for HTML preview when the project has several entry files.
class HtmlPreviewEntrySheet extends StatelessWidget {
  const HtmlPreviewEntrySheet({super.key, required this.entries});

  final List<HtmlProjectEntry> entries;

  static Future<HtmlProjectEntry?> show(
    BuildContext context,
    List<HtmlProjectEntry> entries,
  ) {
    return showModalBottomSheet<HtmlProjectEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => HtmlPreviewEntrySheet(entries: entries),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'chat.html_preview_pick_entry'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (itemContext, index) {
                  final entry = entries[index];
                  return Material(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: ValueKey('html-preview-entry-${entry.relativePath}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(itemContext).pop(entry),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Text(
                          entry.relativePath,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
