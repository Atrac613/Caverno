import 'package:flutter/material.dart';

import '../../../../core/services/macos_computer_use_setup.dart';

class ComputerUseDebugSectionTitle extends StatelessWidget {
  const ComputerUseDebugSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class ComputerUseDebugHelperBoundaryPanel extends StatelessWidget {
  const ComputerUseDebugHelperBoundaryPanel({required this.backend, super.key});

  final MacosComputerUseBackendInfo backend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.account_tree_outlined, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Computer Use App Boundary',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        backend.usesSeparateHelper
                            ? 'Privileged desktop control runs in the helper app, which also owns capture TCC.'
                            : 'Smoke checks still use the in-process compatibility backend.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ComputerUseDebugBoundaryValueRow(
              label: 'Current executor',
              value: '${backend.displayName} (${backend.executionMode})',
            ),
            _ComputerUseDebugBoundaryValueRow(
              label: 'Accessibility owner',
              value: backend.permissionOwnerName,
            ),
            const _ComputerUseDebugBoundaryValueRow(
              label: 'Screen/audio owner',
              value: 'Caverno Computer Use',
            ),
            _ComputerUseDebugBoundaryValueRow(
              label: 'Target helper',
              value:
                  '${backend.targetHelperName} (${backend.targetHelperBundleIdentifier})',
            ),
          ],
        ),
      ),
    );
  }
}

class _ComputerUseDebugBoundaryValueRow extends StatelessWidget {
  const _ComputerUseDebugBoundaryValueRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 136,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class ComputerUseDebugOnboardingProgressRow extends StatelessWidget {
  const ComputerUseDebugOnboardingProgressRow({
    required this.completed,
    required this.total,
    super.key,
  });

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$completed of $total complete',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class ComputerUseDebugOnboardingStepRow extends StatelessWidget {
  const ComputerUseDebugOnboardingStepRow({
    required this.label,
    required this.complete,
    super.key,
  });

  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = complete ? colorScheme.primary : colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            complete
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            complete ? 'Done' : 'Pending',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: complete ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class ComputerUseDebugOnboardingNote extends StatelessWidget {
  const ComputerUseDebugOnboardingNote({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(body, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ComputerUseDebugPermissionRow extends StatelessWidget {
  const ComputerUseDebugPermissionRow({
    required this.label,
    required this.value,
    this.openSettingsTooltip,
    this.onOpenSettings,
    super.key,
  });

  final String label;
  final bool? value;
  final String? openSettingsTooltip;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (value) {
      true => Icons.check_circle_outline,
      false => Icons.error_outline,
      null => Icons.help_outline,
    };
    final color = switch (value) {
      true => colorScheme.primary,
      false => colorScheme.error,
      null => Theme.of(context).disabledColor,
    };
    final labelText = switch (value) {
      true => 'Granted',
      false => 'Missing',
      null => 'Unknown',
    };
    final showSettingsButton = value != true && onOpenSettings != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(labelText, style: TextStyle(color: color)),
          if (showSettingsButton) ...[
            const SizedBox(width: 4),
            IconButton.filledTonal(
              tooltip: openSettingsTooltip ?? 'Open System Settings',
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

class ComputerUseDebugStatusRow extends StatelessWidget {
  const ComputerUseDebugStatusRow({
    required this.label,
    required this.value,
    required this.trueLabel,
    required this.falseLabel,
    required this.unknownLabel,
    super.key,
  });

  final String label;
  final bool? value;
  final String trueLabel;
  final String falseLabel;
  final String unknownLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (value) {
      true => Icons.check_circle_outline,
      false => Icons.error_outline,
      null => Icons.help_outline,
    };
    final color = switch (value) {
      true => colorScheme.primary,
      false => colorScheme.error,
      null => Theme.of(context).disabledColor,
    };
    final labelText = switch (value) {
      true => trueLabel,
      false => falseLabel,
      null => unknownLabel,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(labelText, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class ComputerUseDebugArmSwitch extends StatelessWidget {
  const ComputerUseDebugArmSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: value
          ? colorScheme.errorContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title),
        subtitle: Text(subtitle),
        secondary: Icon(
          value ? Icons.lock_open_outlined : Icons.lock_outline,
          color: value ? colorScheme.error : null,
        ),
      ),
    );
  }
}

class ComputerUseDebugCoordinateTargetRow extends StatelessWidget {
  const ComputerUseDebugCoordinateTargetRow({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.my_location_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}
