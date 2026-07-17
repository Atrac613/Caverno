import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/local_diagnostics_exporter.dart';
import '../../../../core/services/macos_computer_use_audit_log.dart';
import '../../../../core/services/macos_computer_use_service.dart';
import '../../../../core/services/macos_computer_use_setup.dart';
import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../../core/services/macos_computer_use_xpc_timing_report.dart';
import '../widgets/computer_use_action_gate_plan.dart';
import '../widgets/computer_use_audit_log_summary.dart';
import '../widgets/computer_use_ipc_runtime_summary.dart';
import '../widgets/computer_use_live_smoke_summary.dart';
import '../widgets/computer_use_permission_trust_panel.dart';
import '../widgets/computer_use_xpc_timing_summary.dart';
import 'computer_use_debug_page.dart';

class ComputerUseSettingsPage extends StatelessWidget {
  const ComputerUseSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_computer_use'.tr())),
      body: ListView(
        children: const [
          _ComputerUseSettingsHeader(),
          _ComputerUseOnboardingCard(),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ComputerUseSettingsHeader extends StatelessWidget {
  const _ComputerUseSettingsHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.admin_panel_settings_outlined,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'settings.computer_use_header_title'.tr(),
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'settings.computer_use_header_desc'.tr(),
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
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
      screenRecordingGrantFlowPendingRestart:
          _screenRecordingGrantFlowPendingRestart(),
    );
    final helperIpcRuntime = _helperIpcRuntime();
    final permissionRecoverySummary = _permissionRecoverySummary(
      backend: service.permissionBackendInfo,
      permissions: checklist.permissions,
      helperIpcRuntime: helperIpcRuntime,
      onboardingVerification: onboardingVerification,
      helperStatusPersistence: helperStatusPersistence,
    );
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
            ComputerUsePermissionTrustPanel(
              accessibilityGranted: accessibilityGranted,
              screenCaptureGranted: screenCaptureGranted,
              isLoading: _isLoading,
              recoverySummary: permissionRecoverySummary,
              onOpenAccessibility: () =>
                  _openPermissionSettings('accessibility'),
              onOpenScreenRecording: () =>
                  _openPermissionSettings('screen_recording'),
              onRecheck: () => _refresh(force: true),
            ),
            const SizedBox(height: 12),
            ComputerUseActionGatePlan(
              viewModel: ComputerUseActionGatePlanViewModel.fromState(
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
            ExpansionTile(
              key: const ValueKey('computer-use-settings-diagnostics'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.query_stats_outlined),
              title: const Text('Diagnostics'),
              subtitle: const Text(
                'Runtime status, saved smoke reports, redacted audit log, and privacy controls.',
              ),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
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
                        falseText: verificationRan
                            ? 'Needs attention'
                            : 'Not run',
                      ),
                      _StatusChip(
                        label: 'Helper Work',
                        value: !helperWorkActive,
                        trueText: 'Idle',
                        falseText: 'Active',
                      ),
                    ],
                  ),
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
                ComputerUseIpcRuntimeSummary(
                  viewModel: ComputerUseIpcRuntimeSummaryViewModel.fromRuntime(
                    helperIpcRuntime,
                  ),
                ),
                if (xpcTimingSummary['classification'] !=
                    'missing_preferred_attempt') ...[
                  const SizedBox(height: 8),
                  ComputerUseXpcTimingSummary(
                    viewModel: ComputerUseXpcTimingSummaryViewModel.fromSummary(
                      xpcTimingSummary,
                    ),
                  ),
                ],
                if (_lastLiveSmokeReport != null) ...[
                  const SizedBox(height: 8),
                  ComputerUseLiveSmokeSummary(
                    viewModel:
                        ComputerUseLiveSmokeSummaryViewModel.fromEnvelope(
                          _lastLiveSmokeReport!,
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                ComputerUseAuditLogSummary(
                  entries: MacosComputerUseAuditLog.instance.redactedEntries,
                  maxEntries: 3,
                ),
              ],
            ),
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
    required bool screenRecordingGrantFlowPendingRestart,
  }) {
    if (!helperInstalled || !helperRunning) {
      return const _ComputerUsePrimaryAction(
        kind: _ComputerUsePrimaryActionKind.launch,
        label: 'Open Computer Use',
        detail: 'Launch the helper app so it can execute approved OS actions.',
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
      if (screenRecordingGrantFlowPendingRestart) {
        return const _ComputerUsePrimaryAction(
          kind: _ComputerUsePrimaryActionKind.restart,
          label: 'Restart Helper',
          detail:
              'Restart Caverno Computer Use so macOS applies the screen recording grant.',
          icon: Icons.restart_alt,
        );
      }
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
        _lastPermissionOverlayResult = null;
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
    final service = ref.read(macosComputerUseServiceProvider);
    final setupChecklist = _setupChecklist(service.permissionBackendInfo);
    final permissionRecoverySummary = _permissionRecoverySummary(
      backend: service.permissionBackendInfo,
      permissions: setupChecklist.permissions,
      helperIpcRuntime: helperIpcRuntime,
      onboardingVerification: _onboardingVerification(),
      helperStatusPersistence: _helperStatusPersistence(),
    );
    final diagnostics = MacosComputerUseOnboardingDiagnostics(
      generatedAt: DateTime.now(),
      setupChecklist: setupChecklist,
      onboardingSmokeChecklist: _onboardingSmokeChecklist(),
      onboardingVerification: _onboardingVerification(),
      permissionRecoverySummary: permissionRecoverySummary.toJson(),
      productionActionPolicy:
          MacosComputerUseToolPolicy.productionActionPolicy().toJson(),
      helperStatus: _helperStatus,
      helperStatusPersistence: _helperStatusPersistence(),
      permissions: _permissions,
      helperIpcProtocol: MacosComputerUseIpc.current.toJson(),
      helperIpcRuntime: helperIpcRuntime,
      auditLog: MacosComputerUseAuditLog.instance.redactedEntries,
      auditPrivacyControls: MacosComputerUseAuditLog.instance.privacyControls,
      installMigrationGuardrails:
          MacosComputerUseInstallMigrationGuardrails.fromState(
            helperStatus: _helperStatus,
            helperIpcRuntime: helperIpcRuntime,
          ),
      lastAction: _lastActionLabel(),
      lastResult: {
        'helperStatus': _helperStatus,
        'helperStatusPersistence': _helperStatusPersistence(),
        'permissions': _permissions,
        'helperIpcRuntime': helperIpcRuntime,
        'permissionRecoverySummary': permissionRecoverySummary.toJson(),
        'installMigrationGuardrails':
            MacosComputerUseInstallMigrationGuardrails.fromState(
              helperStatus: _helperStatus,
              helperIpcRuntime: helperIpcRuntime,
            ),
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

  MacosComputerUsePermissionRecoverySummary _permissionRecoverySummary({
    required MacosComputerUseBackendInfo backend,
    required MacosComputerUsePermissionSnapshot? permissions,
    required Map<String, dynamic> helperIpcRuntime,
    required Map<String, dynamic>? onboardingVerification,
    required Map<String, dynamic>? helperStatusPersistence,
  }) {
    return MacosComputerUsePermissionRecoverySummary.fromState(
      backend: backend,
      permissions: permissions,
      helperStatus: _helperStatus,
      helperIpcRuntime: helperIpcRuntime,
      onboardingVerification: onboardingVerification,
      helperStatusPersistence: helperStatusPersistence,
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

  bool _screenRecordingGrantFlowPendingRestart() {
    final result = _lastPermissionOverlayResult;
    if (result == null) {
      return false;
    }
    final permission = result['permission'] ?? result['section'];
    final opened = result['settingsOpened'] == true || result['ok'] == true;
    return opened == true && permission == 'screenRecording';
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
      'mainAppOwnsTccPermissions':
          snapshot['mainAppOwnsTccPermissions'] ??
          MacosComputerUseIpc.current.mainAppOwnsTccPermissions,
      'tccPermissionOwnerBundleIdentifier':
          snapshot['tccPermissionOwnerBundleIdentifier'] ??
          MacosComputerUseIpc.current.tccPermissionOwnerBundleIdentifier,
      'tccPermissionOwnerDisplayName':
          snapshot['tccPermissionOwnerDisplayName'] ??
          MacosComputerUseIpc.current.tccPermissionOwnerDisplayName,
      'helperActsAsOsActionExecutor':
          snapshot['helperActsAsOsActionExecutor'] ??
          MacosComputerUseIpc.current.helperActsAsOsActionExecutor,
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
    runtime['installMigrationGuardrails'] =
        MacosComputerUseInstallMigrationGuardrails.fromState(
          helperStatus: snapshot,
          helperIpcRuntime: runtime,
        );
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
      'tccPermissionOwnerBundleIdentifier':
          MacosComputerUseIpc.current.tccPermissionOwnerBundleIdentifier,
      'tccPermissionOwnerDisplayName':
          MacosComputerUseIpc.current.tccPermissionOwnerDisplayName,
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
