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
          ProjectFarmPolicy(
            projectId: widget.projectId,
            allowedVerificationCommands: commands,
            updatedAt: DateTime.now(),
          ),
        );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = ref
        .watch(roadmapSnapshotRepositoryProvider)
        .policyFor(widget.projectId);
    final commands = policy?.allowedVerificationCommands ?? const <String>[];
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
