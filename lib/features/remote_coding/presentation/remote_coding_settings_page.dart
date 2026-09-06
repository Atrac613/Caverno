import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_tokens.dart';
import '../domain/remote_coding_audit.dart';
import '../domain/remote_coding_grant_kinds.dart';
import '../data/remote_coding_diagnostics.dart';
import '../data/remote_coding_multi_device_evidence.dart';
import '../data/remote_coding_notification_relay_pairing.dart';
import '../data/remote_coding_support_packet.dart';
import '../domain/remote_coding_models.dart';
import 'remote_coding_server_notifier.dart';

class RemoteCodingSettingsPage extends ConsumerWidget {
  const RemoteCodingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remoteCodingServerProvider);
    final notifier = ref.read(remoteCodingServerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Remote Coding Host')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Enable Remote Coding Host'),
            subtitle: const Text('Allow paired mobile devices on this LAN.'),
            value: state.settings.enabled,
            onChanged: notifier.setEnabled,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(state.isRunning ? 'Running' : 'Stopped'),
                  if (state.activeUrl != null) ...[
                    const SizedBox(height: 4),
                    SelectableText(state.activeUrl!),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Active mobile sessions: ${state.activeConnectionCount}',
                  ),
                  Text(
                    'Paired devices: ${state.settings.pairedDevices.length}',
                  ),
                  if (state.error?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _showPairingDialog(context, ref),
                        icon: const Icon(Icons.qr_code),
                        label: const Text('Pair Mobile Device'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copySupportPacket(context, state),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy Support Packet'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showMultiDeviceEvidenceDialog(context, state),
                        icon: const Icon(Icons.devices_other),
                        label: const Text('Copy Multi-Device Evidence'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Paired Devices', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (state.settings.pairedDevices.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.phone_iphone),
                title: Text('No paired devices'),
              ),
            )
          else
            ...state.settings.pairedDevices.map(
              (device) => Card(
                child: ListTile(
                  leading: const Icon(Icons.phone_iphone),
                  title: Text(device.name),
                  subtitle: Text(
                    'Last seen ${device.lastSeenAt.toLocal()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (device.relayCredentialState ==
                          RemoteCodingRelayCredentialState.pendingRevocation)
                        IconButton(
                          icon: const Icon(Icons.sync_problem),
                          tooltip: 'Retry notification relay cleanup',
                          onPressed: notifier.retryPendingRelayLifecycle,
                        )
                      else
                        IconButton(
                          icon: Icon(
                            device.hasNotificationRelay
                                ? Icons.notifications_active_outlined
                                : Icons.notifications_outlined,
                          ),
                          tooltip: device.hasNotificationRelay
                              ? 'Replace notification relay credential'
                              : 'Enable completion notifications',
                          onPressed: () => _showNotificationRelayDialog(
                            context,
                            ref,
                            device.id,
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                          device.desktopOriginKinds.isEmpty
                              ? Icons.shield_outlined
                              : Icons.shield,
                        ),
                        tooltip: device.desktopOriginKinds.isEmpty
                            ? 'This device answers only its own requests'
                            : 'Answers ${device.desktopOriginKinds.length} of '
                                  "this Mac's own request kinds",
                        onPressed: () =>
                            _showDesktopOriginGrantDialog(context, ref, device),
                      ),
                      IconButton(
                        icon: const Icon(Icons.link_off),
                        tooltip: 'Revoke',
                        onPressed: () => notifier.revokeDevice(device.id),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          _AuditLogSection(state: state, notifier: notifier),
        ],
      ),
    );
  }

  Future<void> _showPairingDialog(BuildContext context, WidgetRef ref) async {
    final payload = await ref
        .read(remoteCodingServerProvider.notifier)
        .createPairingPayload();
    if (payload == null || !context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _RemoteCodingPairingDialog(payload: payload),
    );
    if (!context.mounted) {
      return;
    }
    ref
        .read(remoteCodingServerProvider.notifier)
        .cancelPairingPayload(payload.ticketId);
  }

  /// Edits which of this desktop's own interactions a device may answer.
  ///
  /// Separate from pairing, and empty by default. A paired device can already
  /// make this Mac run anything, by sending a message and approving the
  /// request it provokes — so what this grants is not new authority but the
  /// right to answer a question the desktop asked rather than one the device
  /// authored (SA-26). It is per kind so that letting a phone answer questions
  /// does not also let it approve shell commands.
  Future<void> _showDesktopOriginGrantDialog(
    BuildContext context,
    WidgetRef ref,
    RemoteCodingPairedDevice device,
  ) async {
    final granted = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _DesktopOriginGrantDialog(device: device),
    );
    if (granted == null) return;
    await ref
        .read(remoteCodingServerProvider.notifier)
        .setDeviceDesktopOriginKinds(device.id, granted);
  }

  Future<void> _showNotificationRelayDialog(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    final payload = await ref
        .read(remoteCodingServerProvider.notifier)
        .createNotificationRelayPairingPayload(deviceId);
    if (payload == null || !context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _NotificationRelayPairingDialog(payload: payload),
    );
    if (!context.mounted) {
      return;
    }
    ref
        .read(remoteCodingServerProvider.notifier)
        .cancelNotificationRelayPairingPayload(payload.challengeId);
  }

  Future<void> _copySupportPacket(
    BuildContext context,
    RemoteCodingServerState state,
  ) async {
    final diagnostics = RemoteCodingDiagnostics.serverSnapshot(
      state.settings,
      isRunning: state.isRunning,
      activeHost: state.activeHost,
      activeUrl: state.activeUrl,
      activeConnectionCount: state.activeConnectionCount,
      pairingPayload: state.pairingPayload,
      error: state.error,
      notificationDelivery: state.lastNotificationDelivery,
    );
    final supportPacket = RemoteCodingSupportPacket.build(
      side: RemoteCodingSupportPacketSide.desktop,
      diagnostics: diagnostics,
    );
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(supportPacket),
      ),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Remote coding support packet copied.')),
    );
  }

  Future<void> _showMultiDeviceEvidenceDialog(
    BuildContext context,
    RemoteCodingServerState state,
  ) async {
    final review = await showDialog<_MultiDeviceEvidenceReview>(
      context: context,
      builder: (_) => _MultiDeviceEvidenceDialog(
        pairedDeviceCount: state.settings.pairedDevices.length,
        activeConnectionCount: state.activeConnectionCount,
      ),
    );
    if (review == null) {
      return;
    }

    final evidence = RemoteCodingMultiDeviceEvidence.build(
      settings: state.settings,
      activeConnectionCount: state.activeConnectionCount,
      revokingOneDeviceKeepsOtherDeviceUsable:
          review.revokingOneDeviceKeepsOtherDeviceUsable,
      approvalsReachOnlyRemoteOriginTurns:
          review.approvalsReachOnlyRemoteOriginTurns,
    );
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(evidence)),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Remote coding multi-device evidence copied.'),
      ),
    );
  }
}

