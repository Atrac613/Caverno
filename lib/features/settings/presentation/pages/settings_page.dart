import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/local_diagnostics_exporter.dart';
import '../../../../core/services/macos_computer_use_audit_log.dart';
import '../../../../core/services/macos_computer_use_service.dart';
import '../../../../core/services/macos_computer_use_setup.dart';
import '../providers/settings_notifier.dart';
import '../widgets/computer_use_audit_log_summary.dart';
import '../widgets/qr_export_dialog.dart';
import 'computer_use_debug_page.dart';
import 'debug_settings_page.dart';
import 'general_settings_page.dart';
import 'chat_settings_page.dart';
import 'voice_settings_page.dart';
import 'tools_settings_page.dart';
import 'qr_scanner_page.dart';

enum _SettingsAction { reset, import, export, importQr, exportQr }

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
        actions: [
          PopupMenuButton<_SettingsAction>(
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
          ),
        ],
      ),
      body: ListView(
        children: [
          const _ComputerUseOnboardingCard(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text('settings.menu_general'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GeneralSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: Text('settings.menu_chat'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.mic_outlined),
            title: Text('settings.menu_voice'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VoiceSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.build_outlined),
            title: Text('settings.menu_tools'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ToolsSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text('settings.menu_debug'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebugSettingsPage()),
              );
            },
          ),
        ],
      ),
    );
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

class _ComputerUseOnboardingCard extends ConsumerStatefulWidget {
  const _ComputerUseOnboardingCard();

  @override
  ConsumerState<_ComputerUseOnboardingCard> createState() =>
      _ComputerUseOnboardingCardState();
}

