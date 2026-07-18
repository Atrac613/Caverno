import 'package:flutter/material.dart';

enum ComputerUseDebugPermissionChecklistStatus {
  ready,
  warning,
  unknown;

  static ComputerUseDebugPermissionChecklistStatus fromReadiness({
    required bool isReady,
    required bool hasSnapshot,
  }) {
    if (isReady) {
      return ready;
    }
    if (hasSnapshot) {
      return warning;
    }
    return unknown;
  }
}

class ComputerUseDebugPermissionChecklistViewModel {
  const ComputerUseDebugPermissionChecklistViewModel({
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String title;
  final String subtitle;
  final ComputerUseDebugPermissionChecklistStatus status;
}

class ComputerUseDebugPermissionChecklist extends StatelessWidget {
  const ComputerUseDebugPermissionChecklist({
    required this.viewModel,
    super.key,
  });

  final ComputerUseDebugPermissionChecklistViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (viewModel.status) {
      ComputerUseDebugPermissionChecklistStatus.ready => (
        Icons.task_alt_outlined,
        colorScheme.primary,
      ),
      ComputerUseDebugPermissionChecklistStatus.warning => (
        Icons.warning_amber_outlined,
        colorScheme.error,
      ),
      ComputerUseDebugPermissionChecklistStatus.unknown => (
        Icons.info_outline,
        colorScheme.secondary,
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viewModel.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    viewModel.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