class _MultiDeviceEvidenceReview {
  const _MultiDeviceEvidenceReview({
    required this.revokingOneDeviceKeepsOtherDeviceUsable,
    required this.approvalsReachOnlyRemoteOriginTurns,
  });

  final bool revokingOneDeviceKeepsOtherDeviceUsable;
  final bool approvalsReachOnlyRemoteOriginTurns;
}

class _MultiDeviceEvidenceDialog extends StatefulWidget {
  const _MultiDeviceEvidenceDialog({
    required this.pairedDeviceCount,
    required this.activeConnectionCount,
  });

  final int pairedDeviceCount;
  final int activeConnectionCount;

  @override
  State<_MultiDeviceEvidenceDialog> createState() =>
      _MultiDeviceEvidenceDialogState();
}

class _MultiDeviceEvidenceDialogState
    extends State<_MultiDeviceEvidenceDialog> {
  bool _revocationConfirmed = false;
  bool _approvalBoundaryConfirmed = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Copy Multi-Device Evidence'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Paired devices'),
              trailing: Text('${widget.pairedDeviceCount}'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active mobile sessions'),
              trailing: Text('${widget.activeConnectionCount}'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _revocationConfirmed,
              onChanged: (value) {
                setState(() {
                  _revocationConfirmed = value ?? false;
                });
              },
              title: const Text('Revocation preserves another device'),
              subtitle: const Text(
                'One paired device was revoked while another stayed usable.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _approvalBoundaryConfirmed,
              onChanged: (value) {
                setState(() {
                  _approvalBoundaryConfirmed = value ?? false;
                });
              },
              title: const Text('Remote approvals stayed scoped'),
              subtitle: const Text(
                'Approvals appeared only on remote-origin turns.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(
              _MultiDeviceEvidenceReview(
                revokingOneDeviceKeepsOtherDeviceUsable: _revocationConfirmed,
                approvalsReachOnlyRemoteOriginTurns: _approvalBoundaryConfirmed,
              ),
            );
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy Evidence'),
        ),
      ],
    );
  }
}

class _RemoteCodingPairingDialog extends ConsumerStatefulWidget {
  const _RemoteCodingPairingDialog({required this.payload});

  final RemoteCodingPairingPayload payload;

  @override
  ConsumerState<_RemoteCodingPairingDialog> createState() =>
      _RemoteCodingPairingDialogState();
}

