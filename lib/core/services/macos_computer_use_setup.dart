class MacosComputerUseBackendInfo {
  const MacosComputerUseBackendInfo({
    required this.displayName,
    required this.bundleIdentifier,
    required this.executionMode,
    required this.permissionOwnerName,
    required this.targetHelperName,
    required this.targetHelperBundleIdentifier,
    required this.usesSeparateHelper,
  });

  final String displayName;
  final String bundleIdentifier;
  final String executionMode;
  final String permissionOwnerName;
  final String targetHelperName;
  final String targetHelperBundleIdentifier;
  final bool usesSeparateHelper;

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'bundleIdentifier': bundleIdentifier,
      'executionMode': executionMode,
      'permissionOwnerName': permissionOwnerName,
      'targetHelperName': targetHelperName,
      'targetHelperBundleIdentifier': targetHelperBundleIdentifier,
      'usesSeparateHelper': usesSeparateHelper,
    };
  }
}

class MacosComputerUseOperationBoundary {
  const MacosComputerUseOperationBoundary._();

  static const values = <String, Object?>{
    'tccGrants': 'user_operated',
    'desktopActions': 'user_operated',
    'inputSmokeRequiresArming': true,
    'systemAudioSmokeRequiresArming': true,
  };
}

class MacosComputerUseMvpGuidance {
  const MacosComputerUseMvpGuidance._();

  static const requiredEvidenceIds = <String>[
    'release_artifact',
    'canary_history',
    'manual_tcc',
    'desktop_action_canary',
    'llm_canary',
  ];
  static const userOperatedEvidenceIds = <String>[
    'manual_tcc',
    'desktop_action_canary',
  ];

  static const manualTccCommand =
      'bash tool/run_macos_computer_use_manual_tcc_signoff.sh';
  static const desktopActionCanaryCommand =
      'bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target';
  static const llmCanaryCommand =
      'bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh';
  static const realAppObserveCanaryCommand =
      'bash tool/run_macos_computer_use_real_app_observe_canary.sh';
  static const m15LlmReviewCanaryCommand =
      'bash tool/run_macos_computer_use_m15_llm_review_canary.sh --handoff <action_proposal_handoff.json>';
  static const mvpSignoffCommand =
      'bash tool/run_macos_computer_use_mvp_signoff.sh';
  static const mvpReadinessPreflightCommand =
      'bash tool/run_macos_computer_use_mvp_readiness_preflight.sh';
  static const artifactIndexCommand =
      'dart run tool/macos_computer_use_readiness_artifact_index.dart --root build/integration_test_reports';
  static const manualTccSummaryFile = 'manual_tcc_report_summary.json';
  static const desktopActionSummaryFile = 'canary_summary.json';
  static const llmCanarySummaryFile = 'canary_summary.json';
  static const m15LlmReviewCanarySummaryFile = 'canary_summary.json';
  static const artifactIndexJsonFile =
      'macos_computer_use_readiness_artifact_index.json';
  static const artifactIndexMarkdownFile =
      'macos_computer_use_readiness_artifact_index.md';
  static const releaseReadinessCiMarkdownFile =
      'macos_computer_use_release_readiness_ci.md';
  static const releaseReadinessSignoffMarkdownFile =
      'macos_computer_use_release_readiness_signoff.md';
  static const mvpReadinessJsonFile = 'macos_computer_use_mvp_readiness.json';
  static const mvpReadinessMarkdownFile = 'macos_computer_use_mvp_readiness.md';
  static const mvpHandoffMarkdownFile = 'macos_computer_use_mvp_handoff.md';
  static const m15ActionProposalHandoffFile = 'action_proposal_handoff.json';
  static const prReviewSummarySection = 'PR Review Summary';
  static const llmCanarySummaryPlaceholder = '<llm-canary-summary.json>';
  static const manualTccSummaryPlaceholder =
      '<manual-tcc-report-or-summary.json>';
  static const desktopActionSummaryPlaceholder =
      '<desktop-action-canary-summary.json>';