class _ComputerUseOnboardingCardState
    extends ConsumerState<_ComputerUseOnboardingCard>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  Map<String, dynamic>? _helperStatus;
  Map<String, dynamic>? _permissions;
  Map<String, dynamic>? _lastStopResult;
  Map<String, dynamic>? _lastPermissionSettingsResult;
  Map<String, dynamic>? _lastLiveSmokeReport;
  String? _lastPrimaryActionLabel;
  String? _lastDiagnosticExportPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(macosComputerUseServiceProvider);
    if (!service.isAvailable) {
      return const SizedBox.shrink();
    }

    final checklist = _setupChecklist(service.permissionBackendInfo);
    final ready = checklist.isReady;
    final onboardingVerification = _onboardingVerification();
    final helperStatusPersistence = _helperStatusPersistence();
    final verificationOk = onboardingVerification?['ok'] == true;
    final verificationRan = onboardingVerification != null;
    final helperWorkActive = _helperWorkActive() == true;
    final hasPermissionSnapshot = _permissions != null || _helperStatus != null;
    final showAccessibilityCta =
        hasPermissionSnapshot &&
        _permissionValue('accessibilityGranted') != true;
    final showScreenRecordingCta =
        hasPermissionSnapshot &&
        _permissionValue('screenCaptureGranted') != true;
    final helperInstalled = _permissionValue('helperInstalled') == true;
    final helperRunning = _permissionValue('helperRunning') == true;
    final helperIpcReady = _permissionValue('helperReachable') == true;
    final accessibilityGranted =
        _permissionValue('accessibilityGranted') == true;
    final screenCaptureGranted =
        _permissionValue('screenCaptureGranted') == true;
    final primaryAction = _primaryAction(
      helperInstalled: helperInstalled,
      helperRunning: helperRunning,
      helperIpcReady: helperIpcReady,
      accessibilityGranted: accessibilityGranted,
      screenCaptureGranted: screenCaptureGranted,
      verificationOk: verificationOk,
    );
    final helperIpcRuntime = _helperIpcRuntime();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ready
                      ? Icons.verified_user_outlined
                      : Icons.ads_click_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ready ? 'Computer Use Ready' : 'Enable Computer Use',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        checklist.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh computer-use status',
                  onPressed: _isLoading ? null : _refresh,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PermissionFlowSummary(
              accessibilityGranted: accessibilityGranted,
              screenCaptureGranted: screenCaptureGranted,
              isLoading: _isLoading,
              onOpenAccessibility: () =>
                  _openPermissionSettings('accessibility'),
              onOpenScreenRecording: () =>
                  _openPermissionSettings('screen_recording'),
              onRecheck: () => _refresh(force: true),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  label: 'Helper App',
                  value: helperInstalled,
                  trueText: 'Installed',
                  falseText: 'Missing',
                ),
                _StatusChip(
                  label: 'Helper Process',
                  value: helperRunning,
                  trueText: 'Running',
                  falseText: helperInstalled ? 'Stopped' : 'Missing',
                ),
                _StatusChip(
                  label: 'IPC Ready',
                  value: helperIpcReady,
                  trueText: 'Reachable',
                  falseText: helperRunning ? 'Timeout' : 'Not ready',
                ),
                _StatusChip(
                  label: 'Accessibility',
                  value: accessibilityGranted,
                ),
                _StatusChip(
                  label: 'Screen & System Audio',
                  value: screenCaptureGranted,
                ),
                _StatusChip(
                  label: 'XPC Attempt',
                  value: MacosComputerUseIpc.current.xpcReady,
                  trueText: 'Enabled',
                  falseText: 'Disabled',
                ),
                _StatusChip(
                  label: 'Verify',
                  value: verificationOk,
                  trueText: 'Passed',
                  falseText: verificationRan ? 'Needs attention' : 'Not run',
                ),
                _StatusChip(
                  label: 'Helper Work',
                  value: !helperWorkActive,
                  trueText: 'Idle',
                  falseText: 'Active',
                ),
              ],
            ),
            if (onboardingVerification != null) ...[
              const SizedBox(height: 8),
              _VerificationSummary(verification: onboardingVerification),
            ],
            if (helperStatusPersistence != null) ...[
              const SizedBox(height: 8),
              _PersistenceSummary(persistence: helperStatusPersistence),
            ],
            const SizedBox(height: 8),
            _IpcRuntimeSummary(runtime: helperIpcRuntime),
            if (_lastLiveSmokeReport != null) ...[
              const SizedBox(height: 8),
              _LiveSmokeSummary(reportEnvelope: _lastLiveSmokeReport!),
            ],
            const SizedBox(height: 8),
            ComputerUseAuditLogSummary(
              entries: MacosComputerUseAuditLog.instance.redactedEntries,
              maxEntries: 3,
            ),
            const SizedBox(height: 12),
            Text(
              'Next action: ${primaryAction.detail}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (showAccessibilityCta || showScreenRecordingCta) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (showAccessibilityCta)
                    OutlinedButton.icon(
                      key: const ValueKey(
                        'computer-use-settings-open-accessibility',
                      ),
                      onPressed: _isLoading
                          ? null
                          : () => _openPermissionSettings('accessibility'),
                      icon: const Icon(Icons.accessibility_new_outlined),
                      label: const Text('Open Accessibility Settings'),
                    ),
                  if (showScreenRecordingCta)
                    OutlinedButton.icon(
                      key: const ValueKey(
                        'computer-use-settings-open-screen-recording',
                      ),
                      onPressed: _isLoading
                          ? null
                          : () => _openPermissionSettings('screen_recording'),
                      icon: const Icon(Icons.screenshot_monitor_outlined),
                      label: const Text('Open Screen Recording Settings'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('computer-use-settings-primary-action'),
                  onPressed: _isLoading
                      ? null
                      : () => _runPrimaryAction(primaryAction),
                  icon: Icon(primaryAction.icon),
                  label: Text(primaryAction.label),
                ),
                OutlinedButton.icon(
                  onPressed: _openSmokeTest,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Open Smoke Test'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'computer-use-settings-recheck-permissions',
                  ),
                  onPressed: _isLoading ? null : () => _refresh(force: true),
                  icon: const Icon(Icons.sync_outlined),
                  label: const Text('Recheck Permissions'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'computer-use-settings-register-xpc-agent',
                  ),
                  onPressed: _isLoading ? null : _registerXpcLaunchAgent,
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('Register XPC Agent'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'computer-use-settings-unregister-xpc-agent',
                  ),
                  onPressed: _isLoading ? null : _unregisterXpcLaunchAgent,
                  icon: const Icon(Icons.link_off_outlined),
                  label: const Text('Unregister XPC Agent'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('computer-use-settings-stop-helper-work'),
                  onPressed: _isLoading ? null : _stopHelperWork,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Helper Work'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('computer-use-settings-copy-diagnostics'),
                  onPressed: _copyDiagnostics,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy Diagnostics'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'computer-use-settings-export-diagnostics',
                  ),
                  onPressed: _exportDiagnostics,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export Diagnostics'),
                ),
              ],
            ),
            if (_lastStopResult != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last stop: ${_resultSummary(_lastStopResult!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_lastPermissionSettingsResult != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last permission action: ${_permissionActionSummary(_lastPermissionSettingsResult!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_lastDiagnosticExportPath != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last export: $_lastDiagnosticExportPath',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  _ComputerUsePrimaryAction _primaryAction({
    required bool helperInstalled,
    required bool helperRunning,
    required bool helperIpcReady,
    required bool accessibilityGranted,
    required bool screenCaptureGranted,
    required bool verificationOk,
  }) {
    if (!helperInstalled || !helperRunning) {
      return const _ComputerUsePrimaryAction(
        kind: _ComputerUsePrimaryActionKind.launch,
        label: 'Launch Computer Use',
        detail: 'Launch the helper app so macOS can attach permissions to it.',
        icon: Icons.rocket_launch_outlined,
      );
    }
    if (!helperIpcReady) {
      return const _ComputerUsePrimaryAction(
        kind: _ComputerUsePrimaryActionKind.restart,
        label: 'Restart Helper',
        detail: 'Restart the helper and wait for IPC readiness.',
        icon: Icons.restart_alt,
      );
    }
    if (!accessibilityGranted) {
      return const _ComputerUsePrimaryAction(
        kind: _ComputerUsePrimaryActionKind.openAccessibility,
        label: 'Open Accessibility',
        detail: 'Grant Accessibility to Caverno Computer Use.',
        icon: Icons.accessibility_new_outlined,
      );
    }
    if (!screenCaptureGranted) {
      return const _ComputerUsePrimaryAction(
        kind: _ComputerUsePrimaryActionKind.openScreenRecording,
        label: 'Open Screen Recording',
        detail:
            'Grant Screen & System Audio Recording to Caverno Computer Use.',
        icon: Icons.screenshot_monitor_outlined,
      );
    }
    if (!verificationOk) {
      return const _ComputerUsePrimaryAction(
        kind: _ComputerUsePrimaryActionKind.openSmokeTest,
        label: 'Run Smoke Check',
        detail: 'Run screenshot, window, input, and audio smoke checks.',
        icon: Icons.fact_check_outlined,
      );
    }
    return const _ComputerUsePrimaryAction(
      kind: _ComputerUsePrimaryActionKind.launch,
      label: 'Open Computer Use',
      detail: 'Open the helper when you want to review permissions.',
      icon: Icons.open_in_new,
    );
  }

  Future<void> _runPrimaryAction(_ComputerUsePrimaryAction action) async {
    setState(() => _lastPrimaryActionLabel = action.label);
    switch (action.kind) {
      case _ComputerUsePrimaryActionKind.launch:
        await _launchHelper();
      case _ComputerUsePrimaryActionKind.restart:
        await _restartHelper();
      case _ComputerUsePrimaryActionKind.openAccessibility:
        await _openPermissionSettings('accessibility');
      case _ComputerUsePrimaryActionKind.openScreenRecording:
        await _openPermissionSettings('screen_recording');
      case _ComputerUsePrimaryActionKind.openSmokeTest:
        _openSmokeTest();
    }
  }

  Future<void> _launchHelper() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final helper = _decodeMap(await service.launchHelper());
      if (!mounted) {
        return;
      }
      setState(() {
        if (helper != null) {
          _helperStatus = {...?_helperStatus, ...helper};
        }
      });
      final readiness = _decodeMap(await service.waitForHelperIpcReady());
      if (!mounted) {
        return;
      }
      setState(() {
        if (readiness != null) {
          _helperStatus = {...?_helperStatus, ...readiness};
        }
      });
      await _refresh(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        await _refresh(force: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restartHelper() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final helper = _decodeMap(await service.restartHelper());
      if (!mounted) {
        return;
      }
      setState(() {
        if (helper != null) {
          _helperStatus = {...?_helperStatus, ...helper};
        }
      });
      final readiness = _decodeMap(await service.waitForHelperIpcReady());
      if (!mounted) {
        return;
      }
      setState(() {
        if (readiness != null) {
          _helperStatus = {...?_helperStatus, ...readiness};
        }
      });
      await _refresh(force: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _stopHelperWork() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final result = _decodeMap(await service.stopHelperWork());
      if (!mounted) {
        return;
      }
      setState(() {
        _lastPrimaryActionLabel = null;
        _lastStopResult = result ?? {'ok': false, 'error': 'Invalid response'};
      });
      await _refresh(force: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _registerXpcLaunchAgent() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final result = _decodeMap(await service.registerXpcLaunchAgent());
      if (!mounted) {
        return;
      }
      setState(() {
        _lastPrimaryActionLabel = null;
        if (result != null) {
          _helperStatus = {...?_helperStatus, ...result};
        }
      });
      await _refresh(force: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unregisterXpcLaunchAgent() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final result = _decodeMap(await service.unregisterXpcLaunchAgent());
      if (!mounted) {
        return;
      }
      setState(() {
        _lastPrimaryActionLabel = null;
        if (result != null) {
          _helperStatus = {...?_helperStatus, ...result};
        }
      });
      await _refresh(force: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openPermissionSettings(String section) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final result = _decodeMap(
        await service.openSystemSettings(section: section),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastPrimaryActionLabel = null;
        _lastPermissionSettingsResult =
            result ??
            {'ok': false, 'section': section, 'error': 'Invalid response'};
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        await _refresh(force: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (_isLoading && !force) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final nextHelperStatus = <String, dynamic>{...?_helperStatus};
      for (final raw in [
        await service.getHelperStatus(),
        await service.pingHelper(),
      ]) {
        final decoded = _decodeMap(raw);
        if (decoded != null) {
          nextHelperStatus.addAll(decoded);
        }
      }
      final nextPermissions = _decodeMap(await service.getPermissions());
      final nextLiveSmokeReport = _liveSmokeReportFrom(
        _decodeMap(await service.getLastLiveSmokeReport()),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _helperStatus = nextHelperStatus;
        if (nextPermissions != null) {
          _permissions = nextPermissions;
        }
        _lastLiveSmokeReport = nextLiveSmokeReport;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openSmokeTest() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ComputerUseDebugPage()),
    ).then((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  Future<void> _copyDiagnostics() async {
    final diagnostics = _diagnosticsJson();
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Computer-use diagnostics copied.')),
    );
  }

  Future<void> _exportDiagnostics() async {
    try {
      final diagnostics = _diagnosticsJson();
      final path = await exportLocalDiagnostics(
        filePrefix: 'caverno-computer-use-onboarding',
        contents: diagnostics,
      );
      if (!mounted) {
        return;
      }
      setState(() => _lastDiagnosticExportPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Computer-use diagnostics exported to $path')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _lastDiagnosticExportPath = 'Failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export diagnostics: $error')),
      );
    }
  }

  String _diagnosticsJson() {
    return const JsonEncoder.withIndent('  ').convert(_diagnosticsMap());
  }

  Map<String, dynamic> _diagnosticsMap() {
    return MacosComputerUseOnboardingDiagnostics(
      generatedAt: DateTime.now(),
      setupChecklist: _setupChecklist(
        ref.read(macosComputerUseServiceProvider).permissionBackendInfo,
      ),
      onboardingSmokeChecklist: _onboardingSmokeChecklist(),
      onboardingVerification: _onboardingVerification(),
      helperStatus: _helperStatus,
      helperStatusPersistence: _helperStatusPersistence(),
      permissions: _permissions,
      helperIpcProtocol: MacosComputerUseIpc.current.toJson(),
      helperIpcRuntime: _helperIpcRuntime(),
      auditLog: MacosComputerUseAuditLog.instance.redactedEntries,
      lastAction: _lastActionLabel(),
      lastResult: {
        'helperStatus': _helperStatus,
        'helperStatusPersistence': _helperStatusPersistence(),
        'permissions': _permissions,
        'helperIpcRuntime': _helperIpcRuntime(),
        'onboardingVerification': _onboardingVerification(),
        'lastLiveSmokeReport': _lastLiveSmokeReport,
        'lastStopResult': _lastStopResult,
        'lastPermissionSettingsResult': _lastPermissionSettingsResult,
      },
      lastLiveSmokeReport: _lastLiveSmokeReport,
      lastDiagnosticExportPath: _lastDiagnosticExportPath,
    ).toJson();
  }

  List<Map<String, dynamic>> _onboardingSmokeChecklist() {
    return [
      {
        'id': 'launch_helper',
        'label': 'Launch Caverno Computer Use',
        'complete':
            _permissionValue('helperInstalled') == true &&
            _permissionValue('helperRunning') == true,
      },
      {
        'id': 'verify_helper_ipc',
        'label': 'Verify helper IPC reachability',
        'complete': _permissionValue('helperReachable') == true,
      },
      {
        'id': 'grant_accessibility',
        'label': 'Grant Accessibility to Caverno Computer Use',
        'complete': _permissionValue('accessibilityGranted') == true,
      },
      {
        'id': 'grant_screen_recording',
        'label':
            'Grant Screen & System Audio Recording to Caverno Computer Use',
        'complete': _permissionValue('screenCaptureGranted') == true,
      },
      {
        'id': 'run_live_smoke',
        'label': 'Run helper smoke checks',
        'complete': _lastLiveSmokeReport?['ok'] == true,
      },
    ];
  }

  MacosComputerUseSetupChecklist _setupChecklist(
    MacosComputerUseBackendInfo backend,
  ) {
    final snapshot = <String, dynamic>{};
    if (_permissions != null) {
      snapshot.addAll(_permissions!);
    }
    if (_helperStatus != null) {
      snapshot.addAll(_helperStatus!);
    }
    return MacosComputerUseSetupChecklist(
      backend: backend,
      permissions: snapshot.isEmpty
          ? null
          : MacosComputerUsePermissionSnapshot.fromMap(snapshot),
    );
  }

  bool? _permissionValue(String key) {
    final permissions = _permissions;
    final helperStatus = _helperStatus;
    final value = permissions?[key] ?? helperStatus?[key];
    return value is bool ? value : null;
  }

  bool? _helperWorkActive() {
    final value =
        _helperStatus?['audioRecordingActive'] ??
        _permissions?['audioRecordingActive'];
    if (value is bool) {
      return value;
    }
    final activeWork = _helperStatusPersistence()?['activeWork'];
    if (activeWork is Map) {
      final systemAudioRecording = activeWork['systemAudioRecording'];
      if (systemAudioRecording is bool) {
        return systemAudioRecording;
      }
    }
    return null;
  }

  Map<String, dynamic>? _onboardingVerification() {
    final value =
        _helperStatus?['onboardingVerification'] ??
        _permissions?['onboardingVerification'];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  Map<String, dynamic>? _helperStatusPersistence() {
    final value =
        _helperStatus?['helperStatusPersistence'] ??
        _permissions?['helperStatusPersistence'];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  Map<String, dynamic>? _liveSmokeReportFrom(Map<String, dynamic>? decoded) {
    if (decoded == null) {
      return null;
    }
    if (decoded['ok'] == true) {
      return decoded;
    }
    if (decoded['report'] is Map) {
      return decoded;
    }
    return null;
  }

  Map<String, dynamic> _helperIpcRuntime() {
    final snapshot = <String, dynamic>{};
    if (_permissions != null) {
      snapshot.addAll(_permissions!);
    }
    if (_helperStatus != null) {
      snapshot.addAll(_helperStatus!);
    }
    final preferredAttempt =
        _mapValue(snapshot['preferredIpcAttempt']) ??
        _mapValue(snapshot['lastPreferredIpcAttempt']);
    final selectedTransport =
        _stringValue(snapshot['selectedIpcTransport']) ??
        _stringValue(snapshot['ipcTransport']) ??
        MacosComputerUseIpc.current.transport;
    final preferredTransport =
        _stringValue(snapshot['preferredIpcTransport']) ??
        MacosComputerUseIpc.current.preferredTransport;
    final fallbackTransport =
        _stringValue(snapshot['fallbackIpcTransport']) ??
        MacosComputerUseIpc.current.fallbackTransport;
    final preferredAttemptStatus = _stringValue(preferredAttempt?['status']);
    final preferredAttemptErrorCode = _stringValue(
      preferredAttempt?['errorCode'],
    );
    final nextParityCommands = _stringListValue(
      snapshot['xpcNextParityCommands'] ??
          MacosComputerUseIpc.current.xpcNextParityCommands,
    );
    final launchAgentStatus = _stringValue(snapshot['xpcLaunchAgentStatus']);
    final launchAgentPlistInstalled =
        snapshot['xpcLaunchAgentPlistInstalled'] == true;
    final launchAgentRegistered =
        snapshot['xpcLaunchAgentEnabled'] == true ||
        snapshot['xpcLaunchAgentRegistered'] == true ||
        launchAgentStatus == 'enabled';
    final namedServiceConnected =
        preferredAttemptStatus == 'xpc_response' ||
        selectedTransport == MacosComputerUseIpc.current.preferredTransport;
    final productionBlockers = [
      if (snapshot['xpcLaunchAgentPlistInstalled'] == false)
        'launch_agent_plist_missing',
      if (!launchAgentRegistered) 'launchd_mach_service_registration_missing',
      if (!namedServiceConnected) 'named_xpc_service_not_connected',
      if (nextParityCommands.isNotEmpty) 'command_parity_pending',
    ];
    final measuredProductionReady = productionBlockers.isEmpty;
    final productionNextAction = measuredProductionReady
        ? 'XPC is production ready.'
        : 'Resolve XPC production blockers before marking production ready.';
    final productionGate = <String, dynamic>{
      'productionReady': measuredProductionReady,
      'namedServiceConnected': namedServiceConnected,
      'launchAgentPlistInstalled': launchAgentPlistInstalled,
      'launchAgentRegistered': launchAgentRegistered,
      'commandParityComplete': nextParityCommands.isEmpty,
      'nextParityCommands': nextParityCommands,
      'blockers': productionBlockers,
      'nextAction': productionNextAction,
    };
    if (launchAgentStatus != null) {
      productionGate['launchAgentStatus'] = launchAgentStatus;
    }
    final runtime = <String, dynamic>{
      'selectedIpcTransport': selectedTransport,
      'preferredIpcTransport': preferredTransport,
      'fallbackIpcTransport': fallbackTransport,
      'xpcReady': snapshot['xpcReady'] ?? MacosComputerUseIpc.current.xpcReady,
      'xpcProductionReady': measuredProductionReady,
      'xpcProductionReadyMeasured': measuredProductionReady,
      'xpcNamedServiceConnected': namedServiceConnected,
      'xpcStatus':
          snapshot['xpcStatus'] ?? MacosComputerUseIpc.current.xpcStatus,
      'xpcConnectionMode':
          snapshot['xpcConnectionMode'] ??
          MacosComputerUseIpc.current.xpcConnectionMode,
      'xpcLaunchAgentPlistName':
          snapshot['xpcLaunchAgentPlistName'] ??
          MacosComputerUseIpc.current.xpcLaunchAgentPlistName,
      'xpcLaunchAgentRelativePath':
          snapshot['xpcLaunchAgentRelativePath'] ??
          MacosComputerUseIpc.current.xpcLaunchAgentRelativePath,
      'xpcLaunchAgentPlistInstalled': snapshot['xpcLaunchAgentPlistInstalled'],
      'xpcLaunchAgentSupported': snapshot['xpcLaunchAgentSupported'],
      'xpcLaunchAgentStatus': snapshot['xpcLaunchAgentStatus'],
      'xpcLaunchAgentEnabled': snapshot['xpcLaunchAgentEnabled'],
      'xpcLaunchAgentRegistered': launchAgentRegistered,
      'xpcLaunchAgentRequiresApproval':
          snapshot['xpcLaunchAgentRequiresApproval'],
      'xpcRegistrationRequirement':
          snapshot['xpcRegistrationRequirement'] ??
          MacosComputerUseIpc.current.xpcRegistrationRequirement,
      'xpcProductionBlockers': productionBlockers,
      'xpcProductionNextAction': productionNextAction,
      'mainAppUnsafeOsActionsAllowed':
          snapshot['mainAppUnsafeOsActionsAllowed'] ??
          MacosComputerUseIpc.current.mainAppUnsafeOsActionsAllowed,
      'helperOwnsUnsafeOsActions':
          snapshot['helperOwnsUnsafeOsActions'] ??
          MacosComputerUseIpc.current.helperOwnsUnsafeOsActions,
      'helperOwnedActionCategories':
          snapshot['helperOwnedActionCategories'] ??
          MacosComputerUseIpc.current.helperOwnedActionCategories,
      'xpcSupportedCommands':
          snapshot['xpcSupportedCommands'] ??
          MacosComputerUseIpc.current.xpcSupportedCommands,
      'xpcNextParityCommands': nextParityCommands,
      'xpcProductionGate': productionGate,
      'xpcProductionReadinessCriteria':
          snapshot['xpcProductionReadinessCriteria'] ??
          MacosComputerUseIpc.current.xpcProductionReadinessCriteria,
      'xpcServiceName':
          snapshot['xpcServiceName'] ??
          MacosComputerUseIpc.current.xpcServiceName,
      'preferredFallbackActive':
          selectedTransport == fallbackTransport &&
          preferredAttempt != null &&
          preferredTransport != fallbackTransport,
    };
    if (preferredAttemptStatus != null) {
      runtime['preferredAttemptStatus'] = preferredAttemptStatus;
    }
    if (preferredAttemptErrorCode != null) {
      runtime['preferredAttemptErrorCode'] = preferredAttemptErrorCode;
    }
    if (runtime['preferredFallbackActive'] == true &&
        preferredAttemptStatus != null) {
      runtime['preferredFallbackReason'] = preferredAttemptErrorCode == null
          ? preferredAttemptStatus
          : '$preferredAttemptStatus ($preferredAttemptErrorCode)';
    }
    return runtime;
  }

  List<String> _stringListValue(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String? _stringValue(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  String _resultSummary(Map<String, dynamic> result) {
    final ok = result['ok'] == true;
    final code = result['code'];
    final error = result['error'];
    if (ok) {
      final stoppedAudioRecording = result['stoppedAudioRecording'];
      final cancelledInputEvents = result['cancelledInputEvents'];
      return 'ok, audio stopped: $stoppedAudioRecording, input cancelled: $cancelledInputEvents';
    }
    if (code != null || error != null) {
      return '${code ?? 'failed'}: ${error ?? 'Unknown error'}';
    }
    return ok ? 'ok' : 'failed';
  }

  String _permissionActionSummary(Map<String, dynamic> result) {
    final section = result['section'] ?? 'unknown';
    final ok = result['ok'] == true;
    final error = result['error'];
    if (ok) {
      return 'opened $section';
    }
    return 'failed to open $section${error == null ? '' : ': $error'}';
  }

  String _lastActionLabel() {
    if (_lastPrimaryActionLabel != null) {
      return 'Settings primary action: $_lastPrimaryActionLabel';
    }
    if (_lastStopResult != null) {
      return 'Settings stop helper work';
    }
    if (_lastPermissionSettingsResult != null) {
      return 'Settings open permission pane';
    }
    return 'Settings onboarding status';
  }

  Map<String, dynamic>? _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

enum _ComputerUsePrimaryActionKind {
  launch,
  restart,
  openAccessibility,
  openScreenRecording,
  openSmokeTest,
}

class _ComputerUsePrimaryAction {
  const _ComputerUsePrimaryAction({
    required this.kind,
    required this.label,
    required this.detail,
    required this.icon,
  });

  final _ComputerUsePrimaryActionKind kind;
  final String label;
  final String detail;
  final IconData icon;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    this.trueText = 'Ready',
    this.falseText = 'Missing',
  });

  final String label;
  final bool value;
  final String trueText;
  final String falseText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = value ? colorScheme.primary : colorScheme.outline;
    return Chip(
      avatar: Icon(
        value ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        size: 18,
        color: color,
      ),
      label: Text('$label: ${value ? trueText : falseText}'),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
      label: Text('$label: $value'),
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

class _IpcRuntimeSummary extends StatelessWidget {
  const _IpcRuntimeSummary({required this.runtime});

  final Map<String, dynamic> runtime;

  @override
  Widget build(BuildContext context) {
    final selected = '${runtime['selectedIpcTransport']}';
    final preferred = '${runtime['preferredIpcTransport']}';
    final fallback = '${runtime['fallbackIpcTransport']}';
    final preferredAttemptStatus = runtime['preferredAttemptStatus'];
    final preferredAttemptErrorCode = runtime['preferredAttemptErrorCode'];
    final helperOwnsUnsafeOsActions =
        runtime['helperOwnsUnsafeOsActions'] == true;
    final mainAppUnsafeOsActionsAllowed =
        runtime['mainAppUnsafeOsActionsAllowed'] == true;
    final fallbackActive = runtime['preferredFallbackActive'] == true;
    final status = fallbackActive
        ? 'preferred XPC fell back to $fallback'
        : 'using $selected';
    final fallbackReason = runtime['preferredFallbackReason'];
    final supportedCommands = _stringList(runtime['xpcSupportedCommands']);
    final nextParityCommands = _stringList(runtime['xpcNextParityCommands']);
    final productionBlockers = _stringList(runtime['xpcProductionBlockers']);
    final launchAgentStatus = runtime['xpcLaunchAgentStatus'];
    final launchAgentPlistInstalled = runtime['xpcLaunchAgentPlistInstalled'];
    final productionReady = runtime['xpcProductionReadyMeasured'] == true;
    final namedServiceConnected = runtime['xpcNamedServiceConnected'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IPC runtime: $status',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(label: 'Active IPC', value: selected),
            _InfoChip(label: 'Preferred IPC', value: preferred),
            if (supportedCommands.isNotEmpty)
              _InfoChip(
                label: 'XPC commands',
                value: supportedCommands.join(', '),
              ),
            _InfoChip(label: 'XPC status', value: '${runtime['xpcStatus']}'),
            _InfoChip(
              label: 'XPC connection',
              value: '${runtime['xpcConnectionMode']}',
            ),
            _InfoChip(
              label: 'XPC registration',
              value: '${runtime['xpcRegistrationRequirement']}',
            ),
            if (launchAgentStatus != null)
              _InfoChip(label: 'LaunchAgent', value: '$launchAgentStatus'),
            if (launchAgentPlistInstalled is bool)
              _InfoChip(
                label: 'LaunchAgent plist',
                value: launchAgentPlistInstalled ? 'installed' : 'missing',
              ),
            _InfoChip(
              label: 'XPC gate',
              value: productionReady ? 'ready' : 'blockers',
            ),
            _InfoChip(
              label: 'Named XPC',
              value: namedServiceConnected ? 'connected' : 'fallback',
            ),
            if (productionBlockers.isNotEmpty)
              _InfoChip(
                label: 'XPC blockers',
                value: productionBlockers.join(', '),
              ),
            _InfoChip(
              label: 'XPC next action',
              value: '${runtime['xpcProductionNextAction']}',
            ),
            _InfoChip(
              label: 'OS action owner',
              value: helperOwnsUnsafeOsActions ? 'helper' : 'main app',
            ),
            _InfoChip(
              label: 'Main app OS actions',
              value: mainAppUnsafeOsActionsAllowed ? 'allowed' : 'blocked',
            ),
            if (preferredAttemptStatus is String)
              _InfoChip(
                label: 'Preferred attempt',
                value: preferredAttemptStatus,
              ),
            if (preferredAttemptErrorCode is String)
              _InfoChip(
                label: 'Preferred error',
                value: preferredAttemptErrorCode,
              ),
            if (fallbackReason is String)
              _InfoChip(label: 'Fallback reason', value: fallbackReason),
            _InfoChip(
              label: 'Next XPC parity',
              value: nextParityCommands.isEmpty
                  ? 'none'
                  : nextParityCommands.join(', '),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }
}

class _VerificationSummary extends StatelessWidget {
  const _VerificationSummary({required this.verification});

  final Map<String, dynamic> verification;

  @override
  Widget build(BuildContext context) {
    final generatedAt = verification['generatedAt'];
    final steps = verification['steps'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          generatedAt is String
              ? 'Last Verify: ${verification['summary'] ?? generatedAt}'
              : 'Last Verify: ${verification['summary'] ?? 'Unknown'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (steps is List) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final step in steps)
                if (step is Map)
                  _StatusChip(
                    label: '${step['label'] ?? step['id'] ?? 'Step'}',
                    value: step['ok'] == true,
                    trueText: 'Done',
                    falseText: '${step['status'] ?? 'Failed'}',
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PersistenceSummary extends StatelessWidget {
  const _PersistenceSummary({required this.persistence});

  final Map<String, dynamic> persistence;

  @override
  Widget build(BuildContext context) {
    final updatedAt = persistence['updatedAt'];
    final activeWork = persistence['activeWork'];
    final activeWorkLabels = <String>[];
    if (activeWork is Map) {
      for (final entry in activeWork.entries) {
        if (entry.value == true) {
          activeWorkLabels.add('${entry.key}');
        }
      }
    }
    final verification = persistence['onboardingVerification'];
    final hasVerification = verification is Map;
    final verificationOk = hasVerification && verification['ok'] == true;
    final hasActiveWork = activeWorkLabels.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Helper status saved: ${updatedAt is String ? updatedAt : 'Unknown'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              label: 'Saved Work',
              value: !hasActiveWork,
              trueText: 'Idle',
              falseText: 'Active',
            ),
            _StatusChip(
              label: 'Saved Verify',
              value: verificationOk,
              trueText: 'Passed',
              falseText: hasVerification ? 'Needs attention' : 'Not saved',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Saved active work: ${hasActiveWork ? activeWorkLabels.join(', ') : 'none'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LiveSmokeSummary extends StatelessWidget {
  const _LiveSmokeSummary({required this.reportEnvelope});

  final Map<String, dynamic> reportEnvelope;

  @override
  Widget build(BuildContext context) {
    final report = _report();
    final generatedAt = report['generatedAt'];
    final path = reportEnvelope['path'] ?? report['reportPath'];
    final ok = report['ok'] == true;
    final coreOk = report['coreOk'] == true;
    final captureOk = report['captureOk'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          generatedAt is String
              ? 'Last live smoke: ${ok ? 'passed' : 'needs attention'} at $generatedAt'
              : 'Last live smoke: ${ok ? 'passed' : 'needs attention'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              label: 'Live Core',
              value: coreOk,
              trueText: 'Passed',
              falseText: 'Needs attention',
            ),
            _StatusChip(
              label: 'Live Capture',
              value: captureOk,
              trueText: 'Passed',
              falseText: 'Needs attention',
            ),
          ],
        ),
        if (path is String && path.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Live smoke report: $path',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Map<String, dynamic> _report() {
    final report = reportEnvelope['report'];
    if (report is Map) {
      return Map<String, dynamic>.from(report);
    }
    return reportEnvelope;
  }
}