class _RemoteCodingPairingDialogState
    extends ConsumerState<_RemoteCodingPairingDialog> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _computeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _remaining = _computeRemaining();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _computeRemaining() {
    final remaining = widget.payload.expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RemoteCodingPairingPayload?>(
      remoteCodingServerProvider.select((state) => state.pairingPayload),
      (previous, next) {
        final wasCurrentTicket = previous?.ticketId == widget.payload.ticketId;
        final isCurrentTicket = next?.ticketId == widget.payload.ticketId;
        if (wasCurrentTicket && !isCurrentTicket && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
    );

    return AlertDialog(
      title: const Text('Pair Mobile Device'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 240,
              child: QrImageView(
                data: widget.payload.toQrData(),
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _remaining == Duration.zero
                  ? 'Pairing code expired'
                  : 'Expires in ${_formatDuration(_remaining)}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Expires at ${widget.payload.expiresAt.toLocal()}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _NotificationRelayPairingDialog extends ConsumerStatefulWidget {
  const _NotificationRelayPairingDialog({required this.payload});

  final RemoteCodingNotificationRelayPairingPayload payload;

  @override
  ConsumerState<_NotificationRelayPairingDialog> createState() =>
      _NotificationRelayPairingDialogState();
}

class _NotificationRelayPairingDialogState
    extends ConsumerState<_NotificationRelayPairingDialog> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _computeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _remaining = _computeRemaining());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _computeRemaining() {
    final remaining = widget.payload.expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RemoteCodingNotificationRelayPairingPayload?>(
      remoteCodingServerProvider.select((state) => state.relayPairingPayload),
      (previous, next) {
        final wasCurrent = previous?.challengeId == widget.payload.challengeId;
        final isCurrent = next?.challengeId == widget.payload.challengeId;
        if (wasCurrent && !isCurrent && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
    );
    return AlertDialog(
      title: const Text('Enable Completion Notifications'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 240,
              child: QrImageView(
                data: widget.payload.toQrData(),
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _remaining == Duration.zero
                  ? 'Notification code expired'
                  : 'Expires in ${_formatDuration(_remaining)}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Scan this code from the connected mobile device.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _DesktopOriginGrantDialog extends StatefulWidget {
  const _DesktopOriginGrantDialog({required this.device});

  final RemoteCodingPairedDevice device;

  @override
  State<_DesktopOriginGrantDialog> createState() =>
      _DesktopOriginGrantDialogState();
}

class _DesktopOriginGrantDialogState extends State<_DesktopOriginGrantDialog> {
  late final Set<String> _granted = {...widget.device.desktopOriginKinds};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Consequential kinds last, so "grant everything" is a scroll and a
    // decision rather than the first thing under the thumb.
    final kinds = [
      ...RemoteCodingGrantKinds.all.where(
        (kind) => !RemoteCodingGrantKinds.consequential.contains(kind),
      ),
      ...RemoteCodingGrantKinds.all.where(
        RemoteCodingGrantKinds.consequential.contains,
      ),
    ];
    return AlertDialog(
      title: Text('${widget.device.name}: this Mac\'s own requests'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This device already answers requests from turns it starts '
              'itself. Tick a kind to also let it answer one raised by a turn '
              'started here, at this Mac.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final kind in kinds)
                    CheckboxListTile(
                      dense: true,
                      value: _granted.contains(kind),
                      title: Text(RemoteCodingGrantKinds.label(kind)),
                      subtitle:
                          RemoteCodingGrantKinds.consequential.contains(kind)
                          ? Text(
                              'Can change this machine',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            )
                          : null,
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _granted.add(kind);
                        } else {
                          _granted.remove(kind);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => setState(_granted.clear),
          child: const Text('Grant nothing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _granted),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// What paired devices have decided on this desktop (SA-26, T4).
///
/// A paired device can approve commands that change this machine. Until this
/// existed the machine kept no account of which device approved what, so
/// "did I approve that, or the phone in my bag?" had no answer.
class _AuditLogSection extends StatelessWidget {
  const _AuditLogSection({required this.state, required this.notifier});

  static const int _visibleEntries = 20;

  final RemoteCodingServerState state;
  final RemoteCodingServerNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = state.auditLog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Remote decisions',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (entries.isNotEmpty)
              TextButton(
                onPressed: notifier.clearAuditLog,
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.history),
              title: Text('No paired device has answered anything yet'),
            ),
          )
        else ...[
          for (final entry in entries.take(_visibleEntries))
            Card(
              child: ListTile(
                leading: Icon(
                  switch (entry.outcome) {
                    RemoteCodingAuditOutcome.refused => Icons.block,
                    RemoteCodingAuditOutcome.resolved when entry.approved =>
                      Icons.check_circle_outline,
                    RemoteCodingAuditOutcome.resolved =>
                      Icons.do_not_disturb_on_outlined,
                  },
                  color: entry.outcome == RemoteCodingAuditOutcome.refused
                      ? theme.colorScheme.error
                      : null,
                ),
                title: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kMonoFontFamily),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.deviceName} · '
                      '${RemoteCodingGrantKinds.label(entry.kind)} · '
                      '${entry.at.toLocal()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // The line worth reading: a decision on a turn this Mac
                    // started is the authority SA-26 widened, and the only one
                    // that required a grant.
                    if (entry.isDesktopOrigin)
                      Text(
                        "Answered this Mac's own request",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    if (entry.refusedReason != null)
                      Text(
                        'Refused: ${entry.refusedReason}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    if (entry.warning != null)
                      Text(
                        entry.warning!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                ),
                isThreeLine: entry.isDesktopOrigin || entry.warning != null,
              ),
            ),
          if (entries.length > _visibleEntries)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${entries.length - _visibleEntries} older decisions kept but '
                'not shown.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}