  static const manualTccNextAction =
      'Ask the user to run `$manualTccCommand` and provide `$manualTccSummaryFile`.';
  static const desktopActionCanaryNextAction =
      'Ask the user to run `$desktopActionCanaryCommand` and provide `$desktopActionSummaryFile`.';
  static const llmCanaryNextAction =
      'Run `$llmCanaryCommand`, run `$realAppObserveCanaryCommand` with a user-provided screenshot, or provide a Computer Use LLM canary `$llmCanarySummaryFile` before final sign-off aggregation.';
  static const releaseArtifactNextAction =
      'Refresh safe release inputs with `bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-safe-inputs`.';
  static const canaryHistoryNextAction =
      'Run the automation-safe Computer Use canary or safe readiness refresh to produce `macos_computer_use_canary_history.json`.';
  static const finalAggregationCommand =
      '$mvpSignoffCommand --final-signoff --manual-tcc-report $manualTccSummaryPlaceholder --desktop-action-canary-summary $desktopActionSummaryPlaceholder --llm-canary-summary $llmCanarySummaryPlaceholder';
  static const prReviewSummaryGuidance =
      'Review `$prReviewSummarySection` in `$mvpHandoffMarkdownFile`, `$artifactIndexMarkdownFile`, `$releaseReadinessCiMarkdownFile`, and `$releaseReadinessSignoffMarkdownFile` before PR review. '
      'After final sign-off aggregation, inspect `$mvpReadinessJsonFile` and `$mvpReadinessMarkdownFile`. '
      'It separates ready artifacts, missing evidence, user-operated blockers, automation-safe blockers, blocked M15 action-proposal review evidence, blocked M15 LLM review evidence, and M15 review/gate consistency.';

  static String missingArtifactNextAction(String artifactId) {
    switch (artifactId) {
      case 'release_artifact':
        return releaseArtifactNextAction;
      case 'canary_history':
        return canaryHistoryNextAction;
      case 'manual_tcc':
        return manualTccNextAction;
      case 'desktop_action_canary':
        return desktopActionCanaryNextAction;
      case 'llm_canary':
        return llmCanaryNextAction;
      default:
        return 'Provide the missing `$artifactId` artifact before final sign-off aggregation.';
    }
  }
}

class MacosComputerUseBackends {
  const MacosComputerUseBackends._();

  static const mainAppDisplayName = 'Caverno';
  static const mainAppBundleIdentifier = 'com.noguwo.apps.caverno';
  static const helperDisplayName = 'Caverno Computer Use';
  static const helperBundleIdentifier = 'com.noguwo.apps.caverno.computer-use';

  static const inProcessCompatibility = MacosComputerUseBackendInfo(
    displayName: mainAppDisplayName,
    bundleIdentifier: mainAppBundleIdentifier,
    executionMode: 'in_process_compatibility',
    permissionOwnerName: mainAppDisplayName,
    targetHelperName: helperDisplayName,
    targetHelperBundleIdentifier: helperBundleIdentifier,
    usesSeparateHelper: false,
  );

  static const helperIpc = MacosComputerUseBackendInfo(
    displayName: helperDisplayName,
    bundleIdentifier: helperBundleIdentifier,
    executionMode: 'helper_ipc',
    permissionOwnerName: helperDisplayName,
    targetHelperName: helperDisplayName,
    targetHelperBundleIdentifier: helperBundleIdentifier,
    usesSeparateHelper: true,
  );
}

