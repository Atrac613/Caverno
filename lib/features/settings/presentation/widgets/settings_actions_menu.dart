import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/qr_scanner_page.dart';
import '../providers/settings_notifier.dart';
import 'qr_export_dialog.dart';

enum _SettingsAction { reset, import, export, importQr, exportQr }

/// Overflow menu with the settings-wide actions (import / export / reset / QR).
/// Shared by the full-screen [SettingsPage] app bar and the desktop settings
/// modal header so the logic lives in one place.
class SettingsActionsMenu extends ConsumerWidget {
  const SettingsActionsMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_SettingsAction>(
      onSelected: (action) {
        switch (action) {
          case _SettingsAction.reset:
            _resetToDefaults(context, ref);
            break;
          case _SettingsAction.import:
            _importSettings(context, ref);
            break;
          case _SettingsAction.export:
            _exportSettings(context, ref);
            break;
          case _SettingsAction.importQr:
            _importFromQr(context, ref);
            break;
          case _SettingsAction.exportQr:
            _exportToQr(context, ref);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _SettingsAction.import,
          child: Row(
            children: [
              const Icon(Icons.upload_file_outlined),
              const SizedBox(width: 12),
              Text('settings.import_settings'.tr()),
            ],
          ),
        ),
        PopupMenuItem(
          value: _SettingsAction.export,
          child: Row(
            children: [
              const Icon(Icons.file_download_outlined),
              const SizedBox(width: 12),
              Text('settings.export_settings'.tr()),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _SettingsAction.importQr,
          child: Row(
            children: [
              const Icon(Icons.qr_code_scanner),
              const SizedBox(width: 12),
              Text('settings.import_qr'.tr()),
            ],
          ),
        ),
        PopupMenuItem(
          value: _SettingsAction.exportQr,
          child: Row(
            children: [
              const Icon(Icons.qr_code),
              const SizedBox(width: 12),
              Text('settings.export_qr'.tr()),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _SettingsAction.reset,
          child: Row(
            children: [
              const Icon(Icons.restore, color: Colors.red),
              const SizedBox(width: 12),
              Text(
                'settings.reset_to_default'.tr(),
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _resetToDefaults(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.reset_title'.tr()),
        content: Text('settings.reset_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.reset'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(settingsNotifierProvider.notifier).resetToDefaults();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('settings.reset_done'.tr())));
      }
    }
  }

  Future<void> _importSettings(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.import_settings'.tr()),
        content: Text('settings.import_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('settings.import_settings'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await ref
            .read(settingsNotifierProvider.notifier)
            .importSettings();
        if (success && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('settings.import_done'.tr())));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('settings.import_error'.tr(args: [e.toString()])),
            ),
          );
        }
      }
    }
  }

  Future<void> _exportSettings(BuildContext context, WidgetRef ref) async {
    try {
      final path = await ref
          .read(settingsNotifierProvider.notifier)
          .exportSettings();
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('settings.export_done'.tr(args: [path]))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('settings.export_error'.tr(args: [e.toString()])),
          ),
        );
      }
    }
  }

  Future<void> _importFromQr(BuildContext context, WidgetRef ref) async {
    // Scan first, then ask for confirmation
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerPage()));

    if (result == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.import_qr'.tr()),
        content: Text('settings.qr_import_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('settings.import_settings'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(settingsNotifierProvider.notifier).importFromQr(result);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('settings.import_done'.tr())));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('settings.import_error'.tr(args: [e.toString()])),
            ),
          );
        }
      }
    }
  }

  Future<void> _exportToQr(BuildContext context, WidgetRef ref) async {
    final data = ref.read(settingsNotifierProvider.notifier).exportToQr();
    showDialog(
      context: context,
      builder: (context) => QrExportDialog(data: data),
    );
  }
}
