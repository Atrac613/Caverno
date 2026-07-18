import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/local_diagnostics_exporter.dart';
import '../../../../core/services/macos_computer_use_audit_log.dart';
import '../../../../core/services/macos_computer_use_service.dart';
import '../../../../core/services/macos_computer_use_setup.dart';
import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../../core/services/macos_computer_use_xpc_timing_report.dart';
import '../widgets/computer_use_debug_diagnostics_cards.dart';
import '../widgets/computer_use_debug_image_preview.dart';
import '../widgets/computer_use_debug_onboarding_card.dart';
import '../widgets/computer_use_debug_status_primitives.dart';

class ComputerUseDebugPage extends ConsumerStatefulWidget {
  const ComputerUseDebugPage({super.key});

  @override
  ConsumerState<ComputerUseDebugPage> createState() =>
      _ComputerUseDebugPageState();
}

class _ComputerUseDebugPageState extends ConsumerState<ComputerUseDebugPage> {
  final _maxWidthController = TextEditingController(text: '1200');
  final _xController = TextEditingController(text: '40');
  final _yController = TextEditingController(text: '40');
  final _textController = TextEditingController();

  bool _isBusy = false;
  bool _audioRecording = false;
  bool _inputActionsArmed = false;
  bool _inputSmokeCompleted = false;
  bool _audioSmokeCompleted = false;
  bool _audioRecordingArmed = false;
  bool _manualSmokeRunning = false;
  String? _busyAction;
  String _lastAction = 'No action has run yet.';
  String _lastResult = 'Run a smoke check to see the native response.';
  Object? _lastResultForDiagnostics =
      'Run a smoke check to see the native response.';
  String? _lastDiagnosticExportPath;
  List<Map<String, dynamic>> _manualSmokeSteps = const [];
  Map<String, dynamic>? _helperStatus;
  Map<String, dynamic>? _permissions;
  Map<String, dynamic>? _lastLiveSmokeReport;
  Map<String, dynamic>? _lastExistingHelperProbeReport;
  List<Map<String, dynamic>> _windows = const [];
  int? _selectedWindowId;
  _CoordinateTarget? _coordinateTarget;
  ComputerUseDebugImageSnapshot? _displayScreenshot;
  ComputerUseDebugImageSnapshot? _windowScreenshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refreshHelperStatus();
    });
  }

  @override
  void dispose() {
    _maxWidthController.dispose();
    _xController.dispose();
    _yController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(macosComputerUseServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Computer Use Smoke Sequence')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isBusy) ...[
            LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: _busyAction ?? 'Running computer use action',
            ),
            const SizedBox(height: 12),
          ],
          if (!service.isAvailable) ...[
            _buildUnsupportedPlatformCard(context),
            const SizedBox(height: 12),
          ],
          _buildRuntimeBoundaryCard(),
          const SizedBox(height: 12),
          _buildPermissionsCard(service.permissionBackendInfo),
          const SizedBox(height: 12),
          ComputerUseDebugOnboardingCard(viewModel: _onboardingViewModel()),
          const SizedBox(height: 12),
          _buildDisplayScreenshotCard(),
          const SizedBox(height: 12),
          _buildWindowCard(),
          const SizedBox(height: 12),
          _buildInputCard(),
          const SizedBox(height: 12),
          _buildAudioCard(),
          const SizedBox(height: 12),
          ComputerUseDebugDiagnosticsCard(
            viewModel: ComputerUseDebugDiagnosticsViewModel(
              isBusy: _isBusy,
              auditEntries: MacosComputerUseAuditLog.instance.redactedEntries,
              lastExportPath: _lastDiagnosticExportPath,
            ),
            onRunSmokeSequence: _runManualSmokeSequence,
            onCopyDiagnostics: _copyDiagnostics,
            onExportDiagnostics: _exportDiagnostics,
          ),
          const SizedBox(height: 12),
          ComputerUseDebugResultCard(
            lastAction: _lastAction,
            lastResult: _lastResult,
          ),
        ],
      ),
    );
  }

  Widget _buildUnsupportedPlatformCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'These smoke checks use the native macOS computer-use channel.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuntimeBoundaryCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: ComputerUseDebugOnboardingNote(
          icon: Icons.front_hand_outlined,
          title: 'User-Operated Runtime Boundary',
          body:
              'Use this page to inspect helper readiness and run smoke checks. TCC grants, System Settings changes, and real desktop actions must be performed by the user.',
        ),
      ),
    );
  }

  Widget _buildPermissionsCard(MacosComputerUseBackendInfo backend) {
    final setupChecklist = _setupChecklist(backend);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComputerUseDebugSectionTitle(
              icon: Icons.verified_user_outlined,
              title: 'Permissions',
              subtitle:
                  'Launch the helper, then grant Accessibility and Screen & System Audio Recording to Caverno Computer Use.',
            ),
            const SizedBox(height: 12),
            ComputerUseDebugHelperBoundaryPanel(
              backend: setupChecklist.backend,
            ),
            const SizedBox(height: 12),
            _buildPermissionChecklist(backend),
            const SizedBox(height: 12),
            ComputerUseDebugStatusRow(
              label: 'Helper Installed',
              value: _permissionValue('helperInstalled'),
              trueLabel: 'Installed',
              falseLabel: 'Missing',
              unknownLabel: 'Unknown',
            ),
            ComputerUseDebugStatusRow(
              label: 'Helper Running',
              value: _permissionValue('helperRunning'),
              trueLabel: 'Running',
              falseLabel: 'Stopped',
              unknownLabel: 'Unknown',
            ),
            ComputerUseDebugStatusRow(
              label: 'Helper Reachable',
              value: _permissionValue('helperReachable'),
              trueLabel: 'Reachable',
              falseLabel: 'Unreachable',
              unknownLabel: 'Unknown',
            ),
            if (_helperStatus?['helperPathMismatch'] == true) ...[
              const SizedBox(height: 8),
              ComputerUseDebugOnboardingNote(
                icon: Icons.route_outlined,
                title: 'Helper Path Mismatch',
                body: [
                  'Running: ${_shortPath('${_helperStatus?['runningHelperPath']}')}',
                  'Expected: ${_shortPath('${_helperStatus?['embeddedHelperPath'] ?? _helperStatus?['helperPath']}')}',
                  if (_helperPathSignoffSummary() != null)
                    'Sign-off: ${_helperPathSignoffSummary()}',
                  if (_helperPathMismatchNextAction() != null)
                    'Next: ${_helperPathMismatchNextAction()}',
                ].join(' | '),
              ),
            ],
            if (_existingHelperProbeSummary() != null) ...[
              const SizedBox(height: 8),
              ComputerUseDebugOnboardingNote(
                icon: Icons.fact_check_outlined,
                title: 'Existing Helper Probe',
                body: _existingHelperProbeSummary()!,
              ),
            ],
            if (_manualTccHandoffSummary() != null) ...[
              const SizedBox(height: 8),
              ComputerUseDebugOnboardingNote(
                icon: Icons.privacy_tip_outlined,
                title: 'Manual TCC Handoff',
                body: _manualTccHandoffSummary()!,
              ),
            ],
            if (_overlayCanarySummary() != null) ...[
              const SizedBox(height: 8),
              ComputerUseDebugOnboardingNote(
                icon: Icons.picture_in_picture_alt_outlined,
                title: 'Overlay Canary',
                body: _overlayCanarySummary()!,
              ),
            ],
            const SizedBox(height: 8),
            ComputerUseDebugOnboardingNote(
              icon: Icons.fact_check_outlined,
              title: 'MVP Sign-Off Path',
              body: _mvpSignoffSummary(),
            ),
            const SizedBox(height: 8),
            ComputerUseDebugOnboardingNote(
              icon: Icons.checklist_outlined,
              title: 'MVP Evidence Preflight',
              body: _mvpEvidencePreflightSummary(),
            ),
            const SizedBox(height: 8),
            ComputerUseDebugOnboardingNote(
              icon: Icons.rule_folder_outlined,
              title: 'MVP Missing Evidence Checklist',
              body: _mvpMissingEvidenceChecklistSummary(),
            ),
            const SizedBox(height: 8),
            ComputerUseDebugOnboardingNote(
              icon: Icons.terminal_outlined,
              title: 'User-Operated MVP Commands',
              body: _mvpUserOperatedCommandSummary(),
            ),
            const SizedBox(height: 8),
            ComputerUseDebugOnboardingNote(
              icon: Icons.folder_open_outlined,
              title: 'MVP Artifact Paths',
              body: _mvpArtifactPathSummary(),
            ),
            const SizedBox(height: 8),
            ComputerUseDebugOnboardingNote(
              icon: Icons.rate_review_outlined,
              title: 'MVP PR Review Summary',
              body: _mvpPrReviewSummary(),
            ),
            ComputerUseDebugPermissionRow(
              label: 'Accessibility',
              value: _permissionValue('accessibilityGranted'),
              openSettingsTooltip: 'Open Accessibility Settings',
              onOpenSettings: () => _openSystemSettings(
                section: 'accessibility',
                action: 'Open Accessibility Settings',
              ),
            ),
            ComputerUseDebugPermissionRow(
              label: 'Screen & System Audio Recording',
              value: _permissionValue('screenCaptureGranted'),
              openSettingsTooltip: 'Open Screen Recording Settings',
              onOpenSettings: () => _openSystemSettings(
                section: 'screen_recording',
                action: 'Open Screen Recording Settings',
              ),
            ),
            ComputerUseDebugPermissionRow(
              label: 'System Audio Supported',
              value: _permissionValue('systemAudioRecordingSupported'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  key: const ValueKey('computer-use-launch-helper'),
                  icon: Icons.rocket_launch_outlined,
                  label: 'Launch Helper',
                  onPressed: _launchHelper,
                ),
                _actionButton(
                  key: const ValueKey('computer-use-restart-helper'),
                  icon: Icons.restart_alt,
                  label: 'Restart Helper',
                  onPressed: _restartHelper,
                ),
                _actionButton(
                  key: const ValueKey('computer-use-ping-helper'),
                  icon: Icons.sensors_outlined,
                  label: 'Ping Helper',
                  onPressed: () => _run(
                    'Ping helper',
                    (service) => service.pingHelper(),
                    onResult: _storeHelperStatus,
                  ),
                ),
                _actionButton(
                  icon: Icons.refresh,
                  label: 'Refresh',
                  onPressed: _refreshPermissions,
                ),
                _actionButton(
                  icon: Icons.accessibility_new_outlined,
                  label: 'Request Accessibility',
                  onPressed: () => _run(
                    'Request Accessibility',
                    (service) => service.requestPermissions(
                      accessibility: true,
                      screenCapture: false,
                    ),
                    onResult: _storePermissions,
                  ),
                ),
                _actionButton(
                  key: const ValueKey(
                    'computer-use-open-accessibility-settings',
                  ),
                  icon: Icons.settings_outlined,
                  label: 'Open Accessibility Settings',
                  onPressed: () => _openSystemSettings(
                    section: 'accessibility',
                    action: 'Open Accessibility Settings',
                  ),
                ),
                _actionButton(
                  icon: Icons.screenshot_monitor_outlined,
                  label: 'Request Screen Recording',
                  onPressed: () => _run(
                    'Request Screen Recording',
                    (service) => service.requestPermissions(
                      accessibility: false,
                      screenCapture: true,
                    ),
                    onResult: _storePermissions,
                  ),
                ),
                _actionButton(
                  key: const ValueKey('computer-use-stop-helper-work'),
                  icon: Icons.stop_circle_outlined,
                  label: 'Stop Helper Work',
                  onPressed: () => _run(
                    'Stop helper work',
                    (service) => service.stopHelperWork(),
                    onResult: _storeHelperStatus,
                  ),
                ),
                _actionButton(
                  key: const ValueKey(
                    'computer-use-open-screen-recording-settings',
                  ),
                  icon: Icons.settings_applications_outlined,
                  label: 'Open Screen Recording Settings',
                  onPressed: () => _openSystemSettings(
                    section: 'screen_recording',
                    action: 'Open Screen Recording Settings',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplayScreenshotCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComputerUseDebugSectionTitle(
              icon: Icons.desktop_mac_outlined,
              title: 'Display Screenshot',
              subtitle: 'Capture the main display and preview the PNG payload.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _maxWidthController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max image width',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _actionButton(
              icon: Icons.camera_alt_outlined,
              label: 'Capture Display',
              onPressed: () => _run(
                'Capture display screenshot',
                (service) => service.screenshot({'max_width': _maxWidth()}),
                onResult: (result) {
                  final snapshot = _imageSnapshot(result, 'Display screenshot');
                  if (snapshot != null) {
                    _displayScreenshot = snapshot;
                    _coordinateTarget = _CoordinateTarget.display;
                  }
                },
              ),
            ),
            if (_displayScreenshot != null) ...[
              const SizedBox(height: 12),
              ComputerUseDebugImagePreview(
                key: const ValueKey('computer-use-display-preview'),
                snapshot: _displayScreenshot!,
                active: _coordinateTarget == _CoordinateTarget.display,
                tapAreaKey: const ValueKey(
                  'computer-use-display-preview-tap-area',
                ),
                onPointSelected: (point) =>
                    _selectImagePoint(_CoordinateTarget.display, point),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWindowCard() {
    final selectedWindow = _selectedWindow();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComputerUseDebugSectionTitle(
              icon: Icons.web_asset_outlined,
              title: 'Window Targeting',
              subtitle:
                  'List visible windows, focus one, and capture a window-relative screenshot.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  icon: Icons.list_alt_outlined,
                  label: 'List Windows',
                  onPressed: () => _run(
                    'List windows',
                    (service) => service.listWindows({
                      'include_current_app': true,
                      'max_windows': 80,
                    }),
                    onResult: _storeWindows,
                  ),
                ),
                _actionButton(
                  icon: Icons.filter_center_focus_outlined,
                  label: 'Focus Selected',
                  onPressed: _selectedWindowId == null
                      ? null
                      : () => _run(
                          'Focus selected window',
                          (service) => service.focusWindow({
                            'window_id': _selectedWindowId,
                            'reason': 'Debug smoke test',
                          }),
                        ),
                ),
                _actionButton(
                  icon: Icons.crop_free_outlined,
                  label: 'Capture Selected',
                  onPressed: _selectedWindowId == null
                      ? null
                      : () => _run(
                          'Capture selected window',
                          (service) => service.screenshotWindow({
                            'window_id': _selectedWindowId,
                            'max_width': _maxWidth(),
                          }),
                          onResult: (result) {
                            final snapshot = _imageSnapshot(
                              result,
                              _windowTitle(result),
                            );
                            if (snapshot != null) {
                              _windowScreenshot = snapshot;
                              _coordinateTarget = _CoordinateTarget.window;
                            }
                          },
                        ),
                ),
              ],
            ),
            if (_windows.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(_selectedWindowId),
                initialValue: _selectedWindowId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Selected window',
                  border: OutlineInputBorder(),
                ),
                items: _windows
                    .map((window) {
                      final id = _windowId(window);
                      if (id == null) {
                        return null;
                      }
                      return DropdownMenuItem<int>(
                        value: id,
                        child: Text(
                          _windowLabel(window),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    })
                    .whereType<DropdownMenuItem<int>>()
                    .toList(),
                onChanged: _isBusy
                    ? null
                    : (value) => setState(() {
                        if (_selectedWindowId != value) {
                          _selectedWindowId = value;
                          _windowScreenshot = null;
                          if (_coordinateTarget == _CoordinateTarget.window) {
                            _coordinateTarget = null;
                          }
                        }
                      }),
              ),
            ],
            if (selectedWindow != null) ...[
              const SizedBox(height: 8),
              Text(
                _windowBoundsLabel(selectedWindow),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_windowScreenshot != null) ...[
              const SizedBox(height: 12),
              ComputerUseDebugImagePreview(
                key: const ValueKey('computer-use-window-preview'),
                snapshot: _windowScreenshot!,
                active: _coordinateTarget == _CoordinateTarget.window,
                tapAreaKey: const ValueKey(
                  'computer-use-window-preview-tap-area',
                ),
                onPointSelected: (point) =>
                    _selectImagePoint(_CoordinateTarget.window, point),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    final hasTarget = _hasCoordinateTarget;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComputerUseDebugSectionTitle(
              icon: Icons.ads_click_outlined,
              title: 'Input Smoke Checks',
              subtitle:
                  'Run explicit input events against the selected window or display coordinates.',
            ),
            const SizedBox(height: 12),
            ComputerUseDebugArmSwitch(
              title: 'Input Events Armed',
              subtitle:
                  'Required before moving the pointer, clicking, or typing text.',
              value: _inputActionsArmed,
              onChanged: _isBusy
                  ? null
                  : (value) => setState(() => _inputActionsArmed = value),
            ),
            const SizedBox(height: 12),
            ComputerUseDebugCoordinateTargetRow(label: _coordinateTargetLabel),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _xController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'X',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _yController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Y',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Text to type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  icon: Icons.mouse_outlined,
                  label: 'Move Pointer',
                  onPressed: hasTarget && _inputActionsArmed
                      ? _movePointer
                      : null,
                ),
                _actionButton(
                  icon: Icons.touch_app_outlined,
                  label: 'Click Point',
                  onPressed: hasTarget && _inputActionsArmed
                      ? _clickPoint
                      : null,
                ),
                _actionButton(
                  icon: Icons.keyboard_alt_outlined,
                  label: 'Type Text',
                  onPressed: _inputActionsArmed ? _typeText : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComputerUseDebugSectionTitle(
              icon: Icons.graphic_eq_outlined,
              title: 'System Audio',
              subtitle:
                  'Start and stop a ScreenCaptureKit system audio recording.',
            ),
            const SizedBox(height: 12),
            ComputerUseDebugArmSwitch(
              title: 'System Audio Armed',
              subtitle: 'Required before starting a system audio recording.',
              value: _audioRecordingArmed,
              onChanged: _isBusy || _audioRecording
                  ? null
                  : (value) => setState(() => _audioRecordingArmed = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _audioRecording
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _audioRecording
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).disabledColor,
                ),
                const SizedBox(width: 8),
                Text(_audioRecording ? 'Recording active' : 'Not recording'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  icon: Icons.fiber_manual_record_outlined,
                  label: 'Start Recording',
                  onPressed: _audioRecording || !_audioRecordingArmed
                      ? null
                      : _startAudioRecording,
                ),
                _actionButton(
                  icon: Icons.stop_circle_outlined,
                  label: 'Stop Recording',
                  onPressed: !_audioRecording
                      ? null
                      : () => _run(
                          'Stop system audio recording',
                          (service) => service.stopSystemAudioRecording(),
                          onResult: (result) {
                            if (result['ok'] == true) {
                              _audioSmokeCompleted = true;
                              _audioRecording = false;
                            } else if (result['code'] == 'not_recording') {
                              _audioRecording = false;
                            }
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.tonalIcon(
      key: key,
      onPressed: _isBusy ? null : onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildPermissionChecklist(MacosComputerUseBackendInfo backend) {
    final setupChecklist = _setupChecklist(backend);
    final hasSnapshot = setupChecklist.hasSnapshot;
    final ready = setupChecklist.isReady;
    final colorScheme = Theme.of(context).colorScheme;
    final icon = ready
        ? Icons.task_alt_outlined
        : hasSnapshot
        ? Icons.warning_amber_outlined
        : Icons.info_outline;
    final color = ready
        ? colorScheme.primary
        : hasSnapshot
        ? colorScheme.error
        : colorScheme.secondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    setupChecklist.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    setupChecklist.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSystemSettings({
    required String section,
    required String action,
  }) {
    return _run(
      action,
      (service) => service.openSystemSettings(section: section),
    );
  }

  Future<void> _launchHelper() async {
    await _run(
      'Launch helper',
      (service) => service.launchHelper(),
      onResult: _storeHelperStatus,
    );
    await _run(
      'Wait for helper IPC readiness',
      (service) => service.waitForHelperIpcReady(),
      onResult: _storeHelperStatus,
    );
    await _refreshHelperStatus(refreshPermissions: true);
  }

  Future<void> _restartHelper() async {
    await _run(
      'Restart helper',
      (service) => service.restartHelper(),
      onResult: _storeHelperStatus,
    );
    await _run(
      'Wait for helper IPC readiness',
      (service) => service.waitForHelperIpcReady(),
      onResult: _storeHelperStatus,
    );
    await _refreshHelperStatus(refreshPermissions: true);
  }

  Future<void> _refreshPermissions() async {
    await _run(
      'Refresh permissions',
      (service) => service.getPermissions(),
      onResult: _storePermissions,
    );
    await _refreshHelperStatus();
  }

  Future<void> _refreshHelperStatus({bool refreshPermissions = false}) async {
    final service = ref.read(macosComputerUseServiceProvider);
    final nextHelperStatus = <String, dynamic>{...?_helperStatus};
    Map<String, dynamic>? nextPermissions;
    Map<String, dynamic>? nextLiveSmokeReport;
    Map<String, dynamic>? nextExistingHelperProbeReport;

    try {
      for (final raw in [
        await service.getHelperStatus(),
        await service.pingHelper(),
      ]) {
        final decoded = _decodeMap(raw);
        if (decoded != null) {
          nextHelperStatus.addAll(decoded);
        }
      }
      if (refreshPermissions) {
        nextPermissions = _decodeMap(await service.getPermissions());
      }
      nextLiveSmokeReport = _liveSmokeReportFrom(
        _decodeMap(await service.getLastLiveSmokeReport()),
      );
      nextExistingHelperProbeReport = _liveSmokeReportFrom(
        _decodeMap(await service.getLastExistingHelperProbeReport()),
      );
    } catch (error) {
      nextHelperStatus.addAll({'ok': false, 'error': error.toString()});
    }

    if (!mounted) {
      return;
    }
    setState(() {
      if (nextHelperStatus.isNotEmpty) {
        _helperStatus = nextHelperStatus;
      }
      if (nextPermissions != null) {
        _storePermissions(nextPermissions);
      }
      _lastLiveSmokeReport = nextLiveSmokeReport;
      _lastExistingHelperProbeReport = nextExistingHelperProbeReport;
    });
  }

  Future<void> _movePointer() async {
    final coordinates = _coordinates();
    if (coordinates == null) {
      return;
    }
    await _run(
      'Move pointer',
      (service) => service.moveMouse(_coordinateArguments(coordinates)),
      onResult: (result) {
        if (result['ok'] == true) {
          _inputSmokeCompleted = true;
        }
      },
    );
    _disarmInputActions();
  }

  Future<void> _clickPoint() async {
    final coordinates = _coordinates();
    if (coordinates == null) {
      return;
    }
    final arguments = _coordinateArguments(coordinates)
      ..addAll({'button': 'left', 'click_count': 1});
    await _run(
      'Click point',
      (service) => service.click(arguments),
      onResult: (result) {
        if (result['ok'] == true) {
          _inputSmokeCompleted = true;
        }
      },
    );
    _disarmInputActions();
  }

  void _selectImagePoint(
    _CoordinateTarget target,
    ComputerUseDebugImagePoint point,
  ) {
    setState(() {
      _coordinateTarget = target;
      _xController.text = point.x.round().toString();
      _yController.text = point.y.round().toString();
    });
  }

  Future<void> _typeText() async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter text before running Type Text.')),
      );
      return;
    }
    await _run(
      'Type text',
      (service) => service.typeText({'text': text}),
      onResult: (result) {
        if (result['ok'] == true) {
          _inputSmokeCompleted = true;
        }
      },
    );
    _disarmInputActions();
  }

  Future<void> _startAudioRecording() async {
    await _run(
      'Start system audio recording',
      (service) => service.startSystemAudioRecording({
        'exclude_current_process_audio': true,
      }),
      onResult: (result) {
        if (result['ok'] == true) {
          _audioRecording = true;
        }
        _audioRecordingArmed = false;
      },
    );
    if (mounted && _audioRecordingArmed) {
      setState(() => _audioRecordingArmed = false);
    }
  }

  Future<void> _runManualSmokeSequence() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
      _manualSmokeRunning = true;
      _manualSmokeSteps = const [];
      _busyAction = 'Run smoke sequence';
      _lastAction = 'Run smoke sequence';
    });

    final service = ref.read(macosComputerUseServiceProvider);
    final steps = <Map<String, dynamic>>[];

    void publishSteps() {
      if (!mounted) {
        return;
      }
      final stepSnapshot = steps
          .map((step) => Map<String, dynamic>.from(step))
          .toList(growable: false);
      setState(() {
        _manualSmokeSteps = stepSnapshot;
        _lastResultForDiagnostics = {'manualSmokeSteps': stepSnapshot};
        _lastResult = const JsonEncoder.withIndent(
          '  ',
        ).convert(_lastResultForDiagnostics);
      });
    }

    Future<Map<String, dynamic>?> runStep(
      String id,
      String label,
      Future<String> Function(MacosComputerUseService service) invoke, {
      void Function(Map<String, dynamic> result)? onResult,
    }) async {
      try {
        final raw = await invoke(service);
        final decoded = _decodeMap(raw);
        final ok = decoded == null ? false : decoded['ok'] != false;
        if (decoded != null) {
          onResult?.call(decoded);
        }
        steps.add({
          'id': id,
          'label': label,
          'ok': ok,
          'skipped': false,
          'result': decoded == null ? raw : _redactForDisplay(decoded),
        });
        publishSteps();
        return decoded;
      } catch (error) {
        steps.add({
          'id': id,
          'label': label,
          'ok': false,
          'skipped': false,
          'error': error.toString(),
        });
        publishSteps();
        return null;
      }
    }

    void skipStep(String id, String label, String reason) {
      steps.add({
        'id': id,
        'label': label,
        'ok': true,
        'skipped': true,
        'reason': reason,
      });
      publishSteps();
    }

    try {
      await runStep(
        'launch_helper',
        'Launch Caverno Computer Use',
        (service) => service.launchHelper(),
        onResult: _storeHelperStatus,
      );
      await runStep(
        'verify_helper_ipc',
        'Verify helper IPC reachability',
        (service) => service.pingHelper(),
        onResult: _storeHelperStatus,
      );
      await runStep(
        'refresh_permissions',
        'Refresh split permissions',
        (service) => service.getPermissions(),
        onResult: _storePermissions,
      );
      await runStep(
        'capture_display',
        'Capture a display screenshot',
        (service) => service.screenshot({'max_width': _maxWidth()}),
        onResult: (result) {
          final snapshot = _imageSnapshot(result, 'Display screenshot');
          if (snapshot != null) {
            _displayScreenshot = snapshot;
            _coordinateTarget = _CoordinateTarget.display;
          }
        },
      );
      await runStep(
        'list_windows',
        'List visible windows',
        (service) => service.listWindows({
          'include_current_app': true,
          'max_windows': 80,
        }),
        onResult: _storeWindows,
      );

      final selectedWindowId = _selectedWindowId;
      if (selectedWindowId == null) {
        skipStep(
          'capture_window',
          'Capture a selected window screenshot',
          'No selectable window was returned.',
        );
      } else {
        await runStep(
          'capture_window',
          'Capture a selected window screenshot',
          (service) => service.screenshotWindow({
            'window_id': selectedWindowId,
            'max_width': _maxWidth(),
          }),
          onResult: (result) {
            final snapshot = _imageSnapshot(result, _windowTitle(result));
            if (snapshot != null) {
              _windowScreenshot = snapshot;
              _coordinateTarget = _CoordinateTarget.window;
            }
          },
        );
      }

      if (_inputActionsArmed) {
        final coordinates = _coordinates();
        if (coordinates == null) {
          skipStep(
            'run_input_smoke',
            'Run an armed input smoke check',
            'Coordinates were not valid.',
          );
        } else {
          await runStep(
            'run_input_smoke',
            'Move pointer at selected coordinates',
            (service) => service.moveMouse(_coordinateArguments(coordinates)),
            onResult: (result) {
              if (result['ok'] == true) {
                _inputSmokeCompleted = true;
              }
              _inputActionsArmed = false;
            },
          );
        }
      } else {
        skipStep(
          'run_input_smoke',
          'Run an armed input smoke check',
          'Input events were not armed.',
        );
      }

      if (_audioRecordingArmed) {
        await runStep(
          'run_audio_smoke',
          'Start and stop an armed system audio recording',
          _startAndStopSystemAudioForSmoke,
          onResult: (result) {
            if (result['ok'] == true) {
              _audioSmokeCompleted = true;
            }
            _audioRecording = false;
            _audioRecordingArmed = false;
          },
        );
      } else {
        skipStep(
          'run_audio_smoke',
          'Start and stop an armed system audio recording',
          'System audio recording was not armed.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _manualSmokeRunning = false;
          _busyAction = null;
          _lastAction = 'Run smoke sequence';
        });
      }
    }
  }

  Future<String> _startAndStopSystemAudioForSmoke(
    MacosComputerUseService service,
  ) async {
    Map<String, dynamic>? start;
    Object? startError;
    Map<String, dynamic>? stop;
    Object? stopError;
    var started = false;
    var stopAttempted = false;

    try {
      final startRaw = await service.startSystemAudioRecording({
        'exclude_current_process_audio': true,
      });
      start = _decodeMap(startRaw);
      started = start?['ok'] == true;
      if (started) {
        _audioRecording = true;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (error) {
      startError = error;
    } finally {
      try {
        stopAttempted = true;
        final stopRaw = await service.stopSystemAudioRecording();
        stop = _decodeMap(stopRaw) ?? {'raw': stopRaw};
      } catch (error) {
        stopError = error;
      }
      _audioRecording = false;
    }

    return jsonEncode({
      'ok': started && stop?['ok'] == true,
      'start': start,
      if (startError != null) 'startError': startError.toString(),
      'stop': stop,
      if (stopError != null) 'stopError': stopError.toString(),
      'stopAttempted': stopAttempted,
    });
  }

  void _disarmInputActions() {
    if (!mounted || !_inputActionsArmed) {
      return;
    }
    setState(() => _inputActionsArmed = false);
  }

  Future<void> _copyDiagnostics() async {
    final diagnostics = _diagnosticsJson();
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard.')),
    );
  }

  Future<void> _exportDiagnostics() async {
    try {
      final diagnostics = _diagnosticsJson();
      final path = await exportLocalDiagnostics(
        filePrefix: 'caverno-computer-use-smoke',
        contents: diagnostics,
      );
      if (!mounted) {
        return;
      }
      setState(() => _lastDiagnosticExportPath = path);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Diagnostics exported to $path')));
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

  Future<void> _run(
    String action,
    Future<String> Function(MacosComputerUseService service) invoke, {
    void Function(Map<String, dynamic> result)? onResult,
  }) async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
      _busyAction = action;
      _lastAction = action;
    });

    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final raw = await invoke(service);
      final decoded = _decodeMap(raw);
      if (!mounted) {
        return;
      }
      setState(() {
        final redacted = decoded == null ? raw : _redactForDisplay(decoded);
        _lastResultForDiagnostics = redacted;
        _lastResult = redacted is String
            ? redacted
            : const JsonEncoder.withIndent('  ').convert(redacted);
        if (decoded != null) {
          onResult?.call(decoded);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResult = 'Unexpected error: $error';
        _lastResultForDiagnostics = {'error': error.toString()};
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyAction = null;
        });
      }
    }
  }

  String _diagnosticsJson() {
    return const JsonEncoder.withIndent('  ').convert(_diagnosticsMap());
  }

  Map<String, dynamic> _diagnosticsMap() {
    final diagnostics = MacosComputerUseOnboardingDiagnostics(
      generatedAt: DateTime.now(),
      setupChecklist: _setupChecklist(
        ref.read(macosComputerUseServiceProvider).permissionBackendInfo,
      ),
      onboardingSmokeChecklist: _onboardingSmokeChecklist(),
      onboardingVerification: _onboardingVerification(),
      productionActionPolicy:
          MacosComputerUseToolPolicy.productionActionPolicy().toJson(),
      helperStatus: _helperStatus,
      helperStatusPersistence: _helperStatusPersistence(),
      permissions: _permissions,
      audioRecording: _audioRecording,
      inputActionsArmed: _inputActionsArmed,
      inputSmokeCompleted: _inputSmokeCompleted,
      audioSmokeCompleted: _audioSmokeCompleted,
      audioRecordingArmed: _audioRecordingArmed,
      manualSmokeRunning: _manualSmokeRunning,
      manualSmokeSteps: _manualSmokeSteps,
      helperIpcProtocol: _helperIpcProtocol(),
      migratedCommands: _migratedCommands(),
      selectedWindowId: _selectedWindowId,
      selectedWindow: _selectedWindow(),
      windowCount: _windows.length,
      coordinateTarget: _coordinateTargetName,
      coordinates: _coordinateMap(),
      displayScreenshot: _imageSummary(_displayScreenshot),
      windowScreenshot: _imageSummary(_windowScreenshot),
      lastAction: _lastAction,
      lastResult: _lastResultForDiagnostics,
      auditLog: MacosComputerUseAuditLog.instance.redactedEntries,
      auditPrivacyControls: MacosComputerUseAuditLog.instance.privacyControls,
      installMigrationGuardrails:
          MacosComputerUseInstallMigrationGuardrails.fromState(
            helperStatus: _helperStatus,
            helperIpcRuntime: _helperIpcProtocol(),
          ),
      lastLiveSmokeReport: _lastLiveSmokeReport,
      lastExistingHelperProbeReport: _lastExistingHelperProbeReport,
      lastDiagnosticExportPath: _lastDiagnosticExportPath,
    ).toJson()..['mvpArtifactPaths'] = _mvpArtifactPaths();
    diagnostics['xpcTimingReport'] = buildXpcTimingReportSummary(
      diagnostics,
      sourcePath: 'computer_use_debug_page_diagnostics',
    ).toJson();
    return diagnostics;
  }

  List<Map<String, dynamic>> _onboardingSmokeChecklist() {
    final manualSmokeComplete =
        _manualSmokeSteps.isNotEmpty &&
        _manualSmokeSteps.every((step) => step['ok'] == true);
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
        'id': 'capture_display',
        'label': 'Capture a display screenshot',
        'complete': _displayScreenshot != null,
      },
      {
        'id': 'capture_window',
        'label': 'Capture a selected window screenshot',
        'complete': _windowScreenshot != null,
      },
      {
        'id': 'run_smoke_sequence',
        'label': 'Run the semi-automated smoke sequence',
        'complete': manualSmokeComplete,
      },
      {
        'id': 'run_input_smoke',
        'label': 'Run an armed input smoke check',
        'complete': _inputSmokeCompleted,
      },
      {
        'id': 'run_audio_smoke',
        'label': 'Start and stop an armed system audio recording',
        'complete': _audioSmokeCompleted,
      },
      {
        'id': 'export_diagnostics',
        'label': 'Export redacted diagnostics',
        'complete': _lastDiagnosticExportPath != null,
      },
    ];
  }

  ComputerUseDebugOnboardingViewModel _onboardingViewModel() {
    final ipc = MacosComputerUseIpc.current;
    return ComputerUseDebugOnboardingViewModel(
      steps: _onboardingSmokeChecklist().map(
        (step) => ComputerUseDebugOnboardingStep(
          label: '${step['label']}',
          complete: step['complete'] == true,
        ),
      ),
      xpcProductionBlockers: ipc.xpcProductionBlockers,
      xpcProductionNextAction: ipc.xpcProductionNextAction,
    );
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

  String? _helperPathMismatchNextAction() {
    final details = _helperStatus?['helperPathMismatchDetails'];
    if (details is Map) {
      final nextAction = details['nextAction'];
      if (nextAction is String && nextAction.isNotEmpty) {
        return nextAction;
      }
    }
    return null;
  }

  String? _helperPathSignoffSummary() {
    if (_helperStatus == null) {
      return null;
    }
    final mismatch = _helperStatus?['helperPathMismatch'] == true;
    final preserved = _helperStatus?['preservedMismatchedHelperPath'] == true;
    final matches = _helperStatus?['helperPathMatchesRunningHelper'] == true;
    if (mismatch || preserved) {
      return 'blocked until helper path matches';
    }
    return matches ? 'ready' : 'unknown';
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

  Map<String, dynamic> _helperIpcProtocol() {
    return MacosComputerUseIpc.current.toJson();
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

  String _shortPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 4) {
      return path;
    }
    return '.../${parts.sublist(parts.length - 4).join('/')}';
  }

  Map<String, dynamic>? _reportBody(Map<String, dynamic>? envelope) {
    if (envelope == null) {
      return null;
    }
    final report = envelope['report'];
    if (report is Map) {
      return Map<String, dynamic>.from(report);
    }
    return envelope;
  }

  String? _existingHelperProbeSummary() {
    final report = _reportBody(_lastExistingHelperProbeReport);
    if (report == null) {
      return null;
    }
    final helper = report['helper'];
    final helperMap = helper is Map ? Map<String, dynamic>.from(helper) : null;
    final ok = report['ok'] == true;
    final captureReady = report['captureReady'] == true;
    final pathMatches =
        report['helperPathMatchesExpected'] == true ||
        helperMap?['pathMatchesExpected'] == true;
    final failedChecks = _stringList(report['failedRequiredChecks']);
    final path = _lastExistingHelperProbeReport?['path'];
    return [
      ok ? 'passed' : 'failed',
      'capture ${captureReady ? 'ready' : 'blocked'}',
      'path ${pathMatches ? 'matched' : 'mismatch'}',
      if (failedChecks.isNotEmpty) 'failed ${failedChecks.join(', ')}',
      if (path is String) _shortPath(path),
    ].join(' | ');
  }

  String? _manualTccHandoffSummary() {
    final report = _reportBody(_lastLiveSmokeReport);
    if (report == null) {
      return null;
    }
    final handoff = report['manualTccHandoff'];
    if (handoff is! Map) {
      return null;
    }
    final handoffMap = Map<String, dynamic>.from(handoff);
    final status = handoffMap['status'] as String? ?? 'manual_required';
    final handoffCommand =
        handoffMap['handoffCommand'] as String? ??
        MacosComputerUseMvpGuidance.manualTccHandoffCommand;
    final command = handoffMap['manualCommand'] as String?;
    final parser = handoffMap['summaryCommand'] as String?;
    final helperPath = handoffMap['helperPath'] as String?;
    return [
      status,
      handoffCommand,
      ?command,
      ?parser,
      if (helperPath != null) _shortPath(helperPath),
    ].join(' | ');
  }

  String _mvpSignoffSummary() {
    return [
      'Wrapper: ${MacosComputerUseMvpGuidance.mvpSignoffCommand}',
      'Final aggregation: ${MacosComputerUseMvpGuidance.finalAggregationCommand}',
      'Required inputs: manual TCC ${MacosComputerUseMvpGuidance.manualTccSummaryFile}, desktop action ${MacosComputerUseMvpGuidance.desktopActionSummaryFile}, and MVP fixture LLM ${MacosComputerUseMvpGuidance.llmCanarySummaryFile}',
      'TCC and desktop action stay user-operated',
    ].join(' | ');
  }

  String _mvpUserOperatedCommandSummary() {
    return [
      'Manual TCC preview: ${MacosComputerUseMvpGuidance.manualTccHandoffCommand}',
      'Manual TCC: ${MacosComputerUseMvpGuidance.manualTccCommand}',
      'Desktop action: ${MacosComputerUseMvpGuidance.desktopActionCanaryCommand}',
      'macOS Spaces preview: ${MacosComputerUseMvpGuidance.spacesCanaryHandoffCommand}',
      'macOS Spaces: ${MacosComputerUseMvpGuidance.spacesCanaryCommand}',
    ].join(' | ');
  }

  String _auditPrivacyControlsSummary() {
    final controls = MacosComputerUseAuditLog.instance.privacyControls;
    final requiredEvents = controls['requiredEventTypes'];
    final redactedFields = controls['redactedFieldIds'];
    return [
      'M37 audit/privacy controls: ${controls['status']}',
      'Status: ${controls['status']}',
      'Local-only: ${controls['localOnly']}',
      'User-exportable: ${controls['userExportable']}',
      'Default export redacted: ${controls['defaultExportRedacted']}',
      'Explicit payload export required: ${controls['explicitPayloadExportRequired']}',
      if (requiredEvents is List) 'Events: ${requiredEvents.join(', ')}',
      if (redactedFields is List) 'Redacts: ${redactedFields.join(', ')}',
    ].join(' | ');
  }

  String _installMigrationGuardrailsSummary() {
    final guardrails = MacosComputerUseInstallMigrationGuardrails.fromState(
      helperStatus: _helperStatus,
      helperIpcRuntime: _helperIpcProtocol(),
    );
    final gate = guardrails['m38InstallMigrationGate'];
    final blockers = gate is Map ? gate['blockers'] : null;
    return [
      'M38 install/migration guardrails: ${guardrails['status']}',
      'TCC regrant required: ${guardrails['tccRegrantRequired']}',
      'Old helper action requests blocked: ${guardrails['oldHelperActionRequestsBlocked']}',
      if (blockers is List && blockers.isNotEmpty)
        'Blockers: ${blockers.join(', ')}',
      '${guardrails['nextAction']}',
    ].join(' | ');
  }

  String _mvpEvidencePreflightSummary() {
    return [
      'Required evidence: ${MacosComputerUseMvpGuidance.requiredEvidenceIds.join(', ')}',
      'User-operated: ${MacosComputerUseMvpGuidance.userOperatedEvidenceIds.join(', ')}',
      'LLM evidence: llm_canary',
      'Optional review evidence: m15_llm_review_canary, m16_approval_packet, m17_execution_rehearsal, m18_execution_handoff, m20_execution_result_intake, m22_post_action_review, m23_cycle_outcome_handoff, m25_next_cycle_seed_handoff, m26_observe_restart_packet, m27_screenshot_request_handoff, m28_screenshot_evidence_intake, m29_observe_canary_run_packet, m30_observe_result_intake, m36_live_llm_eval, m46_element_grounded_llm_eval, m47_real_app_observe_pilot, m48_user_operated_action_pilot, m49_privacy_audit_release_pack, m50_signed_beta_gate, m51_production_launch_gate, m52_product_release_rollout, m53_post_release_guardrails, m54_rollout_expansion_gate, m55_post_expansion_monitoring_gate, m56_rollout_decision_handoff_gate',
      'Report-only preflight: ${MacosComputerUseMvpGuidance.mvpReadinessPreflightCommand}',
      'Artifact index: ${MacosComputerUseMvpGuidance.artifactIndexCommand}',
      'M31 next-step navigator: ${MacosComputerUseMvpGuidance.nextStepNavigatorCommand}',
      'M33 release packaging: ${MacosComputerUseMvpGuidance.releasePackagingCommand}',
      'macOS Spaces canary handoff: ${MacosComputerUseMvpGuidance.spacesCanaryHandoffCommand}',
      'macOS Spaces canary command: ${MacosComputerUseMvpGuidance.spacesCanaryCommand}',
      _productionActionPolicySummary(),
      _auditPrivacyControlsSummary(),
      _installMigrationGuardrailsSummary(),
      'M15 LLM review command: ${MacosComputerUseMvpGuidance.m15LlmReviewCanaryCommand}',
      'M16 approval packet command: ${MacosComputerUseMvpGuidance.m16ApprovalPacketCommand}',
      'M17 execution rehearsal command: ${MacosComputerUseMvpGuidance.m17ExecutionRehearsalCommand}',
      'M18 execution handoff command: ${MacosComputerUseMvpGuidance.m18ExecutionHandoffCommand}',
      'M20 execution result intake command: ${MacosComputerUseMvpGuidance.m20ExecutionResultIntakeCommand}',
      'M22 post-action review command: ${MacosComputerUseMvpGuidance.m22PostActionReviewCommand}',
      'M30 observe result intake command: ${MacosComputerUseMvpGuidance.m30ObserveResultIntakeCommand}',
      'M36 Live LLM eval command: ${MacosComputerUseMvpGuidance.m36LiveLlmEvalCommand}',
      'M46 element-grounded LLM eval command: ${MacosComputerUseMvpGuidance.m46ElementGroundedLlmEvalCommand}',
      'M47 real-app observe pilot command: ${MacosComputerUseMvpGuidance.m47RealAppObservePilotCommand}',
      'M48 user-operated action pilot command: ${MacosComputerUseMvpGuidance.m48UserOperatedActionPilotCommand}',
      'M49 privacy and audit release pack command: ${MacosComputerUseMvpGuidance.m49PrivacyAuditReleasePackCommand}',
      'M50 signed beta gate command: ${MacosComputerUseMvpGuidance.m50SignedBetaGateCommand}',
      'M51 production launch gate command: ${MacosComputerUseMvpGuidance.m51ProductionLaunchGateCommand}',
      'M52 product release rollout command: ${MacosComputerUseMvpGuidance.m52ProductReleaseRolloutCommand}',
      'M53 post-release guardrails command: ${MacosComputerUseMvpGuidance.m53PostReleaseGuardrailsCommand}',
      'M54 rollout expansion gate command: ${MacosComputerUseMvpGuidance.m54RolloutExpansionGateCommand}',
      'M55 post-expansion monitoring gate command: ${MacosComputerUseMvpGuidance.m55PostExpansionMonitoringGateCommand}',
      'M56 rollout decision handoff gate command: ${MacosComputerUseMvpGuidance.m56RolloutDecisionHandoffGateCommand}',
      'M30 returns ready observe evidence to the M15 action proposal handoff; use the artifact index for exact M23-M29 restart commands.',
      'Final aggregation waits for all required evidence',
    ].join(' | ');
  }

  String _productionActionPolicySummary() {
    final policy = MacosComputerUseToolPolicy.productionActionPolicy();
    return [
      'M35 production action policy: ${policy.status}',
      'phases ${policy.phaseOrder.join(' > ')}',
      'public actions require separate approval: ${policy.publicActionSeparateApprovalRequired}',
      'emergency stop required: ${policy.emergencyStopRequired}',
      'post-action review required: ${policy.postActionReviewRequired}',
    ].join(' | ');
  }

  String _mvpMissingEvidenceChecklistSummary() {
    return MacosComputerUseMvpGuidance.requiredEvidenceIds
        .map(
          (artifactId) =>
              '$artifactId: ${MacosComputerUseMvpGuidance.missingArtifactNextAction(artifactId)}',
        )
        .join(' | ');
  }

  Map<String, String> _mvpArtifactPaths() {
    final liveReportPath = _lastLiveSmokeReport?['path'];
    return <String, String>{
      'mvpHandoff':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.mvpHandoffMarkdownFile}',
      'mvpReadinessJson':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.mvpReadinessJsonFile}',
      'mvpReadinessMarkdown':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.mvpReadinessMarkdownFile}',
      'manualTccSummary':
          'build/integration_test_reports/macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json',
      'desktopActionSummary':
          'build/integration_test_reports/macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json',
      'spacesCanarySummary':
          'build/integration_test_reports/macos_computer_use_spaces_canary_<timestamp>/${MacosComputerUseMvpGuidance.spacesCanarySummaryFile}',
      'llmCanarySummary':
          'build/integration_test_reports/macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json',
      'm15ActionProposalHandoff':
          'build/integration_test_reports/macos_computer_use_m15_action_proposal_handoff_<timestamp>/${MacosComputerUseMvpGuidance.m15ActionProposalHandoffFile}',
      'm15LlmReviewCanarySummary':
          'build/integration_test_reports/macos_computer_use_m15_llm_review_canary_<timestamp>/${MacosComputerUseMvpGuidance.m15LlmReviewCanarySummaryFile}',
      'm16ApprovalPacket':
          'build/integration_test_reports/macos_computer_use_m16_approval_packet_<timestamp>/${MacosComputerUseMvpGuidance.m16ApprovalPacketFile}',
      'm17ExecutionRehearsal':
          'build/integration_test_reports/macos_computer_use_m17_execution_rehearsal_<timestamp>/${MacosComputerUseMvpGuidance.m17ExecutionRehearsalFile}',
      'm18ExecutionHandoff':
          'build/integration_test_reports/macos_computer_use_m18_execution_handoff_<timestamp>/${MacosComputerUseMvpGuidance.m18ExecutionHandoffFile}',
      'm20ExecutionResultIntake':
          'build/integration_test_reports/macos_computer_use_m20_execution_result_intake_<timestamp>/${MacosComputerUseMvpGuidance.m20ExecutionResultIntakeFile}',
      'm22PostActionReview':
          'build/integration_test_reports/macos_computer_use_m22_post_action_review_<timestamp>/${MacosComputerUseMvpGuidance.m22PostActionReviewFile}',
      'm30ObserveResultIntake':
          'build/integration_test_reports/macos_computer_use_m30_observe_result_intake_<timestamp>/${MacosComputerUseMvpGuidance.m30ObserveResultIntakeFile}',
      'm36LiveLlmEvalSummary':
          'build/integration_test_reports/macos_computer_use_m36_live_llm_eval_<timestamp>/${MacosComputerUseMvpGuidance.m36LiveLlmEvalSummaryFile}',
      'm46ElementGroundedLlmEvalSummary':
          'build/integration_test_reports/macos_computer_use_m46_element_grounded_llm_eval_<timestamp>/${MacosComputerUseMvpGuidance.m46ElementGroundedLlmEvalSummaryFile}',
      'm47RealAppObservePilot':
          'build/integration_test_reports/macos_computer_use_m47_real_app_observe_pilot_<timestamp>/${MacosComputerUseMvpGuidance.m47RealAppObservePilotFile}',
      'm48UserOperatedActionPilot':
          'build/integration_test_reports/macos_computer_use_m48_user_operated_action_pilot_<timestamp>/${MacosComputerUseMvpGuidance.m48UserOperatedActionPilotFile}',
      'm49PrivacyAuditReleasePack':
          'build/integration_test_reports/macos_computer_use_m49_privacy_audit_release_pack_<timestamp>/${MacosComputerUseMvpGuidance.m49PrivacyAuditReleasePackFile}',
      'm50SignedBetaGate':
          'build/integration_test_reports/macos_computer_use_m50_signed_beta_gate_<timestamp>/${MacosComputerUseMvpGuidance.m50SignedBetaGateFile}',
      'm51ProductionLaunchGate':
          'build/integration_test_reports/macos_computer_use_m51_production_launch_gate_<timestamp>/${MacosComputerUseMvpGuidance.m51ProductionLaunchGateJsonFile}',
      'm52ProductReleaseRollout':
          'build/integration_test_reports/macos_computer_use_m52_product_release_rollout_<timestamp>/${MacosComputerUseMvpGuidance.m52ProductReleaseRolloutJsonFile}',
      'm53PostReleaseGuardrails':
          'build/integration_test_reports/macos_computer_use_m53_post_release_guardrails_<timestamp>/${MacosComputerUseMvpGuidance.m53PostReleaseGuardrailsJsonFile}',
      'm54RolloutExpansionGate':
          'build/integration_test_reports/macos_computer_use_m54_rollout_expansion_gate_<timestamp>/${MacosComputerUseMvpGuidance.m54RolloutExpansionGateJsonFile}',
      'm55PostExpansionMonitoringGate':
          'build/integration_test_reports/macos_computer_use_m55_post_expansion_monitoring_gate_<timestamp>/${MacosComputerUseMvpGuidance.m55PostExpansionMonitoringGateJsonFile}',
      'm56RolloutDecisionHandoffGate':
          'build/integration_test_reports/macos_computer_use_m56_rollout_decision_handoff_gate_<timestamp>/${MacosComputerUseMvpGuidance.m56RolloutDecisionHandoffGateJsonFile}',
      'artifactIndexJson':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.artifactIndexJsonFile}',
      'artifactIndexMarkdown':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.artifactIndexMarkdownFile}',
      'nextStepNavigatorJson':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.nextStepNavigatorJsonFile}',
      'nextStepNavigatorMarkdown':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.nextStepNavigatorMarkdownFile}',
      'automationSafeNextStepNavigatorJson':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.automationSafeNextStepNavigatorJsonFile}',
      'automationSafeNextStepNavigatorMarkdown':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.automationSafeNextStepNavigatorMarkdownFile}',
      'releasePackagingJson':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.releasePackagingJsonFile}',
      'releasePackagingMarkdown':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.releasePackagingMarkdownFile}',
      'releaseReadinessCiMarkdown':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.releaseReadinessCiMarkdownFile}',
      'releaseReadinessSignoffMarkdown':
          'build/integration_test_reports/${MacosComputerUseMvpGuidance.releaseReadinessSignoffMarkdownFile}',
      if (liveReportPath is String) 'latestLiveSmokeReport': liveReportPath,
    };
  }

  String _mvpArtifactPathSummary() {
    final paths = _mvpArtifactPaths();
    return [
      'MVP handoff: ${paths['mvpHandoff']}',
      'MVP readiness JSON (final sign-off output): ${paths['mvpReadinessJson']}',
      'MVP readiness Markdown (final sign-off output): ${paths['mvpReadinessMarkdown']}',
      'Manual TCC summary: ${paths['manualTccSummary']}',
      'Desktop action summary: ${paths['desktopActionSummary']}',
      'macOS Spaces summary: ${paths['spacesCanarySummary']}',
      'MVP fixture LLM summary: ${paths['llmCanarySummary']}',
      'M15 action proposal handoff: ${paths['m15ActionProposalHandoff']}',
      'M15 LLM review summary: ${paths['m15LlmReviewCanarySummary']}',
      'M16 approval packet: ${paths['m16ApprovalPacket']}',
      'M17 execution rehearsal: ${paths['m17ExecutionRehearsal']}',
      'M18 execution handoff: ${paths['m18ExecutionHandoff']}',
      'M20 execution result intake: ${paths['m20ExecutionResultIntake']}',
      'M22 post-action review: ${paths['m22PostActionReview']}',
      'M30 observe result intake: ${paths['m30ObserveResultIntake']}',
      'M36 Live LLM eval summary: ${paths['m36LiveLlmEvalSummary']}',
      'M46 element-grounded LLM eval summary: ${paths['m46ElementGroundedLlmEvalSummary']}',
      'M47 real-app observe pilot: ${paths['m47RealAppObservePilot']}',
      'M48 user-operated action pilot: ${paths['m48UserOperatedActionPilot']}',
      'M49 privacy and audit release pack: ${paths['m49PrivacyAuditReleasePack']}',
      'M50 signed beta gate: ${paths['m50SignedBetaGate']}',
      'M51 production launch gate: ${paths['m51ProductionLaunchGate']}',
      'M52 product release rollout: ${paths['m52ProductReleaseRollout']}',
      'M53 post-release guardrails: ${paths['m53PostReleaseGuardrails']}',
      'M54 rollout expansion gate: ${paths['m54RolloutExpansionGate']}',
      'M55 post-expansion monitoring gate: ${paths['m55PostExpansionMonitoringGate']}',
      'M56 rollout decision handoff gate: ${paths['m56RolloutDecisionHandoffGate']}',
      'M23-M29 restart artifact paths are listed by the artifact index when those optional reports exist',
      'Artifact index JSON: ${paths['artifactIndexJson']}',
      'Artifact index Markdown: ${paths['artifactIndexMarkdown']}',
      'Next-step navigator JSON: ${paths['nextStepNavigatorJson']}',
      'Next-step navigator Markdown: ${paths['nextStepNavigatorMarkdown']}',
      'Automation-safe next-step navigator JSON: ${paths['automationSafeNextStepNavigatorJson']}',
      'Automation-safe next-step navigator Markdown: ${paths['automationSafeNextStepNavigatorMarkdown']}',
      'Release packaging JSON: ${paths['releasePackagingJson']}',
      'Release packaging Markdown: ${paths['releasePackagingMarkdown']}',
      'Release readiness CI Markdown: ${paths['releaseReadinessCiMarkdown']}',
      'Release readiness sign-off Markdown: ${paths['releaseReadinessSignoffMarkdown']}',
      if (paths['latestLiveSmokeReport'] != null)
        'Latest live smoke: ${paths['latestLiveSmokeReport']}',
    ].join(' | ');
  }

  String _mvpPrReviewSummary() {
    return [
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      'CLI: ${MacosComputerUseMvpGuidance.artifactIndexCommand}',
    ].join(' | ');
  }

  String? _overlayCanarySummary() {
    final report = _reportBody(_lastLiveSmokeReport);
    if (report == null) {
      return null;
    }
    final overlaySmoke = report['overlaySmoke'];
    if (overlaySmoke is! Map) {
      return null;
    }
    final overlayMap = Map<String, dynamic>.from(overlaySmoke);
    final status = overlayMap['status'] as String? ?? 'unknown';
    final accessibility = _overlayEntrySummary(overlayMap['accessibility']);
    final screenRecording = _overlayEntrySummary(overlayMap['screenRecording']);
    final blockers = _stringList(overlayMap['blockers']);
    return [
      'status $status',
      if (accessibility != null) 'accessibility $accessibility',
      if (screenRecording != null) 'screenshots $screenRecording',
      if (blockers.isNotEmpty) 'blockers ${blockers.join(', ')}',
    ].join(' | ');
  }

  String? _overlayEntrySummary(Object? value) {
    if (value is! Map) {
      return null;
    }
    final entry = Map<String, dynamic>.from(value);
    final status = entry['status'] as String? ?? 'unknown';
    final foreground = entry['overlayForegroundPolicy'] as String? ?? 'missing';
    final floating = entry['overlayIsFloatingPanel'] == true;
    final hides = entry['overlayHidesOnDeactivate'] == true;
    return '$status, foreground $foreground, floating $floating, hides $hides';
  }

  List<Map<String, String>> _migratedCommands() {
    return const [
      {'command': 'ping', 'owner': 'helper'},
      {'command': 'permissionStatus', 'owner': 'helper'},
      {'command': 'openSettings', 'owner': 'helper'},
      {'command': 'showPermissionOverlay', 'owner': 'helper'},
      {'command': 'startOnboardingPermissionFlow', 'owner': 'helper'},
      {'command': 'stopAll', 'owner': 'helper'},
      {'command': 'screenshot', 'owner': 'helper'},
      {'command': 'listWindows', 'owner': 'helper'},
      {'command': 'focusWindow', 'owner': 'helper'},
      {'command': 'screenshotWindow', 'owner': 'helper'},
      {'command': 'moveMouse', 'owner': 'helper'},
      {'command': 'click', 'owner': 'helper'},
      {'command': 'drag', 'owner': 'helper'},
      {'command': 'scroll', 'owner': 'helper'},
      {'command': 'typeText', 'owner': 'helper'},
      {'command': 'pressKey', 'owner': 'helper'},
      {'command': 'startSystemAudioRecording', 'owner': 'helper'},
      {'command': 'stopSystemAudioRecording', 'owner': 'helper'},
    ];
  }

  Map<String, double?> _coordinateMap() {
    return {
      'x': double.tryParse(_xController.text.trim()),
      'y': double.tryParse(_yController.text.trim()),
    };
  }

  Map<String, dynamic>? _imageSummary(ComputerUseDebugImageSnapshot? snapshot) {
    if (snapshot == null) {
      return null;
    }
    return {
      'title': snapshot.title,
      'width': snapshot.width,
      'height': snapshot.height,
      'mimeType': snapshot.mimeType,
    };
  }

  String? get _coordinateTargetName {
    return switch (_coordinateTarget) {
      _CoordinateTarget.display => 'display',
      _CoordinateTarget.window => 'window',
      null => null,
    };
  }

  void _storePermissions(Map<String, dynamic> result) {
    final helper = result['helper'];
    if (helper is Map) {
      _storeHelperStatus(Map<String, dynamic>.from(helper));
    }
    final current = result['current'];
    if (current is Map) {
      _permissions = Map<String, dynamic>.from(current);
      return;
    }
    _permissions = result;
  }

  void _storeHelperStatus(Map<String, dynamic> result) {
    _helperStatus = {...?_helperStatus, ...result};
  }

  void _storeWindows(Map<String, dynamic> result) {
    final windows = result['windows'];
    if (windows is! List) {
      _windows = const [];
      _selectedWindowId = null;
      return;
    }

    final parsedWindows = windows
        .whereType<Map>()
        .map((window) => Map<String, dynamic>.from(window))
        .where((window) => _windowId(window) != null)
        .toList();
    _windows = parsedWindows;

    final selectedStillExists = parsedWindows.any(
      (window) => _windowId(window) == _selectedWindowId,
    );
    _selectedWindowId = selectedStillExists
        ? _selectedWindowId
        : parsedWindows.isEmpty
        ? null
        : _windowId(parsedWindows.first);
  }

  bool? _permissionValue(String key) {
    final value = _setupSnapshotMap?[key];
    return value is bool ? value : null;
  }

  Map<String, dynamic>? get _setupSnapshotMap {
    final snapshot = <String, dynamic>{};
    if (_permissions != null) {
      snapshot.addAll(_permissions!);
    }
    if (_helperStatus != null) {
      snapshot.addAll(_helperStatus!);
    }
    return snapshot.isEmpty ? null : snapshot;
  }

  MacosComputerUseSetupChecklist _setupChecklist(
    MacosComputerUseBackendInfo backend,
  ) {
    final snapshot = _setupSnapshotMap;
    return MacosComputerUseSetupChecklist(
      backend: backend,
      permissions: snapshot == null
          ? null
          : MacosComputerUsePermissionSnapshot.fromMap(snapshot),
    );
  }

  int _maxWidth() {
    final parsed = int.tryParse(_maxWidthController.text.trim());
    if (parsed == null || parsed <= 0) {
      return 1200;
    }
    return parsed;
  }

  _Coordinates? _coordinates() {
    final x = double.tryParse(_xController.text.trim());
    final y = double.tryParse(_yController.text.trim());
    if (x == null || y == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter numeric X and Y coordinates.')),
      );
      return null;
    }
    return _Coordinates(x, y);
  }

  Map<String, dynamic> _coordinateArguments(_Coordinates coordinates) {
    final arguments = <String, dynamic>{'x': coordinates.x, 'y': coordinates.y};

    switch (_coordinateTarget) {
      case _CoordinateTarget.window:
        final selectedWindowId = _selectedWindowId;
        final snapshot = _windowScreenshot;
        if (selectedWindowId == null || snapshot == null) {
          return arguments;
        }
        arguments['window_id'] = selectedWindowId;
        arguments['source_width'] = snapshot.width;
        arguments['source_height'] = snapshot.height;
      case _CoordinateTarget.display:
        final snapshot = _displayScreenshot;
        if (snapshot == null) {
          return arguments;
        }
        arguments['source_width'] = snapshot.width;
        arguments['source_height'] = snapshot.height;
      case null:
        break;
    }
    return arguments;
  }

  bool get _hasCoordinateTarget {
    return switch (_coordinateTarget) {
      _CoordinateTarget.window =>
        _selectedWindowId != null && _windowScreenshot != null,
      _CoordinateTarget.display => _displayScreenshot != null,
      null => false,
    };
  }

  String get _coordinateTargetLabel {
    return switch (_coordinateTarget) {
      _CoordinateTarget.window when _selectedWindowId != null =>
        'Active source: selected window screenshot',
      _CoordinateTarget.display => 'Active source: display screenshot',
      _ => 'Active source: none',
    };
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

  Object? _redactForDisplay(Object? value) {
    if (value is Map) {
      return value.map<String, Object?>((key, child) {
        final keyText = '$key';
        if (keyText.toLowerCase().contains('base64') && child is String) {
          return MapEntry(keyText, '<${child.length} base64 characters>');
        }
        return MapEntry(keyText, _redactForDisplay(child));
      });
    }
    if (value is List) {
      return value.map(_redactForDisplay).toList();
    }
    return value;
  }

  ComputerUseDebugImageSnapshot? _imageSnapshot(
    Map<String, dynamic> result,
    String fallbackTitle,
  ) {
    final imageBase64 = result['imageBase64'];
    if (imageBase64 is! String || imageBase64.isEmpty) {
      return null;
    }
    return ComputerUseDebugImageSnapshot(
      title: fallbackTitle,
      base64: imageBase64,
      width: _intValue(result['width']) ?? 0,
      height: _intValue(result['height']) ?? 0,
      mimeType: result['imageMimeType'] as String? ?? 'image/png',
    );
  }

  Map<String, dynamic>? _selectedWindow() {
    final selectedWindowId = _selectedWindowId;
    if (selectedWindowId == null) {
      return null;
    }
    for (final window in _windows) {
      if (_windowId(window) == selectedWindowId) {
        return window;
      }
    }
    return null;
  }

  int? _windowId(Map<String, dynamic> window) {
    return _intValue(window['windowId'] ?? window['window_id']);
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  String _windowTitle(Map<String, dynamic> result) {
    final appName = '${result['appName'] ?? 'Window'}'.trim();
    final title = '${result['title'] ?? ''}'.trim();
    if (title.isEmpty) {
      return appName;
    }
    return '$appName - $title';
  }

  String _windowLabel(Map<String, dynamic> window) {
    final id = _windowId(window);
    final appName = '${window['appName'] ?? 'Unknown App'}'.trim();
    final title = '${window['title'] ?? ''}'.trim();
    if (title.isEmpty) {
      return '$appName (#$id)';
    }
    return '$appName - $title (#$id)';
  }

  String _windowBoundsLabel(Map<String, dynamic> window) {
    final bounds = window['bounds'];
    if (bounds is! Map) {
      return 'Window bounds unavailable';
    }
    final x = _numberText(bounds['x']);
    final y = _numberText(bounds['y']);
    final width = _numberText(bounds['width']);
    final height = _numberText(bounds['height']);
    return 'Bounds: x=$x, y=$y, width=$width, height=$height';
  }

  String _numberText(Object? value) {
    if (value is int) {
      return '$value';
    }
    if (value is num) {
      return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);
    }
    return '?';
  }
}

class _Coordinates {
  const _Coordinates(this.x, this.y);

  final double x;
  final double y;
}

enum _CoordinateTarget { display, window }