class MacosComputerUseIpcInfo {
  const MacosComputerUseIpcInfo({
    required this.version,
    required this.transport,
    required this.preferredTransport,
    required this.fallbackTransport,
    required this.requestObject,
    required this.responseObject,
    required this.requestNotificationName,
    required this.responseNotificationName,
    required this.requestEnvelope,
    required this.responseEnvelope,
    required this.timeoutsMs,
    required this.errorCodes,
    required this.xpcServiceName,
    required this.xpcSupportedCommands,
    required this.xpcReady,
    required this.xpcProductionReady,
    required this.xpcStatus,
    required this.xpcConnectionMode,
    required this.xpcLaunchAgentPlistName,
    required this.xpcLaunchAgentRelativePath,
    required this.xpcRegistrationRequirement,
    required this.xpcProductionBlockers,
    required this.xpcProductionNextAction,
    required this.mainAppUnsafeOsActionsAllowed,
    required this.helperOwnsUnsafeOsActions,
    required this.helperOwnedActionCategories,
    required this.xpcNextParityCommands,
    required this.xpcProductionReadinessCriteria,
  });

  final int version;
  final String transport;
  final String preferredTransport;
  final String fallbackTransport;
  final String requestObject;
  final String responseObject;
  final String requestNotificationName;
  final String responseNotificationName;
  final List<String> requestEnvelope;
  final List<String> responseEnvelope;
  final Map<String, int> timeoutsMs;
  final List<String> errorCodes;
  final String xpcServiceName;
  final List<String> xpcSupportedCommands;
  final bool xpcReady;
  final bool xpcProductionReady;
  final String xpcStatus;
  final String xpcConnectionMode;
  final String xpcLaunchAgentPlistName;
  final String xpcLaunchAgentRelativePath;
  final String xpcRegistrationRequirement;
  final List<String> xpcProductionBlockers;
  final String xpcProductionNextAction;
  final bool mainAppUnsafeOsActionsAllowed;
  final bool helperOwnsUnsafeOsActions;
  final List<String> helperOwnedActionCategories;
  final List<String> xpcNextParityCommands;
  final List<String> xpcProductionReadinessCriteria;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'transport': transport,
      'preferredTransport': preferredTransport,
      'fallbackTransport': fallbackTransport,
      'requestObject': requestObject,
      'responseObject': responseObject,
      'requestNotificationName': requestNotificationName,
      'responseNotificationName': responseNotificationName,
      'requestEnvelope': requestEnvelope,
      'responseEnvelope': responseEnvelope,
      'timeoutsMs': timeoutsMs,
      'errorCodes': errorCodes,
      'xpcServiceName': xpcServiceName,
      'xpcSupportedCommands': xpcSupportedCommands,
      'xpcReady': xpcReady,
      'xpcProductionReady': xpcProductionReady,
      'xpcStatus': xpcStatus,
      'xpcConnectionMode': xpcConnectionMode,
      'xpcLaunchAgentPlistName': xpcLaunchAgentPlistName,
      'xpcLaunchAgentRelativePath': xpcLaunchAgentRelativePath,
      'xpcRegistrationRequirement': xpcRegistrationRequirement,
      'xpcProductionBlockers': xpcProductionBlockers,
      'xpcProductionNextAction': xpcProductionNextAction,
      'mainAppUnsafeOsActionsAllowed': mainAppUnsafeOsActionsAllowed,
      'helperOwnsUnsafeOsActions': helperOwnsUnsafeOsActions,
      'helperOwnedActionCategories': helperOwnedActionCategories,
      'xpcNextParityCommands': xpcNextParityCommands,
      'xpcProductionReadinessCriteria': xpcProductionReadinessCriteria,
    };
  }
}

class MacosComputerUseIpc {
  const MacosComputerUseIpc._();

