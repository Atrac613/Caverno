import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/remote_coding_diagnostics.dart';
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
                        onPressed: () => _copyDiagnostics(context, state),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy Diagnostics'),
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
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off),
                    tooltip: 'Revoke',
                    onPressed: () => notifier.revokeDevice(device.id),
                  ),
                ),
              ),
            ),
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

  Future<void> _copyDiagnostics(
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
    );
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(diagnostics),
      ),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Remote coding diagnostics copied.')),
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
