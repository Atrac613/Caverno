import 'package:flutter/material.dart';

import '../../../../../core/services/ssh_host_key.dart';

class SshHostKeyApprovalSheet extends StatelessWidget {
  const SshHostKeyApprovalSheet({required this.decision, super.key});

  final SshHostKeyDecision decision;

  static Future<bool?> show(
    BuildContext context,
    SshHostKeyDecision decision,
  ) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SshHostKeyApprovalSheet(decision: decision),
    );
  }

  bool get _isMismatch => decision.verdict == SshHostKeyVerdict.mismatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presented = decision.presented;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    _isMismatch
                        ? Icons.gpp_maybe_outlined
                        : Icons.verified_user_outlined,
                    color: _isMismatch
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isMismatch
                          ? 'SSH host key changed'
                          : 'Trust this SSH host?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${presented.host}:${presented.port}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isMismatch
                    ? 'The presented key does not match the stored identity. '
                          'Replace it only if you expected this host to rotate '
                          'keys. A mismatch can also mean another machine is '
                          'answering for this name.'
                    : 'This host has not been trusted before. Compare the '
                          'fingerprint with the operator of the machine before '
                          'sending credentials.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_isMismatch && decision.stored != null) ...[
                const SizedBox(height: 16),
                _FingerprintBlock(
                  label: 'Stored',
                  identity: decision.stored!,
                ),
              ],
              const SizedBox(height: 12),
              _FingerprintBlock(
                label: _isMismatch ? 'Presented' : 'Fingerprint',
                identity: presented,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(_isMismatch ? 'Replace key' : 'Trust host'),
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

class _FingerprintBlock extends StatelessWidget {
  const _FingerprintBlock({required this.label, required this.identity});

  final String label;
  final SshKnownHostIdentity identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label (${identity.keyType})',
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        SelectableText(
          identity.fingerprint,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