  static const protocolVersion = 1;
  static const transport = 'xpc_service';
  static const preferredTransport = transport;
  static const fallbackTransport = 'distributed_notification_center';
  static const xpcServiceName = 'com.noguwo.apps.caverno.computer-use.xpc';
  static const xpcSupportedCommands = [
    'ping',
    'showMainWindow',
    'permissionStatus',
    'openSettings',
    'showPermissionOverlay',
    'startOnboardingPermissionFlow',
    'stopAll',
    'screenshot',
    'listWindows',
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
  ];
  static const xpcProductionReady = true;
  static const xpcStatus = 'production';
  static const xpcConnectionMode = 'external_helper_mach_service';
  static const xpcLaunchAgentPlistName =
      'com.noguwo.apps.caverno.computer-use.plist';
  static const xpcLaunchAgentRelativePath =
      'Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist';
  static const xpcRegistrationRequirement = 'launchd_mach_service_registration';
  static const xpcProductionBlockers = <String>[];
  static const xpcProductionNextAction = 'XPC is production ready.';
  static const mainAppUnsafeOsActionsAllowed = false;
  static const helperOwnsUnsafeOsActions = true;
  static const helperOwnedActionCategories = [
    'accessibility',
    'screen_capture',
    'input_events',
    'system_audio_recording',
    'emergency_stop',
  ];
  static const xpcNextParityCommands = <String>[];
  static const xpcProductionReadinessCriteria = [
    'named_service_connects_from_signed_main_app',
    'ping_show_main_window_permission_status_open_settings_show_permission_overlay_start_onboarding_permission_flow_stop_all_screenshot_list_windows_focus_window_screenshot_window_move_mouse_click_drag_scroll_type_text_press_key_system_audio_match_dnc',
    'capture_input_audio_commands_have_parity_smoke_coverage',
    'fallback_path_is_observable_and_non_destructive',
  ];
  static const requestNotificationName =
      'com.caverno.computer_use.helper.request';
  static const responseNotificationName =
      'com.caverno.computer_use.helper.response';
  static const requestEnvelope = [
    'protocolVersion',
    'requestId',
    'command',
    'senderBundleIdentifier',
    'senderProcessIdentifier',
    'arguments',
  ];
  static const responseEnvelope = [
    'protocolVersion',
    'requestId',
    'command',
    'response',
  ];
  static const timeoutsMs = {
    'default': 1500,
    'xpcPreferredFallback': 3000,
    'xpcWarmup': 1000,
    'focusWindow': 3000,
    'screenshot': 8000,
    'screenshotWindow': 8000,
    'input': 3000,
    'drag': 6000,
    'typeText': 5000,
    'systemAudioRecording': 8000,
    'stopAll': 8000,
  };
  static const errorCodes = [
    'helper_unreachable',
    'helper_xpc_unavailable',
    'helper_xpc_timeout',
    'helper_unsupported_protocol',
    'helper_response_mismatch',
    'helper_invalid_response',
    'invalid_request',
    'unsupported_protocol',
    'untrusted_sender',
  ];

  static const current = MacosComputerUseIpcInfo(
    version: protocolVersion,
    transport: transport,
    preferredTransport: preferredTransport,
    fallbackTransport: fallbackTransport,
    requestObject: MacosComputerUseBackends.mainAppBundleIdentifier,
    responseObject: MacosComputerUseBackends.helperBundleIdentifier,
    requestNotificationName: requestNotificationName,
    responseNotificationName: responseNotificationName,
    requestEnvelope: requestEnvelope,
    responseEnvelope: responseEnvelope,
    timeoutsMs: timeoutsMs,
    errorCodes: errorCodes,
    xpcServiceName: xpcServiceName,
    xpcSupportedCommands: xpcSupportedCommands,
    xpcReady: true,
    xpcProductionReady: xpcProductionReady,
    xpcStatus: xpcStatus,
    xpcConnectionMode: xpcConnectionMode,
    xpcLaunchAgentPlistName: xpcLaunchAgentPlistName,
    xpcLaunchAgentRelativePath: xpcLaunchAgentRelativePath,
    xpcRegistrationRequirement: xpcRegistrationRequirement,
    xpcProductionBlockers: xpcProductionBlockers,
    xpcProductionNextAction: xpcProductionNextAction,
    mainAppUnsafeOsActionsAllowed: mainAppUnsafeOsActionsAllowed,
    helperOwnsUnsafeOsActions: helperOwnsUnsafeOsActions,
    helperOwnedActionCategories: helperOwnedActionCategories,
    xpcNextParityCommands: xpcNextParityCommands,
    xpcProductionReadinessCriteria: xpcProductionReadinessCriteria,
  );
}

