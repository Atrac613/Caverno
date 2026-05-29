import 'package:flutter/material.dart';

import '../../domain/entities/turn_diff.dart';

Future<void> showTurnDiffSheet(BuildContext context, {required TurnDiff diff}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.86,
      child: TurnDiffSheet(diff: diff),
    ),
  );
}

class TurnDiffSheet extends StatelessWidget {
  const TurnDiffSheet({super.key, required this.diff});

  final TurnDiff diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = diff.source == TurnDiffSource.git
        ? 'Uncommitted changes'
        : 'Turn changes';

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _DiffSummaryText(diff: diff),
                      if (diff.userPromptPreview.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          diff.userPromptPreview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: diff.hasChanges
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    itemCount: diff.files.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final file = diff.files[index];
                      return _TurnDiffFileTile(
                        file: file,
                        initiallyExpanded: index == 0,
                      );
                    },
                  )
                : _CleanDiffView(source: diff.source),
          ),
        ],
      ),
    );
  }
}

class _DiffSummaryText extends StatelessWidget {
  const _DiffSummaryText({required this.diff});

  final TurnDiff diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!diff.hasChanges) {
      return Text(
        diff.source == TurnDiffSource.git
            ? 'Working tree is clean'
            : 'No file changes recorded',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text:
                '${diff.filesChanged} ${diff.filesChanged == 1 ? 'file' : 'files'} changed ',
          ),
          TextSpan(
            text: '+${diff.linesAdded}',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '-${diff.linesRemoved}',
            style: TextStyle(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnDiffFileTile extends StatelessWidget {
  const _TurnDiffFileTile({
    required this.file,
    required this.initiallyExpanded,
  });

  final TurnDiffFile file;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(
          file.filePath,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: _FileSummary(file: file),
        children: [_DiffPatchView(file: file)],
      ),
    );
  }
}

class _FileSummary extends StatelessWidget {
  const _FileSummary({required this.file});

  final TurnDiffFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badges = <String>[
      if (file.isNewFile) 'new',
      if (file.isDeletedFile) 'deleted',
      if (file.isUntracked) 'untracked',
      if (file.isBinary) 'binary',
      if (file.isLargeFile) 'large',
      if (file.isTruncated) 'truncated',
    ];

    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(text: badges.isEmpty ? '' : '${badges.join(', ')}  '),
          TextSpan(
            text: '+${file.linesAdded}',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '-${file.linesRemoved}',
            style: TextStyle(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _DiffPatchView extends StatelessWidget {
  const _DiffPatchView({required this.file});

  final TurnDiffFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = file.note.trim();
    if (!file.hasRenderablePatch) {
      return _DiffUnavailableView(note: note);
    }

    final lines = file.unifiedPatch.split('\n');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in lines) _DiffLine(line: line),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiffUnavailableView extends StatelessWidget {
  const _DiffUnavailableView({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        note.isEmpty ? 'Diff preview is unavailable for this file.' : note,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAddition = line.startsWith('+') && !line.startsWith('+++');
    final isRemoval = line.startsWith('-') && !line.startsWith('---');
    final isHeader =
        line.startsWith('@@') ||
        line.startsWith('diff --git') ||
        line.startsWith('index ') ||
        line.startsWith('---') ||
        line.startsWith('+++');

    final Color? background;
    final Color foreground;
    if (isAddition) {
      background = Colors.green.withValues(alpha: 0.10);
      foreground = Colors.green.shade800;
    } else if (isRemoval) {
      background = theme.colorScheme.error.withValues(alpha: 0.10);
      foreground = theme.colorScheme.error;
    } else if (isHeader) {
      background = theme.colorScheme.surfaceContainerHighest;
      foreground = theme.colorScheme.onSurfaceVariant;
    } else {
      background = null;
      foreground = theme.colorScheme.onSurface;
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: SelectableText(
          line.isEmpty ? ' ' : line,
          style: TextStyle(
            color: foreground,
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _CleanDiffView extends StatelessWidget {
  const _CleanDiffView({required this.source});

  final TurnDiffSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        source == TurnDiffSource.git
            ? 'Working tree is clean'
            : 'No file changes recorded',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
