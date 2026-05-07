import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/local_diagnostics_exporter.dart';
import '../../../../core/services/macos_computer_use_audit_log.dart';
import '../../../../core/services/macos_computer_use_service.dart';
import '../../../../core/services/macos_computer_use_setup.dart';
import '../../../../core/services/macos_computer_use_xpc_timing_report.dart';
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
            key: const ValueKey('settings-menu-computer-use'),
            leading: const Icon(Icons.desktop_windows_outlined),
            title: Text('settings.menu_computer_use'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ComputerUseSettingsPage(),
                ),
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

class ComputerUseSettingsPage extends StatelessWidget {
  const ComputerUseSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_computer_use'.tr())),
      body: ListView(
        children: const [_ComputerUseOnboardingCard(), SizedBox(height: 16)],
      ),
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
  Map<String, dynamic>? _lastLaunchResult;
  Map<String, dynamic>? _lastStopResult;
  Map<String, dynamic>? _lastPermissionSettingsResult;
  Map<String, dynamic>? _lastPermissionOverlayResult;
  Map<String, dynamic>? _lastLiveSmokeReport;
  Map<String, dynamic>? _lastExistingHelperProbeReport;
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
    );
    final helperIpcRuntime = _helperIpcRuntime();
    final captureGate = _mapValue(helperIpcRuntime['captureGate']);
    final inputGate = _mapValue(helperIpcRuntime['inputGate']);
    final audioGate = _mapValue(helperIpcRuntime['audioGate']);
    final overlaySmoke = _mapValue(helperIpcRuntime['overlaySmoke']);
    final unsafeActionGate = _mapValue(helperIpcRuntime['unsafeActionGate']);
    final xpcLaunchAgentRegistered =
        helperIpcRuntime['xpcLaunchAgentRegistered'] == true;
    final xpcLaunchAgentSupported =
        helperIpcRuntime['xpcLaunchAgentSupported'] != false;
    final xpcTimingSummary = _xpcTimingSummary(helperIpcRuntime);

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
            _ComputerUseGatePlan(
              helperInstalled: helperInstalled,
              helperRunning: helperRunning,
              helperIpcReady: helperIpcReady,
              accessibilityGranted: accessibilityGranted,
              screenCaptureGranted: screenCaptureGranted,
              captureGate: captureGate,
              inputGate: inputGate,
              audioGate: audioGate,
              overlaySmoke: overlaySmoke,
              unsafeActionGate: unsafeActionGate,
              hasLiveSmokeReport: _lastLiveSmokeReport != null,
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
            if (xpcTimingSummary['classification'] !=
                'missing_preferred_attempt') ...[
              const SizedBox(height: 8),
              _XpcTimingSummary(summary: xpcTimingSummary),
            ],
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
                if (helperInstalled &&
                    primaryAction.kind != _ComputerUsePrimaryActionKind.launch)
                  OutlinedButton.icon(
                    key: const ValueKey(
                      'computer-use-settings-open-computer-use',
                    ),
                    onPressed: _isLoading ? null : _launchHelper,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open Computer Use'),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'computer-use-settings-open-smoke-sequence',
                  ),
                  onPressed: _openSmokeTest,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Open Smoke Sequence'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'computer-use-settings-recheck-permissions',
                  ),
                  onPressed: _isLoading ? null : () => _refresh(force: true),
                  icon: const Icon(Icons.sync_outlined),
                  label: const Text('Recheck Permissions'),
                ),
                if (helperIpcRuntime['xpcLaunchAgentStatus'] != null &&
                    helperIpcRuntime['xpcLaunchAgentPlistInstalled'] == true &&
                    (xpcLaunchAgentRegistered ||
                        helperIpcRuntime['xpcNamedServiceConnected'] != true) &&
                    helperIpcRuntime['xpcLaunchAgentRequiresApproval'] != true)
                  OutlinedButton.icon(
                    key: xpcLaunchAgentRegistered
                        ? const ValueKey(
                            'computer-use-settings-unregister-xpc-agent',
                          )
                        : const ValueKey(
                            'computer-use-settings-register-xpc-agent',
                          ),
                    onPressed: _isLoading || !xpcLaunchAgentSupported
                        ? null
                        : xpcLaunchAgentRegistered
                        ? _unregisterXpcLaunchAgent
                        : _registerXpcLaunchAgent,
                    icon: Icon(
                      xpcLaunchAgentRegistered
                          ? Icons.link_off_outlined
                          : Icons.route_outlined,
                    ),
                    label: Text(
                      xpcLaunchAgentRegistered
                          ? 'Unregister XPC Agent'
                          : 'Register XPC Agent',
                    ),
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
            if (_lastLaunchResult != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last open: ${_launchResultSummary(_lastLaunchResult!)}',
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
            if (_lastPermissionOverlayResult != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last permission overlay: ${_permissionOverlaySummary(_lastPermissionOverlayResult!)}',
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
  }) {
    if (!helperInstalled || !helperRunning) {
      return const _ComputerUsePrimaryAction(
        kind: _ComputerUsePrimaryActionKind.launch,
        label: 'Open Computer Use',
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
    return const _ComputerUsePrimaryAction(
      kind: _ComputerUsePrimaryActionKind.launch,
      label: 'Open Computer Use',
      detail:
          'Open the helper when you want to review permissions or helper status.',
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
          _lastLaunchResult = helper;
          _helperStatus = {...?_helperStatus, ...helper};
        } else {
          _lastLaunchResult = {'ok': false, 'error': 'Invalid response'};
        }
      });
      final readiness = _decodeMap(await service.waitForHelperIpcReady());
      if (!mounted) {
        return;
      }
      setState(() {
        if (readiness != null) {
          _lastLaunchResult = {...?_lastLaunchResult, ...readiness};
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
        await service.showPermissionOverlay(
          permission: _permissionOverlayPermission(section),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastPrimaryActionLabel = null;
        _lastPermissionOverlayResult =
            result ??
            {
              'ok': false,
              'section': section,
              'permission': _permissionOverlayPermission(section),
              'error': 'Invalid response',
            };
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
      final nextExistingHelperProbeReport = _liveSmokeReportFrom(
        _decodeMap(await service.getLastExistingHelperProbeReport()),
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
        _lastExistingHelperProbeReport = nextExistingHelperProbeReport;
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
    final helperIpcRuntime = _helperIpcRuntime();
    final diagnostics = MacosComputerUseOnboardingDiagnostics(
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
      helperIpcRuntime: helperIpcRuntime,
      auditLog: MacosComputerUseAuditLog.instance.redactedEntries,
      lastAction: _lastActionLabel(),
      lastResult: {
        'helperStatus': _helperStatus,
        'helperStatusPersistence': _helperStatusPersistence(),
        'permissions': _permissions,
        'helperIpcRuntime': helperIpcRuntime,
        'onboardingVerification': _onboardingVerification(),
        'lastLiveSmokeReport': _lastLiveSmokeReport,
        'lastExistingHelperProbeReport': _lastExistingHelperProbeReport,
        'lastLaunchResult': _lastLaunchResult,
        'lastStopResult': _lastStopResult,
        'lastPermissionSettingsResult': _lastPermissionSettingsResult,
        'lastPermissionOverlayResult': _lastPermissionOverlayResult,
      },
      lastLiveSmokeReport: _lastLiveSmokeReport,
      lastExistingHelperProbeReport: _lastExistingHelperProbeReport,
      lastDiagnosticExportPath: _lastDiagnosticExportPath,
    ).toJson();
    diagnostics['xpcTimingReport'] = buildXpcTimingReportSummary(
      diagnostics,
      sourcePath: 'settings_page_diagnostics',
    ).toJson();
    return diagnostics;
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
        _permissions?['onboardingVerification'] ??
        _helperStatusPersistence()?['onboardingVerification'];
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
    final liveSmokeReport = _liveSmokeReportBody(_lastLiveSmokeReport);
    final existingHelperProbeReport = _liveSmokeReportBody(
      _lastExistingHelperProbeReport,
    );
    final signingDiagnostics = _mapValue(
      liveSmokeReport?['signingDiagnostics'],
    );
    final xpcRuntimeDiagnostics = _mapValue(
      liveSmokeReport?['xpcRuntimeDiagnostics'],
    );
    final permissionGate = _mapValue(liveSmokeReport?['permissionGate']);
    final captureGate =
        _mapValue(liveSmokeReport?['captureGate']) ??
        _verificationCaptureGate(
          verification: _onboardingVerification(),
          snapshot: snapshot,
        );
    final inputGate = _mapValue(liveSmokeReport?['inputGate']);
    final audioGate = _mapValue(liveSmokeReport?['audioGate']);
    final unsafeActionGate = _mapValue(liveSmokeReport?['unsafeActionGate']);
    final positiveSmokeGateSummary = _mapValue(
      liveSmokeReport?['positiveSmokeGateSummary'],
    );
    final readinessExpectations = _mapValue(
      liveSmokeReport?['readinessExpectations'],
    );
    final m4SignoffGate = _mapValue(liveSmokeReport?['m4SignoffGate']);
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
    final preferredAttemptElapsedMs = preferredAttempt?['elapsedMs'];
    final preferredAttemptTimeoutMs = preferredAttempt?['timeoutMs'];
    final preferredAttemptResponseReceivedBeforeTimeout =
        preferredAttempt?['responseReceivedBeforeTimeout'];
    final preferredAttemptResponseReceivedAfterTimeout =
        preferredAttempt?['responseReceivedAfterTimeout'];
    final preferredAttemptLateResponseElapsedMs =
        preferredAttempt?['lateResponseElapsedMs'];
    final preferredWarmupAttempt = _mapValue(
      preferredAttempt?['warmupAttempt'] ??
          snapshot['preferredIpcWarmupAttempt'],
    );
    final helperPathMismatch = snapshot['helperPathMismatch'] == true;
    final helperPathMatchesRunning =
        snapshot['helperPathMatchesRunningHelper'] == true;
    final preservedMismatchedHelperPath =
        snapshot['preservedMismatchedHelperPath'] == true;
    final helperPathMismatchDetails = _mapValue(
      snapshot['helperPathMismatchDetails'],
    );
    final helperPathNextAction = _stringValue(
      helperPathMismatchDetails?['nextAction'],
    );
    final embeddedHelperPath =
        _stringValue(snapshot['embeddedHelperPath']) ??
        _stringValue(snapshot['helperPath']);
    final runningHelperPath = _stringValue(snapshot['runningHelperPath']);
    final helperPathSignoffGate = _helperPathSignoffGate(
      embeddedHelperPath: embeddedHelperPath,
      runningHelperPath: runningHelperPath,
      helperPathMismatch: helperPathMismatch,
      helperPathMatchesRunning: helperPathMatchesRunning,
      preservedMismatchedHelperPath: preservedMismatchedHelperPath,
      helperPathNextAction: helperPathNextAction,
    );
    final reportedProductionReady = snapshot['xpcProductionReady'] == true;
    final helperReachable = snapshot['helperReachable'] != false;
    final reportedProductionBlockers =
        snapshot.containsKey('xpcProductionBlockers')
        ? _stringListValue(snapshot['xpcProductionBlockers'])
        : null;
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
    final effectiveProductionBlockers = helperReachable
        ? reportedProductionBlockers ?? productionBlockers
        : productionBlockers;
    final effectiveProductionReady = reportedProductionBlockers == null
        ? productionBlockers.isEmpty
        : helperReachable &&
              reportedProductionReady &&
              effectiveProductionBlockers.isEmpty;
    final productionNextAction = effectiveProductionReady
        ? 'XPC is production ready.'
        : 'Resolve XPC production blockers before marking production ready.';
    final productionGate = <String, dynamic>{
      'productionReady': effectiveProductionReady,
      'namedServiceConnected': namedServiceConnected,
      'launchAgentPlistInstalled': launchAgentPlistInstalled,
      'launchAgentRegistered': launchAgentRegistered,
      'commandParityComplete': nextParityCommands.isEmpty,
      'nextParityCommands': nextParityCommands,
      'blockers': effectiveProductionBlockers,
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
      'xpcProductionReady': effectiveProductionReady,
      'xpcProductionReadyMeasured': effectiveProductionReady,
      'xpcNamedServiceConnected': namedServiceConnected,
      'xpcNamedServiceConnectedMeasured': namedServiceConnected,
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
      'xpcProductionBlockers': effectiveProductionBlockers,
      'xpcProductionNextAction': productionNextAction,
      'helperSharedDiagnosticsStale': snapshot['helperSharedDiagnosticsStale'],
      'helperSharedDiagnosticsStaleReasons':
          snapshot['helperSharedDiagnosticsStaleReasons'],
      'helperSharedDiagnosticsAgeMs': snapshot['helperSharedDiagnosticsAgeMs'],
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
      'signingDiagnostics': signingDiagnostics,
      'xpcRuntimeDiagnostics': xpcRuntimeDiagnostics,
      'permissionGate': permissionGate,
      'captureGate': captureGate,
      'inputGate': inputGate,
      'audioGate': audioGate,
      'overlaySmoke': _mapValue(liveSmokeReport?['overlaySmoke']),
      'unsafeActionGate': unsafeActionGate,
      'positiveSmokeGateSummary': positiveSmokeGateSummary,
      'readinessExpectations': readinessExpectations,
      'm4SignoffGate': m4SignoffGate,
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
      'helperPathSignoffGate': helperPathSignoffGate,
      'helperRuntimeUseGate': _helperRuntimeUseGate(
        helperPathMismatch: helperPathMismatch,
        preservedMismatchedHelperPath: preservedMismatchedHelperPath,
        runningHelperPath: runningHelperPath,
        helperReachable: helperReachable,
      ),
    };
    runtime['preferredFallbackSucceeded'] =
        runtime['preferredFallbackActive'] == true &&
        (snapshot['ok'] == true || snapshot['helperReachable'] == true) &&
        snapshot['code'] == null;
    for (final key in const [
      'embeddedHelperPath',
      'helperLaunchPath',
      'helperPath',
      'runningHelperPath',
      'helperPathMatchesRunningHelper',
      'helperPathMismatch',
      'helperPathMismatchDetails',
      'preservedMismatchedHelperPath',
      'mismatchedHelperPath',
      'mismatchedHelperPaths',
      'alreadyRunningPathMismatch',
    ]) {
      if (snapshot.containsKey(key)) {
        runtime[key] = snapshot[key];
      }
    }
    if (existingHelperProbeReport != null) {
      final helper = _mapValue(existingHelperProbeReport['helper']);
      runtime['existingHelperProbe'] = existingHelperProbeReport;
      runtime['existingHelperProbeOk'] = existingHelperProbeReport['ok'];
      runtime['existingHelperProbePath'] =
          _lastExistingHelperProbeReport?['path'];
      runtime['existingHelperProbeCaptureReady'] =
          existingHelperProbeReport['captureReady'];
      runtime['existingHelperProbeInputReady'] =
          existingHelperProbeReport['inputReady'];
      runtime['existingHelperProbeHelperPathMatchesExpected'] =
          existingHelperProbeReport['helperPathMatchesExpected'] ??
          helper?['pathMatchesExpected'];
      runtime['existingHelperProbeExpectedHelperPath'] =
          helper?['expectedPath'];
      runtime['existingHelperProbeRunningHelperPath'] = helper?['runningPath'];
      runtime['existingHelperProbeFailedRequiredChecks'] = _stringListValue(
        existingHelperProbeReport['failedRequiredChecks'],
      );
    }
    if (preferredAttemptStatus != null) {
      runtime['preferredAttemptStatus'] = preferredAttemptStatus;
    }
    if (preferredAttemptErrorCode != null) {
      runtime['preferredAttemptErrorCode'] = preferredAttemptErrorCode;
    }
    if (preferredAttemptElapsedMs is int) {
      runtime['preferredAttemptElapsedMs'] = preferredAttemptElapsedMs;
    }
    if (preferredAttemptTimeoutMs is int) {
      runtime['preferredAttemptTimeoutMs'] = preferredAttemptTimeoutMs;
    }
    if (preferredAttemptResponseReceivedBeforeTimeout is bool) {
      runtime['preferredAttemptResponseReceivedBeforeTimeout'] =
          preferredAttemptResponseReceivedBeforeTimeout;
    }
    if (preferredAttemptResponseReceivedAfterTimeout is bool) {
      runtime['preferredAttemptResponseReceivedAfterTimeout'] =
          preferredAttemptResponseReceivedAfterTimeout;
    }
    if (preferredAttemptLateResponseElapsedMs is int) {
      runtime['preferredAttemptLateResponseElapsedMs'] =
          preferredAttemptLateResponseElapsedMs;
    }
    if (preferredWarmupAttempt != null) {
      runtime['preferredIpcWarmupAttempt'] = preferredWarmupAttempt;
    }
    if (runtime['preferredFallbackActive'] == true &&
        preferredAttemptStatus != null) {
      runtime['preferredFallbackReason'] = preferredAttemptErrorCode == null
          ? preferredAttemptStatus
          : '$preferredAttemptStatus ($preferredAttemptErrorCode)';
      runtime['preferredFallbackSummary'] =
          runtime['preferredFallbackSucceeded'] == true
          ? '$preferredAttemptStatus, fallback succeeded'
          : preferredAttemptErrorCode == null
          ? preferredAttemptStatus
          : '$preferredAttemptStatus ($preferredAttemptErrorCode)';
    }
    return runtime;
  }

  Map<String, dynamic> _xpcTimingSummary(
    Map<String, dynamic> helperIpcRuntime,
  ) {
    return buildXpcTimingReportSummary({
      'helperStatus': _helperStatus,
      'helperIpcRuntime': helperIpcRuntime,
    }, sourcePath: 'settings_page_runtime').toJson();
  }

  Map<String, dynamic>? _liveSmokeReportBody(Map<String, dynamic>? envelope) {
    if (envelope == null) {
      return null;
    }
    final report = envelope['report'];
    if (report is Map) {
      return Map<String, dynamic>.from(report);
    }
    return envelope;
  }

  Map<String, dynamic> _helperPathSignoffGate({
    required String? embeddedHelperPath,
    required String? runningHelperPath,
    required bool helperPathMismatch,
    required bool helperPathMatchesRunning,
    required bool preservedMismatchedHelperPath,
    required String? helperPathNextAction,
  }) {
    final blockers = <String>[
      if (helperPathMismatch) 'helper_path_mismatch',
      if (preservedMismatchedHelperPath) 'preserved_mismatched_helper',
      if (!helperPathMismatch &&
          !helperPathMatchesRunning &&
          runningHelperPath != null)
        'helper_path_match_unknown',
    ];
    final ready = blockers.isEmpty;
    return {
      'status': ready ? 'ready' : 'blocked',
      'ready': ready,
      'embeddedHelperPath': embeddedHelperPath,
      'runningHelperPath': runningHelperPath,
      'helperPathMismatch': helperPathMismatch,
      'helperPathMatchesRunningHelper': helperPathMatchesRunning,
      'preservedMismatchedHelperPath': preservedMismatchedHelperPath,
      'blockers': blockers,
      'nextAction': ready
          ? 'Helper path is ready for release runtime sign-off.'
          : helperPathNextAction ??
                'Restart Caverno Computer Use from Caverno before release runtime sign-off.',
    };
  }

  Map<String, dynamic> _helperRuntimeUseGate({
    required bool helperPathMismatch,
    required bool preservedMismatchedHelperPath,
    required String? runningHelperPath,
    required bool helperReachable,
  }) {
    final usable =
        helperReachable &&
        (!helperPathMismatch ||
            (preservedMismatchedHelperPath && runningHelperPath != null));
    return {
      'status': usable
          ? preservedMismatchedHelperPath
                ? 'current_session'
                : 'ready'
          : 'blocked',
      'usable': usable,
      'releaseSignoffSafe': !helperPathMismatch,
      'requiresRestartForReleaseSignoff': helperPathMismatch,
      'nextAction': usable
          ? preservedMismatchedHelperPath
                ? 'Use the current helper for this session, then restart from Caverno before release sign-off.'
                : 'Current helper is ready for runtime use.'
          : 'Open Computer Use from Caverno, then recheck helper reachability.',
    };
  }

  Map<String, dynamic>? _verificationCaptureGate({
    required Map<String, dynamic>? verification,
    required Map<String, dynamic> snapshot,
  }) {
    if (verification == null) {
      return null;
    }
    final displayPassed = _verificationStepOk(
      verification,
      'display_screenshot',
    );
    final windowPassed = _verificationStepOk(verification, 'window_capture');
    final permissions = _mapValue(verification['permissions']);
    final screenCaptureGranted =
        permissions?['screenCaptureGranted'] == true ||
        snapshot['screenCaptureGranted'] == true;
    final blockers = <String>[
      if (!screenCaptureGranted) 'screen_capture_permission_missing',
      if (screenCaptureGranted && !displayPassed)
        'display_capture_runtime_failed',
      if (screenCaptureGranted && !windowPassed)
        'window_capture_runtime_failed',
    ];
    final status = !screenCaptureGranted
        ? 'blocked'
        : blockers.isEmpty
        ? 'ready'
        : 'failed';
    final helperPath =
        _stringValue(snapshot['runningHelperPath']) ??
        _stringValue(snapshot['embeddedHelperPath']) ??
        _stringValue(snapshot['helperPath']);
    return {
      'status': status,
      'source': 'helper_verification',
      'screenCaptureGranted': screenCaptureGranted,
      'displayScreenshotPassed': displayPassed,
      'windowCapturePassed': windowPassed,
      'failureClass': blockers.isEmpty ? 'none' : blockers.first,
      'failureClasses': blockers,
      'blockers': blockers,
      'tccOwnerHelperPath': helperPath,
      'nextAction': blockers.isEmpty
          ? 'Display and window capture passed in helper verification.'
          : !screenCaptureGranted
          ? 'Ask the user to grant Screen & System Audio Recording to Caverno Computer Use, then rerun the smoke sequence manually.'
          : 'Open Smoke Sequence, then press Run Smoke Sequence to rerun display and window capture checks.',
    };
  }

  bool _verificationStepOk(Map<String, dynamic> verification, String id) {
    final direct = _mapValue(verification[id]);
    if (direct != null) {
      return direct['ok'] == true;
    }
    final camelCaseId = switch (id) {
      'display_screenshot' => 'displayScreenshot',
      'window_capture' => 'windowCapture',
      _ => id,
    };
    final camelCase = _mapValue(verification[camelCaseId]);
    if (camelCase != null) {
      return camelCase['ok'] == true;
    }
    final steps = verification['steps'];
    if (steps is! List) {
      return false;
    }
    for (final step in steps) {
      if (step is Map && step['id'] == id) {
        return step['ok'] == true;
      }
    }
    return false;
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

  String _launchResultSummary(Map<String, dynamic> result) {
    final ok = result['ok'] == true;
    final launched = result['launched'];
    final helperReachable = result['helperReachable'];
    final ipcReady = result['ipcReady'];
    final code = result['code'];
    final error = result['error'];
    if (ok) {
      return 'ok, launched: $launched, reachable: $helperReachable, ipc ready: $ipcReady';
    }
    if (code != null || error != null) {
      return '${code ?? 'failed'}: ${error ?? 'Unknown error'}';
    }
    return 'failed';
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

  String _permissionOverlaySummary(Map<String, dynamic> result) {
    final permission = result['permission'] ?? result['section'] ?? 'unknown';
    final shown = result['overlayShown'] == true;
    final opened = result['settingsOpened'] == true || result['ok'] == true;
    final ready = result['draggableTileReady'] == true;
    final error = result['error'];
    if (shown) {
      return ready
          ? 'shown for $permission'
          : 'shown without tile for $permission';
    }
    if (opened) {
      return ready
          ? 'opened $permission with tile ready'
          : 'opened $permission';
    }
    return 'failed to show $permission${error == null ? '' : ': $error'}';
  }

  String _permissionOverlayPermission(String section) {
    return switch (section) {
      'screen_capture' ||
      'screencapture' ||
      'screen_recording' ||
      'screenrecording' => 'screenRecording',
      _ => 'accessibility',
    };
  }

  String _lastActionLabel() {
    if (_lastPrimaryActionLabel != null) {
      return 'Settings primary action: $_lastPrimaryActionLabel';
    }
    if (_lastLaunchResult != null) {
      return 'Settings open computer use';
    }
    if (_lastStopResult != null) {
      return 'Settings stop helper work';
    }
    if (_lastPermissionSettingsResult != null) {
      return 'Settings open permission pane';
    }
    if (_lastPermissionOverlayResult != null) {
      return 'Settings show permission overlay';
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

class _ComputerUseGatePlan extends StatelessWidget {
  const _ComputerUseGatePlan({
    required this.helperInstalled,
    required this.helperRunning,
    required this.helperIpcReady,
    required this.accessibilityGranted,
    required this.screenCaptureGranted,
    required this.captureGate,
    required this.inputGate,
    required this.audioGate,
    required this.overlaySmoke,
    required this.unsafeActionGate,
    required this.hasLiveSmokeReport,
  });

  final bool helperInstalled;
  final bool helperRunning;
  final bool helperIpcReady;
  final bool accessibilityGranted;
  final bool screenCaptureGranted;
  final Map<String, dynamic>? captureGate;
  final Map<String, dynamic>? inputGate;
  final Map<String, dynamic>? audioGate;
  final Map<String, dynamic>? overlaySmoke;
  final Map<String, dynamic>? unsafeActionGate;
  final bool hasLiveSmokeReport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final captureStatus = _status(captureGate);
    final inputStatus = _status(inputGate);
    final audioStatus = _status(audioGate);
    final overlayStatus = _status(overlaySmoke);
    final unsafeStatus = _status(unsafeActionGate);
    final helperReady = helperInstalled && helperRunning && helperIpcReady;
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
            Text('Computer Use action plan', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            _GatePlanRow(
              label: 'Helper boundary',
              status: helperReady
                  ? 'ready'
                  : !helperInstalled || !helperRunning
                  ? 'needs launch'
                  : 'needs IPC',
              ok: helperReady,
              detail:
                  'Caverno.app stays the chat client; Caverno Computer Use owns macOS permissions and OS actions.',
            ),
            _GatePlanRow(
              label: 'Accessibility permission',
              status: accessibilityGranted ? 'granted' : 'blocked',
              ok: accessibilityGranted,
              detail: accessibilityGranted
                  ? 'Input inspection and UI control can be verified.'
                  : 'Grant Accessibility to Caverno Computer Use.',
            ),
            _GatePlanRow(
              label: 'Screen recording permission',
              status: screenCaptureGranted ? 'granted' : 'blocked',
              ok: screenCaptureGranted,
              detail: screenCaptureGranted
                  ? 'Display and window capture can be verified.'
                  : 'Grant Screen & System Audio Recording to Caverno Computer Use.',
            ),
            _GatePlanRow(
              label: 'Capture smoke',
              status: captureStatus,
              ok: captureStatus == 'ready',
              detail: captureGate != null
                  ? _nextAction(captureGate)
                  : 'Run live smoke after permissions are granted.',
            ),
            _GatePlanRow(
              label: 'Input smoke',
              status: inputStatus,
              ok: inputStatus == 'ready',
              detail: hasLiveSmokeReport
                  ? _nextAction(inputGate)
                  : 'Arm non-destructive input smoke only when ready to test.',
            ),
            _GatePlanRow(
              label: 'System audio smoke',
              status: audioStatus,
              ok: audioStatus == 'ready' || audioStatus == 'unsupported',
              detail: hasLiveSmokeReport
                  ? _nextAction(audioGate)
                  : 'System audio is optional and uses Screen & System Audio Recording.',
            ),
            _GatePlanRow(
              label: 'Overlay smoke',
              status: overlayStatus,
              ok: overlayStatus == 'ready',
              detail: hasLiveSmokeReport
                  ? _nextAction(overlaySmoke)
                  : 'Run overlay smoke before marking M1 onboarding ready.',
            ),
            _GatePlanRow(
              label: 'Unsafe arms',
              status: unsafeStatus,
              ok: unsafeStatus == 'armed',
              detail: hasLiveSmokeReport
                  ? _nextAction(unsafeActionGate)
                  : 'Click and text input remain separately armed.',
            ),
          ],
        ),
      ),
    );
  }

  String _status(Map<String, dynamic>? gate) {
    final status = gate?['status'];
    return status is String ? status : 'not run';
  }

  String _nextAction(Map<String, dynamic>? gate) {
    final nextAction = gate?['nextAction'];
    if (nextAction is String && nextAction.isNotEmpty) {
      return nextAction;
    }
    return 'Review the latest live smoke report.';
  }
}

class _GatePlanRow extends StatelessWidget {
  const _GatePlanRow({
    required this.label,
    required this.status,
    required this.ok,
    required this.detail,
  });

  final String label;
  final String status;
  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = ok ? colorScheme.primary : colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label: $status', style: textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(detail, style: textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
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
    final fallbackSummary = runtime['preferredFallbackSummary'];
    final fallbackSucceeded = runtime['preferredFallbackSucceeded'] == true;
    final preferredAttemptElapsedMs = runtime['preferredAttemptElapsedMs'];
    final responseReceivedBeforeTimeout =
        runtime['preferredAttemptResponseReceivedBeforeTimeout'];
    final responseReceivedAfterTimeout =
        runtime['preferredAttemptResponseReceivedAfterTimeout'];
    final lateResponseElapsedMs =
        runtime['preferredAttemptLateResponseElapsedMs'];
    final supportedCommands = _stringList(runtime['xpcSupportedCommands']);
    final nextParityCommands = _stringList(runtime['xpcNextParityCommands']);
    final productionBlockers = _stringList(runtime['xpcProductionBlockers']);
    final signingDiagnostics = _mapValue(runtime['signingDiagnostics']);
    final xpcRuntimeDiagnostics = _mapValue(runtime['xpcRuntimeDiagnostics']);
    final permissionGate = _mapValue(runtime['permissionGate']);
    final captureGate = _mapValue(runtime['captureGate']);
    final inputGate = _mapValue(runtime['inputGate']);
    final audioGate = _mapValue(runtime['audioGate']);
    final overlaySmoke = _mapValue(runtime['overlaySmoke']);
    final accessibilityOverlay = _mapValue(overlaySmoke?['accessibility']);
    final screenRecordingOverlay = _mapValue(overlaySmoke?['screenRecording']);
    final unsafeActionGate = _mapValue(runtime['unsafeActionGate']);
    final positiveSmokeGateSummary = _mapValue(
      runtime['positiveSmokeGateSummary'],
    );
    final readinessExpectations = _mapValue(runtime['readinessExpectations']);
    final m4SignoffGate = _mapValue(runtime['m4SignoffGate']);
    final signingBlockers = _stringList(
      signingDiagnostics?['launchConstraintBlockers'],
    );
    final xpcRuntimeBlockers = _stringList(xpcRuntimeDiagnostics?['blockers']);
    final helperDiagnosticsStale =
        runtime['helperSharedDiagnosticsStale'] == true ||
        xpcRuntimeDiagnostics?['helperDiagnosticsLatestStale'] == true;
    final helperDiagnosticsStaleReasons = _uniqueStrings([
      ..._stringList(runtime['helperSharedDiagnosticsStaleReasons']),
      ..._stringList(xpcRuntimeDiagnostics?['helperDiagnosticsStaleReasons']),
    ]);
    final permissionBlockers = _stringList(
      permissionGate?['blockedByPermissions'],
    );
    final captureBlockers = _stringList(captureGate?['blockers']);
    final captureFailureClasses = _stringList(captureGate?['failureClasses']);
    final captureFailureClass = _stringValue(captureGate?['failureClass']);
    final captureStepDiagnostics = _mapValue(captureGate?['stepDiagnostics']);
    final captureDisplayStatus = _stringValue(
      _mapValue(captureStepDiagnostics?['displayScreenshot'])?['status'],
    );
    final captureWindowListStatus = _stringValue(
      _mapValue(captureStepDiagnostics?['listWindows'])?['status'],
    );
    final captureWindowStatus = _stringValue(
      _mapValue(captureStepDiagnostics?['windowCapture'])?['status'],
    );
    final captureTccOwnerPath = _stringValue(
      captureGate?['tccOwnerHelperPath'],
    );
    final inputBlockers = _stringList(inputGate?['blockers']);
    final audioBlockers = _stringList(audioGate?['blockers']);
    final overlayBlockers = _stringList(overlaySmoke?['blockers']);
    final overlayPlacements = _uniqueStrings([
      _stringValue(accessibilityOverlay?['overlayPlacement']),
      _stringValue(screenRecordingOverlay?['overlayPlacement']),
    ]);
    final overlayModes = _uniqueStrings([
      _stringValue(accessibilityOverlay?['overlayMode']),
      _stringValue(screenRecordingOverlay?['overlayMode']),
    ]);
    final overlayPasteboardTypes = _uniqueStrings([
      ..._stringList(accessibilityOverlay?['dragPasteboardTypes']),
      ..._stringList(screenRecordingOverlay?['dragPasteboardTypes']),
    ]);
    final overlayHelperPaths = _uniqueStrings([
      _stringValue(accessibilityOverlay?['helperBundlePath']),
      _stringValue(screenRecordingOverlay?['helperBundlePath']),
    ]).map(_shortPath).toList(growable: false);
    final unsafeBlockers = _stringList(unsafeActionGate?['blockers']);
    final positiveSmokeBlockers = _stringList(
      positiveSmokeGateSummary?['blockedBy'],
    );
    final failedExpectations = _stringList(readinessExpectations?['failed']);
    final m4SignoffBlockers = _stringList(m4SignoffGate?['blockers']);
    final m4SignoffHelperPath = _stringValue(
      _mapValue(m4SignoffGate?['helperPath'])?['embeddedHelperPath'],
    );
    final m4SignoffNextAction = _stringValue(m4SignoffGate?['nextAction']);
    final launchAgentStatus = runtime['xpcLaunchAgentStatus'];
    final launchAgentPlistInstalled = runtime['xpcLaunchAgentPlistInstalled'];
    final productionReady = runtime['xpcProductionReadyMeasured'] == true;
    final namedServiceConnected = runtime['xpcNamedServiceConnected'] == true;
    final helperPathMismatch = runtime['helperPathMismatch'] == true;
    final helperPathMatchesRunning =
        runtime['helperPathMatchesRunningHelper'] == true;
    final preservedMismatchedHelperPath =
        runtime['preservedMismatchedHelperPath'] == true;
    final helperPathSignoffGate = _mapValue(runtime['helperPathSignoffGate']);
    final helperRuntimeUseGate = _mapValue(runtime['helperRuntimeUseGate']);
    final helperPathSignoffBlockers = _stringList(
      helperPathSignoffGate?['blockers'],
    );
    final helperPathSignoffNextAction = _stringValue(
      helperPathSignoffGate?['nextAction'],
    );
    final helperRuntimeUseNextAction = _stringValue(
      helperRuntimeUseGate?['nextAction'],
    );
    final helperPathMismatchDetails = _mapValue(
      runtime['helperPathMismatchDetails'],
    );
    final helperPathNextAction = _stringValue(
      helperPathMismatchDetails?['nextAction'],
    );
    final embeddedHelperPath = _stringValue(runtime['embeddedHelperPath']);
    final runningHelperPath = _stringValue(runtime['runningHelperPath']);
    final tccOwnerHelperPath = preservedMismatchedHelperPath
        ? runningHelperPath
        : embeddedHelperPath;
    final existingProbeOk = runtime['existingHelperProbeOk'];
    final existingProbePathMatch =
        runtime['existingHelperProbeHelperPathMatchesExpected'];
    final existingProbeFailedChecks = _stringList(
      runtime['existingHelperProbeFailedRequiredChecks'],
    );
    final existingProbeExpectedPath = _stringValue(
      runtime['existingHelperProbeExpectedHelperPath'],
    );
    final existingProbeRunningPath = _stringValue(
      runtime['existingHelperProbeRunningHelperPath'],
    );
    final xpcListenerStarted =
        xpcRuntimeDiagnostics?['xpcListenerStarted'] == true;
    final xpcListenerStartAttempted =
        xpcRuntimeDiagnostics?['xpcListenerStartAttempted'] == true;
    final signingLooksAccepted =
        signingDiagnostics?['launchConstraintLikelyAccepted'] == true;

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
            if (signingDiagnostics != null)
              _InfoChip(
                label: 'Signing gate',
                value: signingLooksAccepted ? 'accepted' : 'blockers',
              ),
            if (signingBlockers.isNotEmpty)
              _InfoChip(
                label: 'Signing blockers',
                value: signingBlockers.join(', '),
              ),
            if (xpcRuntimeDiagnostics != null)
              _InfoChip(
                label: 'XPC runtime',
                value: xpcRuntimeBlockers.isEmpty ? 'ready' : 'blockers',
              ),
            if (xpcRuntimeDiagnostics != null)
              _InfoChip(
                label: 'XPC listener',
                value: xpcListenerStarted
                    ? 'started'
                    : xpcListenerStartAttempted
                    ? 'attempted'
                    : 'not started',
              ),
            if (xpcRuntimeBlockers.isNotEmpty)
              _InfoChip(
                label: 'Runtime blockers',
                value: xpcRuntimeBlockers.join(', '),
              ),
            if (helperDiagnosticsStale)
              _InfoChip(
                label: 'Helper diagnostics',
                value: helperDiagnosticsStaleReasons.isEmpty
                    ? 'stale'
                    : 'stale: ${helperDiagnosticsStaleReasons.join(', ')}',
              ),
            if (runtime.containsKey('helperPathMatchesRunningHelper'))
              _InfoChip(
                label: 'Helper path',
                value: helperPathMismatch
                    ? 'mismatch'
                    : helperPathMatchesRunning
                    ? 'matched'
                    : 'unknown',
              ),
            if (helperPathMismatch)
              _InfoChip(
                label: 'Helper identity',
                value: preservedMismatchedHelperPath
                    ? 'preserved running helper'
                    : 'path mismatch',
              ),
            if (helperPathMismatch && tccOwnerHelperPath != null)
              _InfoChip(
                label: 'TCC owner helper',
                value: _shortPath(tccOwnerHelperPath),
              ),
            if (preservedMismatchedHelperPath)
              const _InfoChip(
                label: 'Release sign-off',
                value: 'requires helper path match',
              ),
            if (helperPathSignoffGate != null)
              _InfoChip(
                label: 'Helper path sign-off',
                value: '${helperPathSignoffGate['status']}',
              ),
            if (helperRuntimeUseGate != null)
              _InfoChip(
                label: 'Helper runtime use',
                value: '${helperRuntimeUseGate['status']}',
              ),
            if (helperPathSignoffBlockers.isNotEmpty)
              _InfoChip(
                label: 'Helper path blockers',
                value: helperPathSignoffBlockers.join(', '),
              ),
            if (helperPathSignoffNextAction != null)
              _InfoChip(
                label: 'Helper path sign-off next action',
                value: helperPathSignoffNextAction,
              ),
            if (helperPathNextAction != null)
              _InfoChip(
                label: 'Helper path next action',
                value: helperPathNextAction,
              ),
            if (helperRuntimeUseNextAction != null)
              _InfoChip(
                label: 'Helper runtime next action',
                value: helperRuntimeUseNextAction,
              ),
            if (embeddedHelperPath != null)
              _InfoChip(
                label: 'Embedded helper',
                value: _shortPath(embeddedHelperPath),
              ),
            if (runningHelperPath != null)
              _InfoChip(
                label: 'Running helper',
                value: _shortPath(runningHelperPath),
              ),
            if (existingProbeOk is bool)
              _InfoChip(
                label: 'Existing probe',
                value: existingProbeOk ? 'passed' : 'failed',
              ),
            if (existingProbePathMatch is bool)
              _InfoChip(
                label: 'Probe helper path',
                value: existingProbePathMatch ? 'matched' : 'mismatch',
              ),
            if (existingProbeExpectedPath != null)
              _InfoChip(
                label: 'Probe expected helper',
                value: _shortPath(existingProbeExpectedPath),
              ),
            if (existingProbeRunningPath != null)
              _InfoChip(
                label: 'Probe running helper',
                value: _shortPath(existingProbeRunningPath),
              ),
            if (existingProbeFailedChecks.isNotEmpty)
              _InfoChip(
                label: 'Probe failed checks',
                value: existingProbeFailedChecks.join(', '),
              ),
            if (permissionGate != null)
              _InfoChip(
                label: 'Permission gate',
                value: permissionBlockers.isEmpty ? 'clear' : 'blocked',
              ),
            if (permissionBlockers.isNotEmpty)
              _InfoChip(
                label: 'Permission blockers',
                value: permissionBlockers.join(', '),
              ),
            if (captureGate != null)
              _InfoChip(
                label: 'Capture gate',
                value: '${captureGate['status']}',
              ),
            if (captureBlockers.isNotEmpty)
              _InfoChip(
                label: 'Capture blockers',
                value: captureBlockers.join(', '),
              ),
            if (captureFailureClass != null && captureFailureClass != 'none')
              _InfoChip(
                label: 'Capture failure',
                value: captureFailureClasses.isEmpty
                    ? captureFailureClass
                    : captureFailureClasses.join(', '),
              ),
            if (captureStepDiagnostics != null)
              _InfoChip(
                label: 'Capture steps',
                value: [
                  if (captureDisplayStatus != null)
                    'display=$captureDisplayStatus',
                  if (captureWindowListStatus != null)
                    'windows=$captureWindowListStatus',
                  if (captureWindowStatus != null)
                    'window=$captureWindowStatus',
                ].join(', '),
              ),
            if (captureTccOwnerPath != null)
              _InfoChip(
                label: 'Capture TCC owner',
                value: _shortPath(captureTccOwnerPath),
              ),
            if (inputGate != null)
              _InfoChip(label: 'Input gate', value: '${inputGate['status']}'),
            if (inputBlockers.isNotEmpty)
              _InfoChip(
                label: 'Input blockers',
                value: inputBlockers.join(', '),
              ),
            if (audioGate != null)
              _InfoChip(label: 'Audio gate', value: '${audioGate['status']}'),
            if (audioBlockers.isNotEmpty)
              _InfoChip(
                label: 'Audio blockers',
                value: audioBlockers.join(', '),
              ),
            if (overlaySmoke != null)
              _InfoChip(
                label: 'Overlay smoke',
                value: '${overlaySmoke['status']}',
              ),
            if (overlayPlacements.isNotEmpty)
              _InfoChip(
                label: 'Overlay placement',
                value: overlayPlacements.join(', '),
              ),
            if (overlayModes.isNotEmpty)
              _InfoChip(label: 'Overlay mode', value: overlayModes.join(', ')),
            if (overlayPasteboardTypes.isNotEmpty)
              _InfoChip(
                label: 'Overlay pasteboard',
                value: overlayPasteboardTypes.join(', '),
              ),
            if (overlayHelperPaths.isNotEmpty)
              _InfoChip(
                label: 'Overlay helper',
                value: overlayHelperPaths.join(', '),
              ),
            if (overlayBlockers.isNotEmpty)
              _InfoChip(
                label: 'Overlay blockers',
                value: overlayBlockers.join(', '),
              ),
            if (unsafeActionGate != null)
              _InfoChip(
                label: 'Unsafe action gate',
                value: '${unsafeActionGate['status']}',
              ),
            if (unsafeBlockers.isNotEmpty)
              _InfoChip(
                label: 'Unsafe blockers',
                value: unsafeBlockers.join(', '),
              ),
            if (positiveSmokeGateSummary != null)
              _InfoChip(
                label: 'Positive smoke gate',
                value: '${positiveSmokeGateSummary['status']}',
              ),
            if (positiveSmokeBlockers.isNotEmpty)
              _InfoChip(
                label: 'Positive smoke blockers',
                value: positiveSmokeBlockers.join(', '),
              ),
            if (readinessExpectations != null)
              _InfoChip(
                label: 'Readiness expectations',
                value: readinessExpectations['ok'] == true
                    ? 'passed'
                    : 'failed',
              ),
            if (m4SignoffGate != null)
              _InfoChip(
                label: 'M4 sign-off',
                value: '${m4SignoffGate['status']}',
              ),
            if (m4SignoffBlockers.isNotEmpty)
              _InfoChip(
                label: 'M4 blockers',
                value: m4SignoffBlockers.join(', '),
              ),
            if (m4SignoffHelperPath != null)
              _InfoChip(
                label: 'M4 helper',
                value: _shortPath(m4SignoffHelperPath),
              ),
            if (m4SignoffNextAction != null)
              _InfoChip(label: 'M4 next action', value: m4SignoffNextAction),
            if (failedExpectations.isNotEmpty)
              _InfoChip(
                label: 'Failed expectations',
                value: failedExpectations.join(', '),
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
                value: fallbackSummary is String
                    ? fallbackSummary
                    : preferredAttemptStatus,
              ),
            if (preferredAttemptErrorCode is String)
              _InfoChip(
                label: 'Preferred error',
                value: preferredAttemptErrorCode,
              ),
            if (preferredAttemptElapsedMs is int)
              _InfoChip(
                label: 'Preferred elapsed',
                value: '${preferredAttemptElapsedMs}ms',
              ),
            if (responseReceivedBeforeTimeout is bool)
              _InfoChip(
                label: 'XPC response before timeout',
                value: responseReceivedBeforeTimeout ? 'yes' : 'no',
              ),
            if (responseReceivedAfterTimeout is bool)
              _InfoChip(
                label: 'XPC late response',
                value: responseReceivedAfterTimeout ? 'yes' : 'no',
              ),
            if (lateResponseElapsedMs is int)
              _InfoChip(
                label: 'XPC late elapsed',
                value: '${lateResponseElapsedMs}ms',
              ),
            if (fallbackReason is String)
              _InfoChip(label: 'Fallback reason', value: fallbackReason),
            if (fallbackActive)
              _InfoChip(
                label: 'Fallback outcome',
                value: fallbackSucceeded ? 'succeeded' : 'needs attention',
              ),
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

  String? _stringValue(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  List<String> _uniqueStrings(Iterable<String?> values) {
    final result = <String>[];
    for (final value in values) {
      if (value == null || value.isEmpty || result.contains(value)) {
        continue;
      }
      result.add(value);
    }
    return result;
  }

  String _shortPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 4) {
      return path;
    }
    return '.../${parts.sublist(parts.length - 4).join('/')}';
  }

  Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
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

class _XpcTimingSummary extends StatelessWidget {
  const _XpcTimingSummary({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final ready = summary['ready'] == true;
    final classification = _summaryString('classification') ?? 'unknown';
    final status = _summaryString('status') ?? 'unknown';
    final nextAction = _summaryString('nextAction');
    final recommendedActionId = _summaryString('recommendedActionId');
    final userNextAction = _summaryString('userNextAction');
    final engineeringNextAction = _summaryString('engineeringNextAction');
    final elapsedMs = summary['elapsedMs'];
    final timeoutMs = summary['timeoutMs'];
    final currentPreferredFallbackTimeoutMs =
        summary['currentPreferredFallbackTimeoutMs'];
    final currentTimeoutHeadroomMs = summary['currentTimeoutHeadroomMs'];
    final lateElapsedMs = summary['lateResponseElapsedMs'];
    final warmupElapsedMs = summary['warmupElapsedMs'];
    final responseBeforeTimeout = summary['responseReceivedBeforeTimeout'];
    final responseAfterTimeout = summary['responseReceivedAfterTimeout'];
    final warmupResponseBeforeTimeout =
        summary['warmupResponseReceivedBeforeTimeout'];
    final fallbackSucceeded = summary['preferredFallbackSucceeded'];
    final warmupStatus = _summaryString('warmupStatus');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'XPC timing: $classification',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(label: 'Timing status', value: status),
            _InfoChip(label: 'Timing gate', value: ready ? 'ready' : 'review'),
            if (elapsedMs is int)
              _InfoChip(label: 'Elapsed', value: '${elapsedMs}ms'),
            if (timeoutMs is int)
              _InfoChip(label: 'Timeout budget', value: '${timeoutMs}ms'),
            if (currentPreferredFallbackTimeoutMs is int)
              _InfoChip(
                label: 'Current XPC timeout',
                value: '${currentPreferredFallbackTimeoutMs}ms',
              ),
            if (currentTimeoutHeadroomMs is int)
              _InfoChip(
                label: 'Current headroom',
                value: '${currentTimeoutHeadroomMs}ms',
              ),
            if (responseBeforeTimeout is bool)
              _InfoChip(
                label: 'Before timeout',
                value: responseBeforeTimeout ? 'yes' : 'no',
              ),
            if (responseAfterTimeout is bool)
              _InfoChip(
                label: 'Late response',
                value: responseAfterTimeout ? 'yes' : 'no',
              ),
            if (lateElapsedMs is int)
              _InfoChip(label: 'Late elapsed', value: '${lateElapsedMs}ms'),
            if (warmupStatus != null)
              _InfoChip(label: 'Warmup status', value: warmupStatus),
            if (warmupElapsedMs is int)
              _InfoChip(label: 'Warmup elapsed', value: '${warmupElapsedMs}ms'),
            if (warmupResponseBeforeTimeout is bool)
              _InfoChip(
                label: 'Warmup before timeout',
                value: warmupResponseBeforeTimeout ? 'yes' : 'no',
              ),
            if (fallbackSucceeded is bool)
              _InfoChip(
                label: 'Fallback',
                value: fallbackSucceeded ? 'succeeded' : 'not used',
              ),
            if (recommendedActionId != null)
              _InfoChip(label: 'Timing action', value: recommendedActionId),
            if (userNextAction != null)
              _InfoChip(label: 'User next action', value: userNextAction),
            if (engineeringNextAction != null)
              _InfoChip(
                label: 'Engineering next action',
                value: engineeringNextAction,
              ),
            if (nextAction != null)
              _InfoChip(label: 'Timing next action', value: nextAction),
          ],
        ),
      ],
    );
  }

  String? _summaryString(String key) {
    final value = summary[key];
    return value is String && value.isNotEmpty ? value : null;
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
    final signingDiagnostics = _mapValue(report['signingDiagnostics']);
    final xpcRuntimeDiagnostics = _mapValue(report['xpcRuntimeDiagnostics']);
    final permissionGate = _mapValue(report['permissionGate']);
    final captureGate = _mapValue(report['captureGate']);
    final inputGate = _mapValue(report['inputGate']);
    final audioGate = _mapValue(report['audioGate']);
    final unsafeActionGate = _mapValue(report['unsafeActionGate']);
    final positiveSmokeGateSummary = _mapValue(
      report['positiveSmokeGateSummary'],
    );
    final readinessExpectations = _mapValue(report['readinessExpectations']);
    final m4SignoffGate = _mapValue(report['m4SignoffGate']);
    final signingBlockers = _stringList(
      signingDiagnostics?['launchConstraintBlockers'],
    );
    final runtimeBlockers = _stringList(xpcRuntimeDiagnostics?['blockers']);
    final permissionBlockers = _stringList(
      permissionGate?['blockedByPermissions'],
    );
    final captureBlockers = _stringList(captureGate?['blockers']);
    final captureFailureClasses = _stringList(captureGate?['failureClasses']);
    final captureFailureClass = _stringValue(captureGate?['failureClass']);
    final captureNextAction = _stringValue(captureGate?['nextAction']);
    final inputBlockers = _stringList(inputGate?['blockers']);
    final audioBlockers = _stringList(audioGate?['blockers']);
    final unsafeBlockers = _stringList(unsafeActionGate?['blockers']);
    final positiveSmokeBlockers = _stringList(
      positiveSmokeGateSummary?['blockedBy'],
    );
    final failedExpectations = _stringList(readinessExpectations?['failed']);
    final m4SignoffBlockers = _stringList(m4SignoffGate?['blockers']);
    final m4SignoffHelperPath = _stringValue(
      _mapValue(m4SignoffGate?['helperPath'])?['embeddedHelperPath'],
    );
    final m4SignoffNextAction = _stringValue(m4SignoffGate?['nextAction']);

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
            if (signingDiagnostics != null)
              _StatusChip(
                label: 'Live Signing',
                value: signingBlockers.isEmpty,
                trueText: 'Accepted',
                falseText: 'Blocked',
              ),
            if (xpcRuntimeDiagnostics != null)
              _StatusChip(
                label: 'Live XPC Runtime',
                value: runtimeBlockers.isEmpty,
                trueText: 'Ready',
                falseText: 'Blocked',
              ),
            if (permissionGate != null)
              _StatusChip(
                label: 'Live Permissions',
                value: permissionBlockers.isEmpty,
                trueText: 'Clear',
                falseText: 'Blocked',
              ),
            if (captureGate != null)
              _StatusChip(
                label: 'Live Capture Gate',
                value: captureBlockers.isEmpty,
                trueText: 'Ready',
                falseText: '${captureGate['status']}',
              ),
            if (inputGate != null)
              _StatusChip(
                label: 'Live Input Gate',
                value: inputBlockers.isEmpty,
                trueText: 'Ready',
                falseText: '${inputGate['status']}',
              ),
            if (audioGate != null)
              _StatusChip(
                label: 'Live Audio Gate',
                value:
                    audioBlockers.isEmpty ||
                    audioGate['status'] == 'unsupported',
                trueText: audioGate['status'] == 'unsupported'
                    ? 'Unsupported'
                    : 'Ready',
                falseText: '${audioGate['status']}',
              ),
            if (unsafeActionGate != null)
              _StatusChip(
                label: 'Live Unsafe Gate',
                value: unsafeActionGate['unsafeArmed'] == true,
                trueText: 'Armed',
                falseText: 'Not armed',
              ),
            if (positiveSmokeGateSummary != null)
              _StatusChip(
                label: 'Live Positive Smoke',
                value: positiveSmokeGateSummary['status'] == 'ready',
                trueText: 'Ready',
                falseText: '${positiveSmokeGateSummary['status']}',
              ),
            if (readinessExpectations != null)
              _StatusChip(
                label: 'Live Expectations',
                value: readinessExpectations['ok'] == true,
                trueText: 'Passed',
                falseText: 'Failed',
              ),
            if (m4SignoffGate != null)
              _StatusChip(
                label: 'Live M4 Sign-off',
                value: m4SignoffGate['status'] == 'ready',
                trueText: 'Ready',
                falseText: '${m4SignoffGate['status']}',
              ),
          ],
        ),
        if (signingBlockers.isNotEmpty ||
            runtimeBlockers.isNotEmpty ||
            permissionBlockers.isNotEmpty ||
            captureBlockers.isNotEmpty ||
            inputBlockers.isNotEmpty ||
            audioBlockers.isNotEmpty ||
            unsafeBlockers.isNotEmpty ||
            positiveSmokeBlockers.isNotEmpty ||
            m4SignoffBlockers.isNotEmpty ||
            failedExpectations.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (signingBlockers.isNotEmpty)
                'signing: ${signingBlockers.join(', ')}',
              if (runtimeBlockers.isNotEmpty)
                'runtime: ${runtimeBlockers.join(', ')}',
              if (permissionBlockers.isNotEmpty)
                'permissions: ${permissionBlockers.join(', ')}',
              if (captureBlockers.isNotEmpty)
                'capture: ${captureBlockers.join(', ')}',
              if (inputBlockers.isNotEmpty)
                'input: ${inputBlockers.join(', ')}',
              if (audioBlockers.isNotEmpty)
                'audio: ${audioBlockers.join(', ')}',
              if (unsafeBlockers.isNotEmpty)
                'unsafe: ${unsafeBlockers.join(', ')}',
              if (positiveSmokeBlockers.isNotEmpty)
                'positive smoke: ${positiveSmokeBlockers.join(', ')}',
              if (m4SignoffBlockers.isNotEmpty)
                'm4: ${m4SignoffBlockers.join(', ')}',
              if (failedExpectations.isNotEmpty)
                'expectations: ${failedExpectations.join(', ')}',
            ].join(' | '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (m4SignoffHelperPath != null) ...[
          const SizedBox(height: 4),
          Text(
            'Live M4 helper: ${_shortPath(m4SignoffHelperPath)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (m4SignoffNextAction != null) ...[
          const SizedBox(height: 4),
          Text(
            'Live M4 next action: $m4SignoffNextAction',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (captureFailureClass != null && captureFailureClass != 'none') ...[
          const SizedBox(height: 4),
          Text(
            'Live capture failure: ${captureFailureClasses.isEmpty ? captureFailureClass : captureFailureClasses.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (captureNextAction != null) ...[
          const SizedBox(height: 4),
          Text(
            'Live capture next action: $captureNextAction',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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

  Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => '$item')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  String _shortPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 4) {
      return path;
    }
    return '.../${parts.sublist(parts.length - 4).join('/')}';
  }
}