class MacosComputerUseOnboardingDiagnostics {
  const MacosComputerUseOnboardingDiagnostics({
    required this.generatedAt,
    required this.setupChecklist,
    required this.onboardingSmokeChecklist,
    required this.helperIpcProtocol,
    this.operationBoundary = MacosComputerUseOperationBoundary.values,
    this.helperIpcRuntime,
    this.onboardingVerification,
    this.helperStatus,
    this.helperStatusPersistence,
    this.permissions,
    this.audioRecording,
    this.inputActionsArmed,
    this.inputSmokeCompleted,
    this.audioSmokeCompleted,
    this.audioRecordingArmed,
    this.manualSmokeRunning,
    this.manualSmokeSteps = const [],
    this.migratedCommands = const [],
    this.selectedWindowId,
    this.selectedWindow,
    this.windowCount,
    this.coordinateTarget,
    this.coordinates,
    this.displayScreenshot,
    this.windowScreenshot,
    this.lastAction,
    this.lastResult,
    this.auditLog = const [],
    this.lastLiveSmokeReport,
    this.lastExistingHelperProbeReport,
    this.lastDiagnosticExportPath,
  });

  static const schemaName = 'macos_computer_use_onboarding';
  static const schemaVersion = 1;

  final DateTime generatedAt;
  final MacosComputerUseSetupChecklist setupChecklist;
  final List<Map<String, dynamic>> onboardingSmokeChecklist;
  final Map<String, dynamic> helperIpcProtocol;
  final Map<String, Object?> operationBoundary;
  final Map<String, dynamic>? helperIpcRuntime;
  final Map<String, dynamic>? onboardingVerification;
  final Map<String, dynamic>? helperStatus;
  final Map<String, dynamic>? helperStatusPersistence;
  final Map<String, dynamic>? permissions;
  final bool? audioRecording;
  final bool? inputActionsArmed;
  final bool? inputSmokeCompleted;
  final bool? audioSmokeCompleted;
  final bool? audioRecordingArmed;
  final bool? manualSmokeRunning;
  final List<Map<String, dynamic>> manualSmokeSteps;
  final List<Map<String, String>> migratedCommands;
  final int? selectedWindowId;
  final Map<String, dynamic>? selectedWindow;
  final int? windowCount;
  final String? coordinateTarget;
  final Map<String, double?>? coordinates;
  final Map<String, dynamic>? displayScreenshot;
  final Map<String, dynamic>? windowScreenshot;
  final String? lastAction;
  final Object? lastResult;
  final List<Map<String, dynamic>> auditLog;
  final Map<String, dynamic>? lastLiveSmokeReport;
  final Map<String, dynamic>? lastExistingHelperProbeReport;
  final String? lastDiagnosticExportPath;

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'setupChecklist': setupChecklist.toJson(),
      'onboardingSmokeChecklist': onboardingSmokeChecklist,
      'operationBoundary': operationBoundary,
      'onboardingVerification': onboardingVerification,
      'helperStatus': helperStatus,
      'helperStatusPersistence': helperStatusPersistence,
      'permissions': permissions,
      'helperIpcRuntime': helperIpcRuntime,
      'audioRecording': audioRecording,
      'inputActionsArmed': inputActionsArmed,
      'inputSmokeCompleted': inputSmokeCompleted,
      'audioSmokeCompleted': audioSmokeCompleted,
      'audioRecordingArmed': audioRecordingArmed,
      'manualSmokeRunning': manualSmokeRunning,
      'manualSmokeSteps': manualSmokeSteps,
      'helperIpcProtocol': helperIpcProtocol,
      'migratedCommands': migratedCommands,
      'selectedWindowId': selectedWindowId,
      'selectedWindow': selectedWindow,
      'windowCount': windowCount,
      'coordinateTarget': coordinateTarget,
      'coordinates': coordinates,
      'displayScreenshot': displayScreenshot,
      'windowScreenshot': windowScreenshot,
      'lastAction': lastAction,
      'lastResult': lastResult,
      'auditLog': auditLog,
      'lastLiveSmokeReport': lastLiveSmokeReport,
      'lastExistingHelperProbeReport': lastExistingHelperProbeReport,
      if (lastDiagnosticExportPath != null)
        'lastDiagnosticExportPath': lastDiagnosticExportPath,
    };
  }
}

