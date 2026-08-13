import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/services/pro_reasoning_models.dart';

class ProReasoningProgressCard extends StatelessWidget {
  const ProReasoningProgressCard({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  final ProReasoningProgress? progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = progress;
    final stage = current?.stage ?? ProReasoningStage.idle;
    final deadline = current == null
        ? null
        : TimeOfDay.fromDateTime(current.deadline.toLocal()).format(context);

    return Card(
      key: const ValueKey('pro-reasoning-progress-card'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _stageLabel(stage),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('pro-reasoning-progress-cancel'),
                  onPressed: current?.cancelRequested == true ? null : onCancel,
                  tooltip: 'message.pro_reasoning_cancel'.tr(),
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: _stageProgress(stage)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _Detail(
                  icon: Icons.groups_2_outlined,
                  label: 'message.pro_reasoning_candidates'.tr(
                    namedArgs: {
                      'completed': '${current?.completedCandidates ?? 0}',
                      'requested': '${current?.requestedCandidates ?? 0}',
                    },
                  ),
                ),
                if (deadline != null)
                  _Detail(
                    icon: Icons.schedule_outlined,
                    label: 'message.pro_reasoning_deadline'.tr(
                      namedArgs: {'time': deadline},
                    ),
                  ),
                if (current?.deadlineHit == true)
                  _Detail(
                    icon: Icons.timer_off_outlined,
                    label: 'message.pro_reasoning_deadline_hit'.tr(),
                  ),
                if (current?.cancelRequested == true)
                  _Detail(
                    icon: Icons.pending_outlined,
                    label: 'message.pro_reasoning_cancelling'.tr(),
                  ),
              ],
            ),
            if (current?.endpointLabels.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                'message.pro_reasoning_endpoints'.tr(
                  namedArgs: {'endpoints': current!.endpointLabels.join(', ')},
                ),
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _stageLabel(ProReasoningStage stage) => switch (stage) {
    ProReasoningStage.idle => 'message.pro_reasoning_stage_preparing'.tr(),
    ProReasoningStage.frame => 'message.pro_reasoning_stage_frame'.tr(),
    ProReasoningStage.investigate =>
      'message.pro_reasoning_stage_investigate'.tr(),
    ProReasoningStage.explore => 'message.pro_reasoning_stage_explore'.tr(),
    ProReasoningStage.critique => 'message.pro_reasoning_stage_critique'.tr(),
    ProReasoningStage.synthesize =>
      'message.pro_reasoning_stage_synthesize'.tr(),
  };

  double? _stageProgress(ProReasoningStage stage) => switch (stage) {
    ProReasoningStage.idle => null,
    ProReasoningStage.frame => 0.1,
    ProReasoningStage.investigate => 0.3,
    ProReasoningStage.explore => 0.55,
    ProReasoningStage.critique => 0.8,
    ProReasoningStage.synthesize => 0.95,
  };
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
