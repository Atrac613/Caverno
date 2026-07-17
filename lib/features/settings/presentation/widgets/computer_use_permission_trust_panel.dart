import 'package:flutter/material.dart';

import '../../../../core/services/macos_computer_use_setup.dart';

class ComputerUsePermissionTrustPanel extends StatelessWidget {
  const ComputerUsePermissionTrustPanel({
    super.key,
    required this.accessibilityGranted,
    required this.screenCaptureGranted,
    required this.isLoading,
    required this.recoverySummary,
    required this.onOpenAccessibility,
    required this.onOpenScreenRecording,
    required this.onRecheck,
  });

  final bool accessibilityGranted;
  final bool screenCaptureGranted;
  final bool isLoading;
  final MacosComputerUsePermissionRecoverySummary recoverySummary;
  final VoidCallback onOpenAccessibility;
  final VoidCallback onOpenScreenRecording;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PermissionFlowSummary(
          accessibilityGranted: accessibilityGranted,
          screenCaptureGranted: screenCaptureGranted,
          isLoading: isLoading,
          onOpenAccessibility: onOpenAccessibility,
          onOpenScreenRecording: onOpenScreenRecording,
          onRecheck: onRecheck,
        ),
        const SizedBox(height: 12),
        _PermissionRecoverySummary(summary: recoverySummary),
      ],
    );
  }
}

class _PermissionFlowSummary extends StatelessWidget {
  const _PermissionFlowSummary({
    required this.accessibilityGranted,
    required this.screenCaptureGranted,
    required this.isLoading,
    required this.onOpenAccessibility,
    required this.onOpenScreenRecording,
    required this.onRecheck,
  });

  final bool accessibilityGranted;
  final bool screenCaptureGranted;
  final bool isLoading;
  final VoidCallback onOpenAccessibility;
  final VoidCallback onOpenScreenRecording;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Permission flow', style: textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(
              'Caverno Computer Use',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _PermissionFlowRow(
              actionKey: const ValueKey(
                'computer-use-permission-flow-accessibility',
              ),
              label: 'Accessibility',
              granted: accessibilityGranted,
              blockedText: 'Grant Caverno Computer Use, then recheck.',
              openLabel: 'Open Accessibility',
              onOpen: onOpenAccessibility,
              onRecheck: onRecheck,
              isLoading: isLoading,
            ),
            const SizedBox(height: 8),
            _PermissionFlowRow(
              actionKey: const ValueKey(
                'computer-use-permission-flow-screen-recording',
              ),
              label: 'Screen & System Audio Recording',
              granted: screenCaptureGranted,
              blockedText: 'Grant Caverno Computer Use, then recheck.',
              openLabel: 'Open Screen Recording',
              onOpen: onOpenScreenRecording,
              onRecheck: onRecheck,
              isLoading: isLoading,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionFlowRow extends StatelessWidget {
  const _PermissionFlowRow({
    required this.actionKey,
    required this.label,
    required this.granted,
    required this.blockedText,
    required this.openLabel,
    required this.onOpen,
    required this.onRecheck,
    required this.isLoading,
  });

  final Key actionKey;
  final String label;
  final bool granted;
  final String blockedText;
  final String openLabel;
  final VoidCallback onOpen;
  final VoidCallback onRecheck;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = granted ? colorScheme.primary : colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(
          color: granted ? colorScheme.outlineVariant : colorScheme.error,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              granted ? Icons.check_circle_outline : Icons.error_outline,
              color: statusColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    granted ? 'Granted to Caverno Computer Use.' : blockedText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!granted)
              OutlinedButton(
                key: actionKey,
                onPressed: isLoading ? null : onOpen,
                child: Text(openLabel),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Done', style: TextStyle(color: statusColor)),
                  const SizedBox(width: 4),
                  Icon(Icons.check, size: 18, color: statusColor),
                ],
              ),
            TextButton(
              onPressed: isLoading ? null : onRecheck,
              child: const Text('Recheck'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRecoverySummary extends StatelessWidget {
  const _PermissionRecoverySummary({required this.summary});

  final MacosComputerUsePermissionRecoverySummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = summary.isReady
        ? colorScheme.primary
        : colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  summary.isReady
                      ? Icons.verified_outlined
                      : Icons.warning_amber_outlined,
                  size: 18,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Text('Recovery guidance', style: textTheme.labelLarge),
                const Spacer(),
                Text(
                  summary.isReady ? 'Ready' : 'Needs recovery',
                  style: textTheme.labelMedium?.copyWith(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (summary.missingPermissionLabels.isNotEmpty)
              _RecoveryDetailRow(
                label: 'Missing permissions',
                value: summary.missingPermissionLabels.join(', '),
              ),
            if (summary.revokedPermissionLabels.isNotEmpty)
              _RecoveryDetailRow(
                label: 'Revoked permissions',
                value: summary.revokedPermissionLabels.join(', '),
              ),
            if (summary.helperSharedDiagnosticsStale)
              _RecoveryDetailRow(
                label: 'Helper diagnostics',
                value: summary.helperSharedDiagnosticsStaleReasons.isEmpty
                    ? 'stale'
                    : 'stale: ${summary.helperSharedDiagnosticsStaleReasons.join(', ')}',
              ),
            if (summary.helperPathMismatch)
              _RecoveryDetailRow(
                label: 'Helper path',
                value: summary.debugReleaseHelperMismatch
                    ? 'debug/release or standalone helper mismatch'
                    : 'mismatch',
              ),
            if (summary.helperUnreachable)
              const _RecoveryDetailRow(
                label: 'Helper reachability',
                value: 'unreachable',
              ),
            _RecoveryDetailRow(
              label: 'Permission owners',
              value: summary.mainAppPermissionPromptsBlocked
                  ? 'Accessibility and Screen & System Audio Recording via Caverno Computer Use'
                  : 'available for compatibility backend',
            ),
            _RecoveryDetailRow(
              label: 'Next recovery action',
              value: summary.nextAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryDetailRow extends StatelessWidget {
  const _RecoveryDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: textTheme.bodySmall)),
        ],
      ),
    );
  }
}
