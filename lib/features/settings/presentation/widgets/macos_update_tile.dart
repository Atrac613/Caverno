import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/macos_update_service.dart';

/// Sparkle update status plus a manual check action.
///
/// Callers are responsible for hiding this tile on platforms where
/// [MacosUpdateService.isAvailable] is false: the service still answers there,
/// but only to say updates are unavailable, which is noise outside macOS.
class MacosUpdateTile extends StatefulWidget {
  const MacosUpdateTile({super.key, required this.service});

  final MacosUpdateService service;

  @override
  State<MacosUpdateTile> createState() => _MacosUpdateTileState();
}

class _MacosUpdateTileState extends State<MacosUpdateTile> {
  late Future<MacosUpdateStatus> _statusFuture;
  bool _checking = false;
  String? _lastMessage;

  @override
  void initState() {
    super.initState();
    _statusFuture = widget.service.getStatus();
  }

  @override
  void didUpdateWidget(MacosUpdateTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _statusFuture = widget.service.getStatus();
      _lastMessage = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MacosUpdateStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final title = Text('settings.macos_updates_title'.tr());
        final subtitle = Text(_subtitleFor(status, snapshot.hasError));
        return ListTile(
          key: const ValueKey('settings-macos-updates'),
          leading: const Icon(Icons.system_update_alt_outlined),
          title: title,
          subtitle: subtitle,
          trailing: TextButton(
            onPressed: status != null && status.configured && !_checking
                ? _checkForUpdates
                : null,
            child: _checking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('settings.macos_updates_check'.tr()),
          ),
        );
      },
    );
  }

  String _subtitleFor(MacosUpdateStatus? status, bool hasError) {
    if (hasError) {
      return 'settings.macos_updates_status_failed'.tr();
    }
    if (status == null) {
      return 'settings.macos_updates_status_loading'.tr();
    }
    if (!status.available) {
      return status.nextAction ??
          'settings.macos_updates_status_unavailable'.tr();
    }
    if (!status.configured) {
      return status.nextAction ??
          'settings.macos_updates_status_unconfigured'.tr();
    }
    final version = status.displayVersion.isEmpty
        ? 'unknown'
        : status.displayVersion;
    final message = _lastMessage;
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return 'settings.macos_updates_status_configured'.tr(
      namedArgs: {
        'version': version,
        'interval': status.updateCheckIntervalSeconds.round().toString(),
      },
    );
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _lastMessage = null;
    });

    try {
      final status = await widget.service.checkForUpdates();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusFuture = Future<MacosUpdateStatus>.value(status);
        _lastMessage = 'settings.macos_updates_check_started'.tr();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastMessage = 'settings.macos_updates_check_failed'.tr(
          namedArgs: {'error': error.toString()},
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }
}
