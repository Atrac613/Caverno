import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('describes the in-process compatibility backend', () {
    const backend = MacosComputerUseBackends.inProcessCompatibility;

    expect(backend.displayName, 'Caverno');
    expect(backend.permissionOwnerName, 'Caverno');
    expect(backend.targetHelperName, 'Caverno Computer Use');
    expect(backend.usesSeparateHelper, isFalse);
  });

  test('describes the helper IPC backend', () {
    const backend = MacosComputerUseBackends.helperIpc;

    expect(backend.displayName, 'Caverno Computer Use');
    expect(backend.permissionOwnerName, 'Caverno Computer Use');
    expect(backend.executionMode, 'helper_ipc');
    expect(backend.usesSeparateHelper, isTrue);
  });

  test('describes the current helper IPC transport', () {
    final info = MacosComputerUseIpc.current.toJson();

    expect(info['version'], 1);
    expect(info['transport'], 'xpc_service');
    expect(info['preferredTransport'], 'xpc_service');
    expect(info['fallbackTransport'], 'distributed_notification_center');
    expect(info['requestObject'], 'com.noguwo.apps.caverno');
    expect(info['responseObject'], 'com.noguwo.apps.caverno.computer-use');
    expect(
      info['requestNotificationName'],
      'com.caverno.computer_use.helper.request',
    );
    expect(
      info['responseNotificationName'],
      'com.caverno.computer_use.helper.response',
    );
    expect(info['requestEnvelope'], contains('senderProcessIdentifier'));
    expect(info['responseEnvelope'], contains('response'));
    expect(info['timeoutsMs'], containsPair('xpcPreferredFallback', 3000));
    expect(info['timeoutsMs'], containsPair('xpcWarmup', 1000));
    expect(info['timeoutsMs'], containsPair('stopAll', 8000));
    expect(info['errorCodes'], contains('helper_unreachable'));
    expect(info['errorCodes'], contains('helper_xpc_timeout'));
    expect(info['xpcServiceName'], 'com.noguwo.apps.caverno.computer-use.xpc');
    expect(info['xpcSupportedCommands'], [
      'ping',
      'showMainWindow',
      'permissionStatus',
      'openSettings',
      'showPermissionOverlay',
      'startOnboardingPermissionFlow',
      'stopAll',
      'screenshot',
      'listDisplays',
      'listWindows',
      'accessibilitySnapshot',
      'focusWindow',
      'screenshotWindow',
      'moveMouse',
      'click',
      'drag',
      'scroll',
      'typeText',
      'pressKey',
      'startSystemAudioRecording',
      'stopSystemAudioRecording',
    ]);
    expect(info['xpcReady'], isTrue);
    expect(info['xpcProductionReady'], isTrue);
    expect(info['xpcStatus'], 'production');
    expect(info['xpcConnectionMode'], 'external_helper_mach_service');
    expect(
      info['xpcLaunchAgentPlistName'],
      'com.noguwo.apps.caverno.computer-use.plist',
    );
    expect(
      info['xpcLaunchAgentRelativePath'],
      'Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist',
    );
    expect(
      info['xpcRegistrationRequirement'],
      'launchd_mach_service_registration',
    );
    expect(info['xpcProductionBlockers'], isEmpty);
    expect(info['xpcProductionNextAction'], 'XPC is production ready.');
    expect(info['mainAppUnsafeOsActionsAllowed'], isFalse);
    expect(info['helperOwnsUnsafeOsActions'], isTrue);
    expect(info['helperOwnedActionCategories'], contains('input_events'));
    expect(
      info['helperOwnedActionCategories'],
      contains('system_audio_recording'),
    );
    expect(info['xpcNextParityCommands'], isEmpty);
    expect(
      info['xpcProductionReadinessCriteria'],
      contains(
        'ping_show_main_window_permission_status_open_settings_show_permission_overlay_start_onboarding_permission_flow_stop_all_screenshot_list_displays_list_windows_accessibility_snapshot_focus_window_screenshot_window_move_mouse_click_drag_scroll_type_text_press_key_system_audio_match_dnc',
      ),
    );
  });

  test('documents MVP PR review consistency guidance', () {
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M15 action-proposal review evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M15 LLM review evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M16 approval packet evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M17 execution rehearsal evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M18 execution handoff evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M20 execution result intake evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M22 post-action review evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M36 Live LLM evaluation evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M46 element-grounded LLM evaluation evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M47 real-app observe pilot evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M48 user-operated action pilot evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M49 privacy and audit release-pack evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M50 signed beta evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M51 production launch evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M52 product release rollout evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M53 post-release guardrail evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M54 rollout expansion evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M55 post-expansion monitoring evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M56 rollout decision handoff evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M39 beta sign-off evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('blocked M40 production launch evidence'),
    );
    expect(
      MacosComputerUseMvpGuidance.prReviewSummaryGuidance,
      contains('M15 review/gate consistency'),
    );
    expect(
      MacosComputerUseMvpGuidance.m15LlmReviewCanaryCommand,
      contains('run_macos_computer_use_m15_llm_review_canary.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m16ApprovalPacketCommand,
      contains('run_macos_computer_use_m16_approval_packet.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m17ExecutionRehearsalCommand,
      contains('run_macos_computer_use_m17_execution_rehearsal.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m18ExecutionHandoffCommand,
      contains('run_macos_computer_use_m18_execution_handoff.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m20ExecutionResultIntakeCommand,
      contains('run_macos_computer_use_m20_execution_result_intake.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m22PostActionReviewCommand,
      contains('run_macos_computer_use_m22_post_action_review.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m36LiveLlmEvalCommand,
      contains('run_macos_computer_use_m36_live_llm_eval.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m46ElementGroundedLlmEvalCommand,
      contains('run_macos_computer_use_m46_element_grounded_llm_eval.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m47RealAppObservePilotCommand,
      contains('run_macos_computer_use_m47_real_app_observe_pilot.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m48UserOperatedActionPilotCommand,
      contains('run_macos_computer_use_m48_user_operated_action_pilot.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m48UserOperatedActionPilotCommand,
      contains('--safe-target-confirmed yes'),
    );
    expect(
      MacosComputerUseMvpGuidance.m49PrivacyAuditReleasePackCommand,
      contains('run_macos_computer_use_m49_privacy_audit_release_pack.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m49PrivacyAuditReleasePackCommand,
      contains('--explicit-payload-export-approved not-requested'),
    );
    expect(
      MacosComputerUseMvpGuidance.m50SignedBetaGateCommand,
      contains('run_macos_computer_use_m50_signed_beta_gate.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m50SignedBetaGateCommand,
      contains('--m49-privacy-audit-release-pack'),
    );
    expect(
      MacosComputerUseMvpGuidance.m51ProductionLaunchGateCommand,
      contains('run_macos_computer_use_m51_production_launch_gate.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m51ProductionLaunchGateCommand,
      contains('--m50-signed-beta-gate'),
    );
    expect(
      MacosComputerUseMvpGuidance.m52ProductReleaseRolloutCommand,
      contains('run_macos_computer_use_m52_product_release_rollout.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m52ProductReleaseRolloutCommand,
      contains('--m51-production-launch-gate'),
    );
    expect(
      MacosComputerUseMvpGuidance.m53PostReleaseGuardrailsCommand,
      contains('run_macos_computer_use_m53_post_release_guardrails.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m53PostReleaseGuardrailsCommand,
      contains('--m52-product-release-rollout'),
    );
    expect(
      MacosComputerUseMvpGuidance.m54RolloutExpansionGateCommand,
      contains('run_macos_computer_use_m54_rollout_expansion_gate.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m54RolloutExpansionGateCommand,
      contains('--m53-post-release-guardrails'),
    );
    expect(
      MacosComputerUseMvpGuidance.m55PostExpansionMonitoringGateCommand,
      contains('run_macos_computer_use_m55_post_expansion_monitoring_gate.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m55PostExpansionMonitoringGateCommand,
      contains('--m54-rollout-expansion-gate'),
    );
    expect(
      MacosComputerUseMvpGuidance.m56RolloutDecisionHandoffGateCommand,
      contains('run_macos_computer_use_m56_rollout_decision_handoff_gate.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m56RolloutDecisionHandoffGateCommand,
      contains('--rollout-decision-handoff-checklist'),
    );
    expect(
      MacosComputerUseMvpGuidance.m56RolloutDecisionHandoffGateCommand,
      contains('--m55-post-expansion-monitoring-gate'),
    );
    expect(
      MacosComputerUseMvpGuidance.m39BetaSignoffCommand,
      contains('run_macos_computer_use_m39_beta_signoff.sh'),
    );
    expect(
      MacosComputerUseMvpGuidance.m40ProductionLaunchGateCommand,
      contains('run_macos_computer_use_m40_production_launch_gate.sh'),
    );
  });

  test('builds the onboarding diagnostics schema', () {
    const checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.helperIpc,
      permissions: MacosComputerUsePermissionSnapshot(
        helperReachable: true,
        accessibilityGranted: true,
        screenCaptureGranted: false,
        systemAudioRecordingSupported: true,
      ),
    );
    final diagnostics = MacosComputerUseOnboardingDiagnostics(
      generatedAt: DateTime.utc(2026, 4, 25, 12),
      setupChecklist: checklist,
      onboardingSmokeChecklist: const [
        {'id': 'launch_helper', 'label': 'Launch helper', 'complete': true},
      ],
      helperIpcProtocol: MacosComputerUseIpc.current.toJson(),
      onboardingVerification: const {
        'ok': false,
        'steps': [
          {'id': 'permissions', 'ok': true},
          {'id': 'display_screenshot', 'ok': true},
          {'id': 'window_capture', 'ok': false},
        ],
      },
      helperStatus: const {'helperRunning': true},
      helperStatusPersistence: const {
        'updatedAt': '2026-04-25T12:00:30Z',
        'activeWork': {'systemAudioRecording': false},
      },
      permissionRecoverySummary: const {
        'status': 'needs_recovery',
        'issueIds': ['missing_permissions'],
      },
      productionActionPolicy: const {
        'status': 'defined',
        'phaseOrder': ['observe', 'approval_packet'],
      },
      auditPrivacyControls: const {
        'schemaName': 'macos_computer_use_audit_privacy_controls',
        'm37AuditPrivacyGate': {'status': 'ready'},
      },
      installMigrationGuardrails: const {
        'schemaName': 'macos_computer_use_install_migration_guardrails',
        'm38InstallMigrationGate': {'status': 'ready'},
      },
      permissions: const {'accessibilityGranted': true},
      manualSmokeSteps: const [
        {'id': 'capture_display', 'ok': true},
      ],
      migratedCommands: const [
        {'command': 'ping', 'owner': 'helper'},
      ],
      lastLiveSmokeReport: const {
        'ok': true,
        'path': '/tmp/caverno-macos-computer-use-smoke.json',
        'report': {'coreOk': true, 'captureOk': false},
      },
      lastAction: 'Run smoke sequence',
    ).toJson();

    expect(
      diagnostics['schemaName'],
      MacosComputerUseOnboardingDiagnostics.schemaName,
    );
    expect(
      diagnostics['schemaVersion'],
      MacosComputerUseOnboardingDiagnostics.schemaVersion,
    );
    expect(diagnostics['generatedAt'], '2026-04-25T12:00:00.000Z');
    expect(diagnostics['setupChecklist'], isA<Map<String, dynamic>>());
    expect(diagnostics['onboardingVerification'], containsPair('ok', false));
    expect(
      diagnostics['permissionRecoverySummary'],
      containsPair('status', 'needs_recovery'),
    );
    expect(
      diagnostics['productionActionPolicy'],
      containsPair('status', 'defined'),
    );
    expect(diagnostics['helperStatusPersistence'], contains('activeWork'));
    expect(diagnostics['helperIpcProtocol'], containsPair('xpcReady', true));
    expect(
      diagnostics['helperIpcProtocol'],
      containsPair('xpcStatus', 'production'),
    );
    expect(
      diagnostics['helperIpcProtocol'],
      containsPair('mainAppUnsafeOsActionsAllowed', false),
    );
    expect(
      diagnostics['helperIpcProtocol'],
      containsPair('helperOwnsUnsafeOsActions', true),
    );
    final helperIpcProtocol =
        diagnostics['helperIpcProtocol'] as Map<String, dynamic>;
    expect(helperIpcProtocol['xpcNextParityCommands'], isEmpty);
    expect(
      diagnostics['operationBoundary'],
      MacosComputerUseOperationBoundary.values,
    );
    expect(diagnostics['auditLog'], isA<List<Map<String, dynamic>>>());
    expect(
      diagnostics['auditPrivacyControls'],
      containsPair('schemaName', 'macos_computer_use_audit_privacy_controls'),
    );
    expect(
      diagnostics['installMigrationGuardrails'],
      containsPair(
        'schemaName',
        'macos_computer_use_install_migration_guardrails',
      ),
    );
    expect(diagnostics['manualSmokeSteps'], isA<List<Map<String, dynamic>>>());
    expect(diagnostics['migratedCommands'], isA<List<Map<String, String>>>());
    expect(diagnostics['lastLiveSmokeReport'], containsPair('ok', true));
  });

  test('classifies revoked helper permissions as recovery issues', () {
    final summary = MacosComputerUsePermissionRecoverySummary.fromState(
      backend: MacosComputerUseBackends.helperIpc,
      permissions: const MacosComputerUsePermissionSnapshot(
        helperReachable: true,
        accessibilityGranted: false,
        screenCaptureGranted: false,
        systemAudioRecordingSupported: true,
      ),
      onboardingVerification: const {
        'permissions': {
          'accessibilityGranted': true,
          'screenCaptureGranted': true,
        },
      },
    );

    expect(summary.isReady, isFalse);
    expect(summary.issueIds, contains('revoked_permissions'));
    expect(summary.missingPermissionLabels, isEmpty);
    expect(summary.revokedPermissionLabels, [
      'Accessibility',
      'Screen & System Audio Recording',
    ]);
    expect(summary.mainAppPermissionPromptsBlocked, isTrue);
    expect(
      summary.nextAction,
      'Ask the user to re-enable Caverno Computer Use in System Settings, then recheck permissions.',
    );
  });

  test('classifies stale helper path mismatches before permission prompts', () {
    final summary = MacosComputerUsePermissionRecoverySummary.fromState(
      backend: MacosComputerUseBackends.helperIpc,
      permissions: const MacosComputerUsePermissionSnapshot(
        helperReachable: true,
        accessibilityGranted: true,
        screenCaptureGranted: true,
        systemAudioRecordingSupported: true,
      ),
      helperStatus: const {
        'helperSharedDiagnosticsStale': true,
        'helperSharedDiagnosticsStaleReasons': ['helper_bundle_path_mismatch'],
        'embeddedHelperPath':
            '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
        'runningHelperPath':
            '/Users/noguwo/Documents/Workspace/Flutter/caverno/build/macos/Build/Products/Debug/Caverno Computer Use.app',
        'helperPathMatchesRunningHelper': false,
      },
    );

    expect(summary.issueIds, contains('stale_helper_diagnostics'));
    expect(summary.issueIds, contains('debug_release_helper_mismatch'));
    expect(summary.helperPathMismatch, isTrue);
    expect(summary.debugReleaseHelperMismatch, isTrue);
    expect(
      summary.nextAction,
      'Restart Caverno Computer Use from Caverno, then recheck helper reachability before sign-off.',
    );
  });

  test('builds M38 install and migration guardrails', () {
    final ready = MacosComputerUseInstallMigrationGuardrails.fromState(
      helperStatus: const {
        'embeddedHelperPath':
            '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
        'runningHelperPath':
            '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
        'helperPathMatchesRunningHelper': true,
        'oldHelperActionRequestsBlocked': true,
      },
    );

    expect(
      ready['schemaName'],
      'macos_computer_use_install_migration_guardrails',
    );
    expect(ready['milestone'], 'M38');
    expect(ready['status'], 'ready');
    expect(ready['tccRegrantRequired'], isFalse);
    expect(ready['oldHelperActionRequestsBlocked'], isTrue);

    final blocked = MacosComputerUseInstallMigrationGuardrails.fromState(
      helperStatus: const {
        'embeddedHelperPath':
            '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
        'runningHelperPath':
            '/Users/noguwo/Documents/Workspace/Flutter/caverno/build/macos/Build/Products/Debug/Caverno Computer Use.app',
        'helperPathMatchesRunningHelper': false,
        'helperPathMismatch': true,
        'helperSharedDiagnosticsStaleReasons': ['helper_bundle_path_mismatch'],
      },
    );

    expect(blocked['status'], 'blocked');
    expect(blocked['tccRegrantRequired'], isTrue);
    expect(
      blocked['tccRegrantReason'],
      contains('TCC grants are tied to the helper app identity'),
    );
    final gate = blocked['m38InstallMigrationGate'] as Map<String, dynamic>;
    expect(gate['blockers'], contains('helper_path_mismatch'));
    expect(gate['blockers'], contains('stale_helper_diagnostics'));
  });

  test('reports missing permissions before a snapshot is loaded', () {
    const checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.inProcessCompatibility,
      permissions: null,
    );

    expect(checklist.hasSnapshot, isFalse);
    expect(checklist.isReady, isFalse);
    expect(checklist.missingPermissionLabels, [
      'Accessibility',
      'Screen & System Audio Recording',
    ]);
    expect(checklist.title, 'Refresh permissions before running smoke checks');
  });

  test('reports helper reachability before permission labels', () {
    final permissions = MacosComputerUsePermissionSnapshot.fromMap({
      'ok': false,
      'backend': 'helper',
      'helperReachable': false,
      'code': 'helper_unreachable',
    });
    final checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.helperIpc,
      permissions: permissions,
    );

    expect(checklist.isReady, isFalse);
    expect(checklist.missingPermissionLabels, ['Caverno Computer Use']);
    expect(
      checklist.subtitle,
      'Launch Caverno Computer Use, then refresh permissions.',
    );
  });

  test('builds action copy for a partial permission snapshot', () {
    final permissions = MacosComputerUsePermissionSnapshot.fromMap({
      'accessibilityGranted': true,
      'screenCaptureGranted': false,
      'systemAudioRecordingSupported': true,
    });
    final checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.inProcessCompatibility,
      permissions: permissions,
    );

    expect(checklist.hasSnapshot, isTrue);
    expect(checklist.isReady, isFalse);
    expect(checklist.missingPermissionLabels, [
      'Screen & System Audio Recording',
    ]);
    expect(
      checklist.subtitle,
      'Open System Settings, grant Caverno, then refresh permissions.',
    );
  });

  test('marks the setup ready when required permissions are granted', () {
    final permissions = MacosComputerUsePermissionSnapshot.fromMap({
      'accessibilityGranted': true,
      'screenCaptureGranted': true,
      'systemAudioRecordingSupported': false,
    });
    final checklist = MacosComputerUseSetupChecklist(
      backend: MacosComputerUseBackends.inProcessCompatibility,
      permissions: permissions,
    );

    expect(checklist.isReady, isTrue);
    expect(checklist.missingPermissionLabels, isEmpty);
    expect(checklist.title, 'Ready for visual, input, and audio smoke checks');
  });
}
