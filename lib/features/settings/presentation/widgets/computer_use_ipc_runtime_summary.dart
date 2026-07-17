import 'package:flutter/material.dart';

@immutable
class ComputerUseIpcRuntimeInfoRow {
  const ComputerUseIpcRuntimeInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

@immutable
class ComputerUseIpcRuntimeSummaryViewModel {
  ComputerUseIpcRuntimeSummaryViewModel({
    required this.status,
    required Iterable<ComputerUseIpcRuntimeInfoRow> rows,
  }) : rows = List.unmodifiable(rows);

  factory ComputerUseIpcRuntimeSummaryViewModel.fromRuntime(
    Map<String, dynamic> runtime,
  ) {
    return _IpcRuntimeSummaryMapper(runtime).build();
  }

  final String status;
  final List<ComputerUseIpcRuntimeInfoRow> rows;
}

class ComputerUseIpcRuntimeSummary extends StatelessWidget {
  const ComputerUseIpcRuntimeSummary({super.key, required this.viewModel});

  final ComputerUseIpcRuntimeSummaryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IPC runtime: ${viewModel.status}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final row in viewModel.rows) _IpcInfoChip(row: row)],
        ),
      ],
    );
  }
}

class _IpcInfoChip extends StatelessWidget {
  const _IpcInfoChip({required this.row});

  final ComputerUseIpcRuntimeInfoRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
      label: Text('${row.label}: ${row.value}'),
    );
  }
}

class _IpcRuntimeSummaryMapper {
  _IpcRuntimeSummaryMapper(this.runtime);

  final Map<String, dynamic> runtime;