class MacosComputerUsePermissionSnapshot {
  const MacosComputerUsePermissionSnapshot({
    required this.helperReachable,
    required this.accessibilityGranted,
    required this.screenCaptureGranted,
    required this.systemAudioRecordingSupported,
  });

  factory MacosComputerUsePermissionSnapshot.fromMap(
    Map<String, dynamic>? values,
  ) {
    final helperReachable = values?['helperReachable'];
    return MacosComputerUsePermissionSnapshot(
      helperReachable: helperReachable is bool
          ? helperReachable
          : values?['backend'] == 'helper'
          ? true
          : null,
      accessibilityGranted: _boolValue(values?['accessibilityGranted']),
      screenCaptureGranted: _boolValue(values?['screenCaptureGranted']),
      systemAudioRecordingSupported: _boolValue(
        values?['systemAudioRecordingSupported'],
      ),
    );
  }

  final bool? helperReachable;
  final bool? accessibilityGranted;
  final bool? screenCaptureGranted;
  final bool? systemAudioRecordingSupported;

  bool get hasRequiredPermissions =>
      helperReachable != false &&
      accessibilityGranted == true &&
      screenCaptureGranted == true;

  List<String> get missingPermissionLabels {
    if (helperReachable == false) {
      return ['Caverno Computer Use'];
    }
    return [
      if (accessibilityGranted != true) 'Accessibility',
      if (screenCaptureGranted != true) 'Screen & System Audio Recording',
    ];
  }

  Map<String, dynamic> toJson() {
    return {
      'helperReachable': helperReachable,
      'accessibilityGranted': accessibilityGranted,
      'screenCaptureGranted': screenCaptureGranted,
      'systemAudioRecordingSupported': systemAudioRecordingSupported,
    };
  }

  static bool? _boolValue(Object? value) {
    return value is bool ? value : null;
  }
}

class MacosComputerUseSetupChecklist {
  const MacosComputerUseSetupChecklist({
    required this.backend,
    required this.permissions,
  });

  final MacosComputerUseBackendInfo backend;
  final MacosComputerUsePermissionSnapshot? permissions;

  bool get hasSnapshot => permissions != null;

  bool get isReady => hasSnapshot && permissions!.hasRequiredPermissions;

  List<String> get missingPermissionLabels {
    return permissions?.missingPermissionLabels ??
        const ['Accessibility', 'Screen & System Audio Recording'];
  }

  String get title {
    if (isReady) {
      return 'Ready for visual, input, and audio smoke checks';
    }
    if (hasSnapshot) {
      return 'Action required: ${missingPermissionLabels.join(', ')}';
    }
    return 'Refresh permissions before running smoke checks';
  }

  String get subtitle {
    if (permissions?.helperReachable == false) {
      return 'Launch ${backend.permissionOwnerName}, then refresh permissions.';
    }
    if (isReady) {
      return 'Run screenshots first, then arm input or audio checks only when needed.';
    }
    if (hasSnapshot) {
      return 'Open System Settings, grant ${backend.permissionOwnerName}, then refresh permissions.';
    }
    return 'Use Refresh to load the current macOS privacy state.';
  }

  Map<String, dynamic> toJson() {
    return {
      'backend': backend.toJson(),
      'hasSnapshot': hasSnapshot,
      'isReady': isReady,
      'missingPermissionLabels': missingPermissionLabels,
      'permissions': permissions?.toJson(),
    };
  }
}
