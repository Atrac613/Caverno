import 'dart:convert';

import 'package:flutter/material.dart';

import '../../providers/chat_state.dart';
import '../tool_perimeter_summary.dart';

class ComputerUseActionApprovalSheetResult {
  const ComputerUseActionApprovalSheetResult({
    required this.approved,
    required this.armed,
  });

  final bool approved;
  final bool armed;
}

class ComputerUseActionApprovalSheet extends StatefulWidget {
  const ComputerUseActionApprovalSheet({
    required this.pending,
    required this.stopHelperWork,
    super.key,
  });

  final PendingComputerUseAction pending;
  final Future<String> Function() stopHelperWork;

  static Future<ComputerUseActionApprovalSheetResult?> show(
    BuildContext context,
    PendingComputerUseAction pending, {
    required Future<String> Function() stopHelperWork,
  }) {
    return showModalBottomSheet<ComputerUseActionApprovalSheetResult>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ComputerUseActionApprovalSheet(
        pending: pending,
        stopHelperWork: stopHelperWork,
      ),
    );
  }

  @override
  State<ComputerUseActionApprovalSheet> createState() =>
      _ComputerUseActionApprovalSheetState();
}

class _ComputerUseActionApprovalSheetState
    extends State<ComputerUseActionApprovalSheet> {
  late bool _unsafeArmed;
  bool _stopInProgress = false;
  String? _stopStatus;

  @override
  void initState() {
    super.initState();
    _unsafeArmed = !widget.pending.requiresSmokeArming;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = widget.pending;
    final riskStyle = _computerUseRiskStyle(
      theme,
      pending.riskCategory,
      pending.toolName,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: riskStyle.containerColor.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        riskStyle.icon,
                        color: riskStyle.iconColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pending.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            pending.toolName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Chip(
                            avatar: Icon(
                              riskStyle.icon,
                              size: 16,
                              color: riskStyle.accentColor,
                            ),
                            label: Text(pending.riskLabel),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(
                              color: riskStyle.accentColor.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              ToolPerimeterSummary(toolName: pending.toolName),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('computer-use-approval-scroll'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              riskStyle.warningIcon,
                              size: 20,
                              color: riskStyle.accentColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pending.warningMessage,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (pending.reason != null &&
                          pending.reason!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pending.reason!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (pending.targetSummary != null ||
                          pending.targetDetails.isNotEmpty ||
                          pending.exactTextPreview != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer
                                  .withValues(alpha: 0.38),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.secondary.withValues(
                                  alpha: 0.22,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.control_camera_outlined,
                                      size: 18,
                                      color: theme.colorScheme.secondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Target review',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                                if (pending.targetSummary != null &&
                                    pending.targetSummary!.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    pending.targetSummary!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme
                                          .colorScheme
                                          .onSecondaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                if (pending.targetDetails.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  for (final detail in pending.targetDetails)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: SelectableText(
                                        detail,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSecondaryContainer
                                                  .withValues(alpha: 0.86),
                                              fontFamily: 'monospace',
                                            ),
                                      ),
                                    ),
                                ],
                                if (pending.exactTextPreview != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'Exact text (${pending.exactTextLength ?? pending.exactTextPreview!.length} characters)',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSecondaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    constraints: const BoxConstraints(
                                      maxHeight: 140,
                                    ),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface
                                          .withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.14),
                                      ),
                                    ),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        pending.exactTextPreview!,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          height: 1.35,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (pending.approvalBoundaries.isNotEmpty ||
                          pending.approvalBlockerCodes.isNotEmpty ||
                          pending.actionProposalNextAction != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outline.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.rule_folder_outlined,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Approval boundaries',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                                if (pending.approvalBoundaries.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final boundary
                                          in pending.approvalBoundaries)
                                        Chip(
                                          label: Text(
                                            _computerUseBoundaryLabel(boundary),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ],
                                if (pending
                                    .approvalBlockerCodes
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Blocked until: ${pending.approvalBlockerCodes.map(_computerUseBlockerLabel).join(', ')}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                if (pending.actionProposalNextAction != null &&
                                    pending
                                        .actionProposalNextAction!
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    pending.actionProposalNextAction!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (pending.visionObservationSummary != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.visibility_outlined,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Latest observation context',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        pending.visionObservationSummary!,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      if (pending
                                          .visionObservationDetails
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        for (final detail
                                            in pending.visionObservationDetails)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              detail,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onPrimaryContainer
                                                        .withValues(alpha: 0.8),
                                                    fontFamily: 'monospace',
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                pending.summary,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  height: 1.5,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              if (pending.details.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                for (final detail in pending.details)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '• ',
                                          style: TextStyle(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            height: 1.4,
                                          ),
                                        ),
                                        Expanded(
                                          child: SelectableText(
                                            detail,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 12,
                                              height: 1.4,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (pending.requiresSmokeArming) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Material(
                            color: Colors.transparent,
                            child: CheckboxListTile(
                              value: _unsafeArmed,
                              onChanged: (value) {
                                setState(() {
                                  _unsafeArmed = value ?? false;
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Arm this Computer Use action'),
                              subtitle: const Text(
                                'I understand this can control the Mac and should run now.',
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (!pending.emergencyStop) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _stopInProgress
                                  ? null
                                  : () async {
                                      setState(() {
                                        _stopInProgress = true;
                                        _stopStatus = null;
                                      });
                                      try {
                                        final result = await widget
                                            .stopHelperWork();
                                        final decoded = jsonDecode(result);
                                        final ok =
                                            decoded is Map &&
                                            decoded['ok'] != false;
                                        if (!context.mounted) {
                                          return;
                                        }
                                        setState(() {
                                          _stopStatus = ok
                                              ? 'Emergency stop sent.'
                                              : 'Emergency stop returned an error.';
                                        });
                                      } catch (error) {
                                        if (!context.mounted) {
                                          return;
                                        }
                                        setState(() {
                                          _stopStatus =
                                              'Emergency stop failed.';
                                        });
                                      } finally {
                                        if (context.mounted) {
                                          setState(() {
                                            _stopInProgress = false;
                                          });
                                        }
                                      }
                                    },
                              icon: _stopInProgress
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.stop_circle_outlined,
                                      size: 18,
                                    ),
                              label: const Text('Stop Computer Use'),
                            ),
                          ),
                        ),
                        if (_stopStatus != null) ...[
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _stopStatus!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  0,
                  24,
                  16 + MediaQuery.of(context).padding.bottom,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _stopInProgress
                            ? null
                            : () => Navigator.pop(
                                context,
                                ComputerUseActionApprovalSheetResult(
                                  approved: false,
                                  armed: _unsafeArmed,
                                ),
                              ),
                        icon: const Icon(Icons.block_rounded, size: 18),
                        label: const Text('Deny'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _unsafeArmed && !_stopInProgress
                            ? () => Navigator.pop(
                                context,
                                ComputerUseActionApprovalSheetResult(
                                  approved: true,
                                  armed: _unsafeArmed,
                                ),
                              )
                            : null,
                        icon: Icon(riskStyle.approveIcon, size: 20),
                        label: Text(pending.approveLabel),
                        style: FilledButton.styleFrom(
                          backgroundColor: riskStyle.buttonColor,
                          foregroundColor: riskStyle.buttonForegroundColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComputerUseRiskStyle {
  const ComputerUseRiskStyle({
    required this.icon,
    required this.warningIcon,
    required this.approveIcon,
    required this.containerColor,
    required this.iconColor,
    required this.accentColor,
    required this.buttonColor,
    required this.buttonForegroundColor,
  });

  final IconData icon;
  final IconData warningIcon;
  final IconData approveIcon;
  final Color containerColor;
  final Color iconColor;
  final Color accentColor;
  final Color buttonColor;
  final Color buttonForegroundColor;
}

ComputerUseRiskStyle _computerUseRiskStyle(
  ThemeData theme,
  String riskCategory,
  String toolName,
) {
  final scheme = theme.colorScheme;
  return switch (riskCategory) {
    'observe' => ComputerUseRiskStyle(
      icon: Icons.visibility_outlined,
      warningIcon: Icons.visibility_outlined,
      approveIcon: Icons.visibility_rounded,
      containerColor: scheme.primaryContainer,
      iconColor: scheme.onPrimaryContainer,
      accentColor: scheme.primary,
      buttonColor: scheme.primary,
      buttonForegroundColor: scheme.onPrimary,
    ),
    'sensitive' => ComputerUseRiskStyle(
      icon: Icons.graphic_eq_rounded,
      warningIcon: Icons.hearing_outlined,
      approveIcon: Icons.mic_rounded,
      containerColor: scheme.errorContainer,
      iconColor: scheme.onErrorContainer,
      accentColor: scheme.error,
      buttonColor: scheme.error,
      buttonForegroundColor: scheme.onError,
    ),
    'recovery' => ComputerUseRiskStyle(
      icon: Icons.health_and_safety_outlined,
      warningIcon: Icons.shield_outlined,
      approveIcon: Icons.stop_circle_outlined,
      containerColor: scheme.tertiaryContainer,
      iconColor: scheme.onTertiaryContainer,
      accentColor: scheme.tertiary,
      buttonColor: scheme.tertiary,
      buttonForegroundColor: scheme.onTertiary,
    ),
    'setup' => ComputerUseRiskStyle(
      icon: Icons.settings_suggest_outlined,
      warningIcon: Icons.info_outline_rounded,
      approveIcon: Icons.arrow_forward_rounded,
      containerColor: scheme.secondaryContainer,
      iconColor: scheme.onSecondaryContainer,
      accentColor: scheme.secondary,
      buttonColor: scheme.secondary,
      buttonForegroundColor: scheme.onSecondary,
    ),
    _ => ComputerUseRiskStyle(
      icon: switch (toolName) {
        'computer_type_text' || 'computer_press_key' => Icons.keyboard_rounded,
        'computer_switch_space' => Icons.swap_horiz_rounded,
        _ => Icons.ads_click_rounded,
      },
      warningIcon: Icons.warning_amber_rounded,
      approveIcon: Icons.check_rounded,
      containerColor: scheme.errorContainer,
      iconColor: scheme.onErrorContainer,
      accentColor: scheme.error,
      buttonColor: scheme.error,
      buttonForegroundColor: scheme.onError,
    ),
  };
}

String _computerUseBoundaryLabel(String boundary) {
  return switch (boundary) {
    'target' => 'Target',
    'exactText' => 'Exact text',
    'publicAction' => 'Public action',
    'systemAudio' => 'System audio',
    'secureField' => 'Secure field',
    'credential' => 'Credential',
    'payment' => 'Payment',
    'destructive' => 'Destructive action',
    _ => boundary,
  };
}

String _computerUseBlockerLabel(String blockerCode) {
  return switch (blockerCode) {
    'target_missing' => 'target selection',
    'exact_text_missing' => 'exact text',
    'separate_public_action_approval_required' =>
      'separate public action approval',
    'secure_field_target_blocked' => 'secure field target',
    'credential_target_blocked' => 'credential target',
    'payment_target_blocked' => 'payment target',
    'destructive_target_blocked' => 'destructive target',
    'action_policy_blocked' => 'target safety policy',
    _ => blockerCode,
  };
}
