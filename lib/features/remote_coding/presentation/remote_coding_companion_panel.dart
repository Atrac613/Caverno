import 'package:flutter/material.dart';

import '../domain/remote_coding_companion_models.dart';

class RemoteCodingCompanionPanel extends StatelessWidget {
  const RemoteCodingCompanionPanel({
    super.key,
    required this.snapshot,
    required this.isLoading,
    required this.queuedCount,
    this.pendingQuestion,
  });

  final RemoteCodingCompanionSnapshot? snapshot;
  final bool isLoading;
  final int queuedCount;
  final String? pendingQuestion;

  @override
  Widget build(BuildContext context) {
    final companion = snapshot;
    if (companion == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The connected desktop does not provide the companion panel yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('remote-coding-companion-panel'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.32,
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProgressSection(context, companion),
              const SizedBox(height: 18),
              _buildChangesSection(context, companion),
              const SizedBox(height: 18),
              _buildEnvironmentSection(context, companion),
              const SizedBox(height: 18),
              _buildAwaitingSection(context, companion),
              const SizedBox(height: 18),
              _buildSourcesSection(context, companion),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection(
    BuildContext context,
    RemoteCodingCompanionSnapshot companion,
  ) {
    final tasks = companion.tasks;
    final completed = companion.completedTaskCount;
    final progress = tasks.isEmpty ? 0.0 : completed / tasks.length;
    final theme = Theme.of(context);
    return _section(
      context,
      title: 'Progress',
      children: [
        if (tasks.isEmpty)
          _emptyText(context, 'No workflow tasks.')
        else ...[
          Text(
            '$completed of ${tasks.length} complete',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: progress, minHeight: 6),
          ),
          const SizedBox(height: 12),
          for (final task in tasks.take(6)) ...[
            _taskRow(context, task),
            if (task != tasks.take(6).last) const SizedBox(height: 10),
          ],
          if (tasks.length > 6) ...[
            const SizedBox(height: 10),
            _emptyText(context, '${tasks.length - 6} more tasks.'),
          ],
        ],
        if (isLoading || queuedCount > 0) ...[
          if (tasks.isNotEmpty) const SizedBox(height: 12),
          Text(
            isLoading
                ? queuedCount > 0
                      ? 'Running with $queuedCount queued message(s).'
                      : 'Running on the desktop.'
                : '$queuedCount message(s) queued on the desktop.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChangesSection(
    BuildContext context,
    RemoteCodingCompanionSnapshot companion,
  ) {
    final changes = companion.changes;
    return _section(
      context,
      title: 'Changes',
      children: [
        if (changes.isEmpty)
          _emptyText(context, 'No recent file changes.')
        else
          for (final change in changes) ...[
            _changeRow(context, change),
            if (change != changes.last) const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildEnvironmentSection(
    BuildContext context,
    RemoteCodingCompanionSnapshot companion,
  ) {
    final rows = <Widget>[];
    if (companion.projectRootPath.isNotEmpty) {
      rows.add(
        _infoRow(
          context,
          icon: Icons.folder_outlined,
          label: 'Project',
          value: companion.projectRootPath,
        ),
      );
    }
    if (companion.worktreePath.isNotEmpty) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(
        _infoRow(
          context,
          icon: Icons.account_tree_outlined,
          label: 'Worktree',
          value: companion.worktreePath,
        ),
      );
    }
    return _section(
      context,
      title: 'Environment',
      children: [
        if (rows.isEmpty) _emptyText(context, 'No environment details.'),
        ...rows,
      ],
    );
  }

  Widget _buildAwaitingSection(
    BuildContext context,
    RemoteCodingCompanionSnapshot companion,
  ) {
    final questions = <String>{
      ...companion.openQuestions,
      if (pendingQuestion != null && pendingQuestion!.trim().isNotEmpty)
        pendingQuestion!.trim(),
    }.toList(growable: false);
    return _section(
      context,
      title: 'Awaiting you',
      children: [
        if (questions.isEmpty)
          _emptyText(context, 'Nothing is waiting for you.'),
        for (final question in questions.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.help_outline, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(question)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSourcesSection(
    BuildContext context,
    RemoteCodingCompanionSnapshot companion,
  ) {
    return _section(
      context,
      title: 'Sources',
      children: [
        if (companion.sourceLocators.isEmpty)
          _emptyText(context, 'No tracked sources.')
        else
          for (final locator in companion.sourceLocators.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _infoRow(
                context,
                icon: Icons.description_outlined,
                label: 'Source',
                value: locator,
              ),
            ),
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  Widget _taskRow(BuildContext context, RemoteCodingCompanionTask task) {
    final theme = Theme.of(context);
    final icon = switch (task.status) {
      'completed' => Icons.check_circle,
      'inProgress' => Icons.play_circle_outline,
      'blocked' => Icons.block,
      _ => Icons.radio_button_unchecked,
    };
    final color = switch (task.status) {
      'completed' => Colors.green.shade700,
      'blocked' => theme.colorScheme.error,
      'inProgress' => theme.colorScheme.primary,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title),
              if (task.targetFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    task.targetFiles.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _changeRow(BuildContext context, RemoteCodingCompanionChange change) {
    final theme = Theme.of(context);
    final summary =
        '${change.filesChanged} ${change.filesChanged == 1 ? 'file' : 'files'} '
        'changed  +${change.linesAdded} -${change.linesRemoved}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.history_toggle_off, size: 18),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(change.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (change.filePaths.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    change.filePaths.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
