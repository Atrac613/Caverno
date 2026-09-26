import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/project_farm_policy.dart';
import '../providers/roadmap_snapshot_providers.dart';

/// Shows and edits one project's background-work policy (FARM4 slice 4a).
///
/// The policy is the user's declaration of which verification commands
/// background work may run. Only this card writes it; no tool does.
class ProjectFarmPolicyCard extends ConsumerStatefulWidget {
  const ProjectFarmPolicyCard({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectFarmPolicyCard> createState() =>
      _ProjectFarmPolicyCardState();
}

class _ProjectFarmPolicyCardState extends ConsumerState<ProjectFarmPolicyCard> {
  Future<void> _edit(ProjectFarmPolicy? policy) async {
    final commands = await showDialog<List<String>>(
      context: context,
      builder: (_) => ProjectFarmPolicyDialog(
        initialCommands: policy?.allowedVerificationCommands ?? const [],
      ),
    );
    if (commands == null || !mounted) return;
    await ref
        .read(roadmapSnapshotRepositoryProvider)
        .savePolicy(
          (policy ??
                  ProjectFarmPolicy(
                    projectId: widget.projectId,
                    updatedAt: DateTime.now(),
                  ))
              .copyWith(
                allowedVerificationCommands: commands,
                // A command the user removed cannot stay unattended.
                unattendedCommands: [
                  for (final command in policy?.unattendedCommands ?? const [])
                    if (commands.contains(normalizePolicyCommand(command)))
                      command,
                ],
                updatedAt: DateTime.now(),
              ),
        );
    if (mounted) setState(() {});
  }

  Future<void> _editUnattended(ProjectFarmPolicy policy) async {
    final updated = await showDialog<ProjectFarmPolicy>(
      context: context,
      builder: (_) => ProjectFarmUnattendedDialog(policy: policy),
    );
    if (updated == null || !mounted) return;
    await ref
        .read(roadmapSnapshotRepositoryProvider)
        .savePolicy(updated.copyWith(updatedAt: DateTime.now()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = ref
        .watch(roadmapSnapshotRepositoryProvider)
        .policyFor(widget.projectId);
    final commands = policy?.allowedVerificationCommands ?? const <String>[];
    final recentRuns = ref
        .watch(roadmapSnapshotRepositoryProvider)
        .farmRuns()
        .where((run) => run.projectId == widget.projectId)
        .toList()
        .reversed
        .take(5)
        .toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'project_farm_policy.title'.tr(),
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                TextButton(
                  key: const ValueKey('project-farm-policy-edit'),
                  onPressed: () => _edit(policy),
                  child: Text('common.edit'.tr()),
                ),
              ],
            ),
            if (commands.isEmpty)
              Text('project_farm_policy.not_configured'.tr())
            else ...[
              Text(
                'project_farm_policy.allowed_commands'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              for (final command in commands)
                Text(
                  command,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      policy!.allowsUnattendedRuns
                          ? 'project_farm_policy.unattended_on'.tr(
                              args: [
                                '${policy.dailyRunLimit}',
                                policy.unattendedCommand!,
                              ],
                            )
                          : 'project_farm_policy.unattended_off'.tr(),
                      key: const ValueKey('project-farm-policy-unattended'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('project-farm-policy-unattended-edit'),
                    onPressed: () => _editUnattended(policy),
                    child: Text('project_farm_policy.unattended_edit'.tr()),
                  ),
                ],
              ),
            ],
            if (recentRuns.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'project_farm_policy.recent_runs'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              for (final run in recentRuns)
                Text(
                  '${DateFormat.MMMd().add_Hm().format(run.at.toLocal())} · '
                  '${'project_farm_policy.run_${run.trigger}'.tr()} · '
                  '${run.outcome == 'enqueued' ? '${run.taskId} → ${run.branch}' : 'project_farm_policy.skipped'.tr(args: [run.detail])}',
                  key: ValueKey('project-farm-run-${run.id}'),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Edits the allowed verification commands, one per line. Completes with the
/// validated list, or null when cancelled.
class ProjectFarmPolicyDialog extends StatefulWidget {
  const ProjectFarmPolicyDialog({super.key, required this.initialCommands});

  final List<String> initialCommands;

  @override
  State<ProjectFarmPolicyDialog> createState() =>
      _ProjectFarmPolicyDialogState();
}

class _ProjectFarmPolicyDialogState extends State<ProjectFarmPolicyDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialCommands.join('\n'),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final commands = <String>[];
    for (final line in _controller.text.split('\n')) {
      if (line.trim().isEmpty) continue;
      if (policyCommandProblem(line) != null) {
        setState(
          () => _error = 'project_farm_policy.invalid_command'.tr(
            args: [line.trim()],
          ),
        );
        return;
      }
      final normalized = normalizePolicyCommand(line);
      if (!commands.contains(normalized)) commands.add(normalized);
    }
    Navigator.of(context).pop(commands);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('project_farm_policy.title'.tr()),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('project_farm_policy.help'.tr()),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('project-farm-policy-commands'),
              controller: _controller,
              minLines: 3,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'fvm flutter analyze\ntool/flutter_test_quiet.sh',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey('project-farm-policy-save'),
          onPressed: _save,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}

/// FARM5: whether idle-time maintenance may start runs, how many a day, and
/// which allowed commands the user declares do not execute project code.
class ProjectFarmUnattendedDialog extends StatefulWidget {
  const ProjectFarmUnattendedDialog({super.key, required this.policy});

  final ProjectFarmPolicy policy;

  @override
  State<ProjectFarmUnattendedDialog> createState() =>
      _ProjectFarmUnattendedDialogState();
}

class _ProjectFarmUnattendedDialogState
    extends State<ProjectFarmUnattendedDialog> {
  late bool _enabled = widget.policy.autoRunEnabled;
  late int _limit = widget.policy.dailyRunLimit.clamp(1, 10);
  late final Set<String> _unattended = {
    for (final command in widget.policy.unattendedCommands)
      normalizePolicyCommand(command),
  };

  @override
  Widget build(BuildContext context) {
    final commands = widget.policy.allowedVerificationCommands;
    return AlertDialog(
      title: Text('project_farm_policy.unattended_title'.tr()),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('project-farm-unattended-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text('project_farm_policy.unattended_enable'.tr()),
              subtitle: Text('project_farm_policy.unattended_window'.tr()),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            Row(
              children: [
                Expanded(
                  child: Text('project_farm_policy.unattended_limit'.tr()),
                ),
                DropdownButton<int>(
                  value: _limit,
                  items: [
                    for (var n = 1; n <= 10; n++)
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _limit = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('project_farm_policy.unattended_commands_help'.tr()),
            for (final command in commands)
              CheckboxListTile(
                key: ValueKey('project-farm-unattended-$command'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  command,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                value: _unattended.contains(normalizePolicyCommand(command)),
                onChanged: (checked) => setState(() {
                  final normalized = normalizePolicyCommand(command);
                  checked == true
                      ? _unattended.add(normalized)
                      : _unattended.remove(normalized);
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey('project-farm-unattended-save'),
          onPressed: () => Navigator.of(context).pop(
            widget.policy.copyWith(
              autoRunEnabled: _enabled,
              dailyRunLimit: _limit,
              unattendedCommands: [
                for (final command in commands)
                  if (_unattended.contains(normalizePolicyCommand(command)))
                    normalizePolicyCommand(command),
              ],
            ),
          ),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