  ComputerUseIpcRuntimeSummaryViewModel build() {
    final selected = '${runtime['selectedIpcTransport']}';
    final preferred = '${runtime['preferredIpcTransport']}';
    final fallback = '${runtime['fallbackIpcTransport']}';
    final preferredAttemptStatus = runtime['preferredAttemptStatus'];
    final preferredAttemptErrorCode = runtime['preferredAttemptErrorCode'];
    final helperOwnsUnsafeOsActions =
        runtime['helperOwnsUnsafeOsActions'] == true;
    final mainAppUnsafeOsActionsAllowed =
        runtime['mainAppUnsafeOsActionsAllowed'] == true;
    final mainAppOwnsTccPermissions =
        runtime['mainAppOwnsTccPermissions'] == true;
    final helperActsAsOsActionExecutor =
        runtime['helperActsAsOsActionExecutor'] == true;
    final tccPermissionOwnerDisplayName =
        _stringValue(runtime['tccPermissionOwnerDisplayName']) ?? 'unknown';
    final tccPermissionOwnerBundleIdentifier = _stringValue(
      runtime['tccPermissionOwnerBundleIdentifier'],
    );
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
    final overlayGrantTargetPaths = _uniqueStrings([
      _stringValue(accessibilityOverlay?['grantTargetBundlePath']),
      _stringValue(screenRecordingOverlay?['grantTargetBundlePath']),
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
    final installMigrationGuardrails = _mapValue(
      runtime['installMigrationGuardrails'],
    );
    final installMigrationGate = _mapValue(
      installMigrationGuardrails?['m38InstallMigrationGate'],
    );
    final migrationBlockers = _stringList(installMigrationGate?['blockers']);
    final migrationNextAction = _stringValue(
      installMigrationGuardrails?['nextAction'],
    );
    final migrationTccRegrantRequired =
        installMigrationGuardrails?['tccRegrantRequired'];
    final migrationOldHelperBlocked =
        installMigrationGuardrails?['oldHelperActionRequestsBlocked'];
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
    final rows = <ComputerUseIpcRuntimeInfoRow>[];

    void add(String label, String value) {
      rows.add(ComputerUseIpcRuntimeInfoRow(label: label, value: value));
    }

    add('Active IPC', selected);
    add('Preferred IPC', preferred);
    if (supportedCommands.isNotEmpty) {
      add('XPC commands', supportedCommands.join(', '));
    }
    add('XPC status', '${runtime['xpcStatus']}');
    add('XPC connection', '${runtime['xpcConnectionMode']}');
    add('XPC registration', '${runtime['xpcRegistrationRequirement']}');
    if (launchAgentStatus != null) {
      add('LaunchAgent', '$launchAgentStatus');
    }
    if (launchAgentPlistInstalled is bool) {
      add(
        'LaunchAgent plist',
        launchAgentPlistInstalled ? 'installed' : 'missing',
      );
    }
    add('XPC gate', productionReady ? 'ready' : 'blockers');
    add('Named XPC', namedServiceConnected ? 'connected' : 'fallback');
    if (productionBlockers.isNotEmpty) {
      add('XPC blockers', productionBlockers.join(', '));
    }
    if (signingDiagnostics != null) {
      add('Signing gate', signingLooksAccepted ? 'accepted' : 'blockers');
    }
    if (signingBlockers.isNotEmpty) {
      add('Signing blockers', signingBlockers.join(', '));
    }
    if (xpcRuntimeDiagnostics != null) {
      add('XPC runtime', xpcRuntimeBlockers.isEmpty ? 'ready' : 'blockers');
      add(
        'XPC listener',
        xpcListenerStarted
            ? 'started'
            : xpcListenerStartAttempted
            ? 'attempted'
            : 'not started',
      );
    }
    if (xpcRuntimeBlockers.isNotEmpty) {
      add('Runtime blockers', xpcRuntimeBlockers.join(', '));
    }
    if (helperDiagnosticsStale) {
      add(
        'Helper diagnostics',
        helperDiagnosticsStaleReasons.isEmpty
            ? 'stale'
            : 'stale: ${helperDiagnosticsStaleReasons.join(', ')}',
      );
    }
    if (runtime.containsKey('helperPathMatchesRunningHelper')) {
      add(
        'Helper path',
        helperPathMismatch
            ? 'mismatch'
            : helperPathMatchesRunning
            ? 'matched'
            : 'unknown',
      );
    }
    if (helperPathMismatch) {
      add(
        'Helper identity',
        preservedMismatchedHelperPath
            ? 'preserved running helper'
            : 'path mismatch',
      );
    }
    if (helperPathMismatch && tccOwnerHelperPath != null) {
      add('Runtime helper', _shortPath(tccOwnerHelperPath));
    }
    if (preservedMismatchedHelperPath) {
      add('Release sign-off', 'requires helper path match');
    }
    if (helperPathSignoffGate != null) {
      add('Helper path sign-off', '${helperPathSignoffGate['status']}');
    }
    if (helperRuntimeUseGate != null) {
      add('Helper runtime use', '${helperRuntimeUseGate['status']}');
    }
    if (installMigrationGuardrails != null) {
      add('M38 migration gate', '${installMigrationGuardrails['status']}');
    }
    if (migrationTccRegrantRequired is bool) {
      add(
        'TCC regrant',
        migrationTccRegrantRequired ? 'may be required' : 'no',
      );
    }
    if (migrationOldHelperBlocked is bool) {
      add(
        'Old helper actions',
        migrationOldHelperBlocked ? 'blocked' : 'not blocked',
      );
    }
    if (migrationBlockers.isNotEmpty) {
      add('M38 blockers', migrationBlockers.join(', '));
    }
    if (migrationNextAction != null) {
      add('M38 next action', migrationNextAction);
    }
    if (helperPathSignoffBlockers.isNotEmpty) {
      add('Helper path blockers', helperPathSignoffBlockers.join(', '));
    }
    if (helperPathSignoffNextAction != null) {
      add('Helper path sign-off next action', helperPathSignoffNextAction);
    }
    if (helperPathNextAction != null) {
      add('Helper path next action', helperPathNextAction);
    }
    if (helperRuntimeUseNextAction != null) {
      add('Helper runtime next action', helperRuntimeUseNextAction);
    }
    if (embeddedHelperPath != null) {
      add('Embedded helper', _shortPath(embeddedHelperPath));
    }
    if (runningHelperPath != null) {
      add('Running helper', _shortPath(runningHelperPath));
    }
    if (existingProbeOk is bool) {
      add('Existing probe', existingProbeOk ? 'passed' : 'failed');
    }
    if (existingProbePathMatch is bool) {
      add('Probe helper path', existingProbePathMatch ? 'matched' : 'mismatch');
    }
    if (existingProbeExpectedPath != null) {
      add('Probe expected helper', _shortPath(existingProbeExpectedPath));
    }
    if (existingProbeRunningPath != null) {
      add('Probe running helper', _shortPath(existingProbeRunningPath));
    }
    if (existingProbeFailedChecks.isNotEmpty) {
      add('Probe failed checks', existingProbeFailedChecks.join(', '));
    }
    if (permissionGate != null) {
      add('Permission gate', permissionBlockers.isEmpty ? 'clear' : 'blocked');
    }
    if (permissionBlockers.isNotEmpty) {
      add('Permission blockers', permissionBlockers.join(', '));
    }
    if (captureGate != null) {
      add('Capture gate', '${captureGate['status']}');
    }
    if (captureBlockers.isNotEmpty) {
      add('Capture blockers', captureBlockers.join(', '));
    }
    if (captureFailureClass != null && captureFailureClass != 'none') {
      add(
        'Capture failure',
        captureFailureClasses.isEmpty
            ? captureFailureClass
            : captureFailureClasses.join(', '),
      );
    }
    if (captureStepDiagnostics != null) {
      add(
        'Capture steps',
        [
          if (captureDisplayStatus != null) 'display=$captureDisplayStatus',
          if (captureWindowListStatus != null)
            'windows=$captureWindowListStatus',
          if (captureWindowStatus != null) 'window=$captureWindowStatus',
        ].join(', '),
      );
    }
    if (captureTccOwnerPath != null) {
      add('Capture TCC owner', _shortPath(captureTccOwnerPath));
    }
    if (inputGate != null) {
      add('Input gate', '${inputGate['status']}');
    }
    if (inputBlockers.isNotEmpty) {
      add('Input blockers', inputBlockers.join(', '));
    }
    if (audioGate != null) {
      add('Audio gate', '${audioGate['status']}');
    }
    if (audioBlockers.isNotEmpty) {
      add('Audio blockers', audioBlockers.join(', '));
    }
    if (overlaySmoke != null) {
      add('Overlay smoke', '${overlaySmoke['status']}');
    }
    if (overlayPlacements.isNotEmpty) {
      add('Overlay placement', overlayPlacements.join(', '));
    }
    if (overlayModes.isNotEmpty) {
      add('Overlay mode', overlayModes.join(', '));
    }
    if (overlayPasteboardTypes.isNotEmpty) {
      add('Overlay pasteboard', overlayPasteboardTypes.join(', '));
    }
    if (overlayGrantTargetPaths.isNotEmpty) {
      add('Overlay grant targets', overlayGrantTargetPaths.join(', '));
    }
    if (overlayBlockers.isNotEmpty) {
      add('Overlay blockers', overlayBlockers.join(', '));
    }
    if (unsafeActionGate != null) {
      add('Unsafe action gate', '${unsafeActionGate['status']}');
    }
    if (unsafeBlockers.isNotEmpty) {
      add('Unsafe blockers', unsafeBlockers.join(', '));
    }
    if (positiveSmokeGateSummary != null) {
      add('Positive smoke gate', '${positiveSmokeGateSummary['status']}');
    }
    if (positiveSmokeBlockers.isNotEmpty) {
      add('Positive smoke blockers', positiveSmokeBlockers.join(', '));
    }
    if (readinessExpectations != null) {
      add(
        'Readiness expectations',
        readinessExpectations['ok'] == true ? 'passed' : 'failed',
      );
    }
    if (m4SignoffGate != null) {
      add('M4 sign-off', '${m4SignoffGate['status']}');
    }
    if (m4SignoffBlockers.isNotEmpty) {
      add('M4 blockers', m4SignoffBlockers.join(', '));
    }
    if (m4SignoffHelperPath != null) {
      add('M4 helper', _shortPath(m4SignoffHelperPath));
    }
    if (m4SignoffNextAction != null) {
      add('M4 next action', m4SignoffNextAction);
    }
    if (failedExpectations.isNotEmpty) {
      add('Failed expectations', failedExpectations.join(', '));
    }
    add('XPC next action', '${runtime['xpcProductionNextAction']}');
    add(
      'TCC owner',
      mainAppOwnsTccPermissions ? tccPermissionOwnerDisplayName : 'helper',
    );
    if (tccPermissionOwnerBundleIdentifier != null) {
      add('TCC owner bundle', tccPermissionOwnerBundleIdentifier);
    }
    add('OS executor', helperActsAsOsActionExecutor ? 'helper' : 'main app');
    add('OS action owner', helperOwnsUnsafeOsActions ? 'helper' : 'main app');
    add(
      'Main app OS actions',
      mainAppUnsafeOsActionsAllowed ? 'allowed' : 'blocked',
    );
    if (preferredAttemptStatus is String) {
      add(
        'Preferred attempt',
        fallbackSummary is String ? fallbackSummary : preferredAttemptStatus,
      );
    }
    if (preferredAttemptErrorCode is String) {
      add('Preferred error', preferredAttemptErrorCode);
    }
    if (preferredAttemptElapsedMs is int) {
      add('Preferred elapsed', '${preferredAttemptElapsedMs}ms');
    }
    if (responseReceivedBeforeTimeout is bool) {
      add(
        'XPC response before timeout',
        responseReceivedBeforeTimeout ? 'yes' : 'no',
      );
    }
    if (responseReceivedAfterTimeout is bool) {
      add('XPC late response', responseReceivedAfterTimeout ? 'yes' : 'no');
    }
    if (lateResponseElapsedMs is int) {
      add('XPC late elapsed', '${lateResponseElapsedMs}ms');
    }
    if (fallbackReason is String) {
      add('Fallback reason', fallbackReason);
    }
    if (fallbackActive) {
      add(
        'Fallback outcome',
        fallbackSucceeded ? 'succeeded' : 'needs attention',
      );
    }
    add(
      'Next XPC parity',
      nextParityCommands.isEmpty ? 'none' : nextParityCommands.join(', '),
    );

    return ComputerUseIpcRuntimeSummaryViewModel(status: status, rows: rows);
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
