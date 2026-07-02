import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../providers/chat_state.dart';

class ParticipantToolApprovalSheet extends StatelessWidget {
  const ParticipantToolApprovalSheet({required this.pending, super.key});

  final PendingParticipantToolApproval pending;

  static Future<bool?> show(
    BuildContext context,
    PendingParticipantToolApproval pending,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ParticipantToolApprovalSheet(pending: pending),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleLabel = pending.participantRoleLabel.trim();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.manage_search_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'chat.participant_tool_approval_title'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'chat.participant_tool_approval_message'.tr(
                  namedArgs: {
                    'participant': pending.participantName,
                    'tool': pending.toolName,
                  },
                ),
                style: theme.textTheme.bodyMedium,
              ),
              if (roleLabel.isNotEmpty) ...[
                const SizedBox(height: 8),
                _participantToolApprovalRow(
                  theme,
                  Icons.badge_outlined,
                  roleLabel,
                ),
              ],
              if (pending.reason?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _participantToolApprovalRow(
                  theme,
                  Icons.help_outline,
                  pending.reason!.trim(),
                ),
              ],
              const SizedBox(height: 8),
              _participantToolApprovalRow(
                theme,
                Icons.data_object,
                _participantToolApprovalArgumentsPreview(pending),
                monospace: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('chat.participant_tool_approval_deny'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(
                        'chat.participant_tool_approval_approve'.tr(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _participantToolApprovalRow(
  ThemeData theme,
  IconData icon,
  String text, {
  bool monospace = false,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: monospace
              ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
              : theme.textTheme.bodyMedium,
        ),
      ),
    ],
  );
}

String _participantToolApprovalArgumentsPreview(
  PendingParticipantToolApproval pending,
) {
  const maxLength = 1200;
  final encoded = const JsonEncoder.withIndent('  ').convert(pending.arguments);
  if (encoded.length <= maxLength) {
    return encoded;
  }
  return '${encoded.substring(0, maxLength).trimRight()}\n...';
}
