import 'dart:collection';

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
  static const manualTccHandoffCommand = '$manualTccCommand --handoff-only';
  static const desktopActionCanaryCommand =
      'bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target';
  static const desktopActionCanaryHandoffCommand =
      '$desktopActionCanaryCommand --handoff-only';
  static const spacesCanaryCommand =
      'bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window --switch-space-next --release-helper-signoff';
  static const spacesCanaryHandoffCommand =
      '$spacesCanaryCommand --handoff-only';
  static const llmCanaryCommand =
      'bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh';
  static const realAppObserveCanaryCommand =
      'bash tool/run_macos_computer_use_real_app_observe_canary.sh';
  static const m15LlmReviewCanaryCommand =
      'bash tool/run_macos_computer_use_m15_llm_review_canary.sh --handoff <action_proposal_handoff.json>';
  static const m16ApprovalPacketCommand =
      'bash tool/run_macos_computer_use_m16_approval_packet.sh --m15-handoff <action_proposal_handoff.json> --m15-llm-review <canary_summary.json>';
  static const m17ExecutionRehearsalCommand =
      'bash tool/run_macos_computer_use_m17_execution_rehearsal.sh --m16-packet <approval_packet.json>';
  static const m18ExecutionHandoffCommand =
      'bash tool/run_macos_computer_use_m18_execution_handoff.sh --m17-rehearsal <execution_rehearsal.json>';
  static const m20ExecutionResultIntakeCommand =
      'bash tool/run_macos_computer_use_m20_execution_result_intake.sh --m18-handoff <execution_handoff.json> --fresh-observation done --target-confirmed yes --exact-text-confirmed yes --public-action-confirmed <yes-or-not-applicable> --runtime-action succeeded --post-action-observation done';
  static const m22PostActionReviewCommand =
      'bash tool/run_macos_computer_use_m22_post_action_review.sh --m20-intake <execution_result_intake.json> --result-reviewed yes --post-action-state <stable-or-needs-follow-up> --follow-up-required <yes-or-no>';
  static const m23CycleOutcomeHandoffCommand =
      'bash tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh --m22-review <post_action_review.json> --outcome-accepted yes --next-observe-needed <yes-or-no>';
  static const m25NextCycleSeedHandoffCommand =
      'bash tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh --m23-handoff <cycle_outcome_handoff.json> --seed-accepted yes';
  static const m26ObserveRestartPacketCommand =
      'bash tool/run_macos_computer_use_m26_observe_restart_packet.sh --m25-handoff <next_cycle_seed_handoff.json> --target-app <target-app>';
  static const m27ScreenshotRequestHandoffCommand =
      'bash tool/run_macos_computer_use_m27_screenshot_request_handoff.sh --m26-packet <observe_restart_packet.json>';
  static const m28ScreenshotEvidenceIntakeCommand =
      'bash tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh --m27-handoff <screenshot_request_handoff.json> --screenshot <user-provided-real-app-screenshot.png>';
  static const m29ObserveCanaryRunPacketCommand =
      'bash tool/run_macos_computer_use_m29_observe_canary_run_packet.sh --m28-intake <screenshot_evidence_intake.json>';
  static const m30ObserveResultIntakeCommand =
      'bash tool/run_macos_computer_use_m30_observe_result_intake.sh --m29-packet <observe_canary_run_packet.json> --m14-summary <canary_summary.json>';
  static const m36LiveLlmEvalCommand =
      'bash tool/run_macos_computer_use_m36_live_llm_eval.sh --fixture-screenshot <mvp-fixture-screenshot.png> --real-app-screenshot <user-provided-real-app-screenshot.png>';
  static const m46ElementGroundedLlmEvalCommand =
      'bash tool/run_macos_computer_use_m46_element_grounded_llm_eval.sh --fixture-screenshot <mvp-fixture-screenshot.png> --real-app-screenshot <user-provided-real-app-screenshot.png>';
  static const m47RealAppObservePilotCommand =
      'bash tool/run_macos_computer_use_m47_real_app_observe_pilot.sh --m14-summary <canary_summary.json>';
  static const m48UserOperatedActionPilotCommand =
      'bash tool/run_macos_computer_use_m48_user_operated_action_pilot.sh --m47-pilot <real_app_observe_pilot.json> --fresh-observation done --target-confirmed yes --exact-text-confirmed yes --public-action-confirmed <yes-or-not-applicable> --runtime-action succeeded --post-action-observation done --result-reviewed yes --post-action-state stable --follow-up-required no --outcome-accepted yes --next-observe-needed no --safe-target-confirmed yes';
  static const m49PrivacyAuditReleasePackCommand =
      'bash tool/run_macos_computer_use_m49_privacy_audit_release_pack.sh --m48-pilot <user_operated_action_pilot.json> --diagnostics <redacted-computer-use-diagnostics.json> --redacted-export-reviewed yes --privacy-copy-reviewed yes --support-diagnostics-reviewed yes --explicit-payload-export-policy-reviewed yes --payload-export-requested no --explicit-payload-export-approved not-requested';
  static const m50SignedBetaGateCommand =
      'bash tool/run_macos_computer_use_m50_signed_beta_gate.sh --signed-beta-checklist <m50-signed-beta-checklist.json> --release-artifact-report <release-artifact-signoff.json> --release-packaging-report <macos_computer_use_release_packaging.json> --m46-element-grounded-llm-eval <canary_summary.json> --m48-user-operated-action-pilot <user_operated_action_pilot.json> --m49-privacy-audit-release-pack <privacy_audit_release_pack.json>';
  static const m51ProductionLaunchGateCommand =
      'bash tool/run_macos_computer_use_m51_production_launch_gate.sh --launch-checklist <m51-launch-checklist.json> --release-artifact-report <release-artifact-signoff.json> --release-packaging-report <macos_computer_use_release_packaging.json> --manual-tcc-report <manual-tcc-summary.json> --m46-element-grounded-llm-eval <canary_summary.json> --m49-privacy-audit-release-pack <privacy_audit_release_pack.json> --m50-signed-beta-gate <macos_computer_use_m50_signed_beta_gate.json> --diagnostics <computer-use-diagnostics.json>';
  static const m52ProductReleaseRolloutCommand =
      'bash tool/run_macos_computer_use_m52_product_release_rollout.sh --product-release-checklist <m52-product-release-checklist.json> --m51-production-launch-gate <macos_computer_use_m51_production_launch_gate.json>';
  static const m53PostReleaseGuardrailsCommand =
      'bash tool/run_macos_computer_use_m53_post_release_guardrails.sh --post-release-checklist <m53-post-release-checklist.json> --m52-product-release-rollout <macos_computer_use_m52_product_release_rollout.json>';
  static const m54RolloutExpansionGateCommand =
      'bash tool/run_macos_computer_use_m54_rollout_expansion_gate.sh --rollout-expansion-checklist <m54-rollout-expansion-checklist.json> --m53-post-release-guardrails <macos_computer_use_m53_post_release_guardrails.json>';
  static const m55PostExpansionMonitoringGateCommand =
      'bash tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh --post-expansion-monitoring-checklist <m55-post-expansion-monitoring-checklist.json> --m54-rollout-expansion-gate <macos_computer_use_m54_rollout_expansion_gate.json>';
  static const m56RolloutDecisionHandoffGateCommand =
      'bash tool/run_macos_computer_use_m56_rollout_decision_handoff_gate.sh --rollout-decision-handoff-checklist <m56-rollout-decision-handoff-checklist.json> --m55-post-expansion-monitoring-gate <macos_computer_use_m55_post_expansion_monitoring_gate.json>';
  static const m39BetaSignoffCommand =
      'bash tool/run_macos_computer_use_m39_beta_signoff.sh --manual-beta-checklist <m39-manual-beta-checklist.json> --m36-live-llm-eval <canary_summary.json> --m23-cycle-outcome <cycle_outcome_handoff.json>';
  static const m40ProductionLaunchGateCommand =
      'bash tool/run_macos_computer_use_m40_production_launch_gate.sh --launch-checklist <m40-launch-checklist.json> --release-artifact-report <release-artifact-signoff.json> --release-packaging-report <macos_computer_use_release_packaging.json> --m36-live-llm-eval <canary_summary.json> --m39-beta-signoff <macos_computer_use_m39_beta_signoff.json> --diagnostics <computer-use-diagnostics.json>';
  static const mvpSignoffCommand =
      'bash tool/run_macos_computer_use_mvp_signoff.sh';
  static const mvpReadinessPreflightCommand =
      'bash tool/run_macos_computer_use_mvp_readiness_preflight.sh';
  static const artifactIndexCommand =
      'dart run tool/macos_computer_use_readiness_artifact_index.dart --root build/integration_test_reports';
  static const nextStepNavigatorCommand =
      'dart run tool/macos_computer_use_next_step_navigator.dart --root build/integration_test_reports';
  static const releasePackagingCommand =
      'bash tool/run_macos_computer_use_release_packaging.sh';
  static const releaseSigningPreflightCommand =
      'bash tool/run_macos_computer_use_release_signing_preflight.sh';
  static const manualTccSummaryFile = 'manual_tcc_report_summary.json';
  static const desktopActionSummaryFile = 'canary_summary.json';
  static const spacesCanarySummaryFile = 'canary_summary.json';
  static const llmCanarySummaryFile = 'canary_summary.json';
  static const m15LlmReviewCanarySummaryFile = 'canary_summary.json';
  static const m16ApprovalPacketFile = 'approval_packet.json';
  static const m17ExecutionRehearsalFile = 'execution_rehearsal.json';
  static const m18ExecutionHandoffFile = 'execution_handoff.json';
  static const m20ExecutionResultIntakeFile = 'execution_result_intake.json';
  static const m22PostActionReviewFile = 'post_action_review.json';
  static const m23CycleOutcomeHandoffFile = 'cycle_outcome_handoff.json';
  static const m25NextCycleSeedHandoffFile = 'next_cycle_seed_handoff.json';
  static const m26ObserveRestartPacketFile = 'observe_restart_packet.json';
  static const m27ScreenshotRequestHandoffFile =
      'screenshot_request_handoff.json';
  static const m28ScreenshotEvidenceIntakeFile =
      'screenshot_evidence_intake.json';
  static const m29ObserveCanaryRunPacketFile = 'observe_canary_run_packet.json';
  static const m30ObserveResultIntakeFile = 'observe_result_intake.json';
  static const m36LiveLlmEvalSummaryFile = 'canary_summary.json';
  static const m46ElementGroundedLlmEvalSummaryFile = 'canary_summary.json';
  static const m47RealAppObservePilotFile = 'real_app_observe_pilot.json';
  static const m48UserOperatedActionPilotFile =
      'user_operated_action_pilot.json';
  static const m49PrivacyAuditReleasePackFile =
      'privacy_audit_release_pack.json';
  static const m50SignedBetaGateFile =
      'macos_computer_use_m50_signed_beta_gate.json';
  static const m51ProductionLaunchGateJsonFile =
      'macos_computer_use_m51_production_launch_gate.json';
  static const m51ProductionLaunchGateMarkdownFile =
      'macos_computer_use_m51_production_launch_gate.md';
  static const m52ProductReleaseRolloutJsonFile =
      'macos_computer_use_m52_product_release_rollout.json';
  static const m52ProductReleaseRolloutMarkdownFile =
      'macos_computer_use_m52_product_release_rollout.md';
  static const m53PostReleaseGuardrailsJsonFile =
      'macos_computer_use_m53_post_release_guardrails.json';
  static const m53PostReleaseGuardrailsMarkdownFile =
      'macos_computer_use_m53_post_release_guardrails.md';
  static const m54RolloutExpansionGateJsonFile =
      'macos_computer_use_m54_rollout_expansion_gate.json';
  static const m54RolloutExpansionGateMarkdownFile =
      'macos_computer_use_m54_rollout_expansion_gate.md';
  static const m55PostExpansionMonitoringGateJsonFile =
      'macos_computer_use_m55_post_expansion_monitoring_gate.json';
  static const m55PostExpansionMonitoringGateMarkdownFile =
      'macos_computer_use_m55_post_expansion_monitoring_gate.md';
  static const m56RolloutDecisionHandoffGateJsonFile =
      'macos_computer_use_m56_rollout_decision_handoff_gate.json';
  static const m56RolloutDecisionHandoffGateMarkdownFile =
      'macos_computer_use_m56_rollout_decision_handoff_gate.md';
  static const m39BetaSignoffJsonFile =
      'macos_computer_use_m39_beta_signoff.json';
  static const m39BetaSignoffMarkdownFile =
      'macos_computer_use_m39_beta_signoff.md';
  static const m40ProductionLaunchGateJsonFile =
      'macos_computer_use_m40_production_launch_gate.json';
  static const m40ProductionLaunchGateMarkdownFile =
      'macos_computer_use_m40_production_launch_gate.md';
  static const artifactIndexJsonFile =
      'macos_computer_use_readiness_artifact_index.json';
  static const artifactIndexMarkdownFile =
      'macos_computer_use_readiness_artifact_index.md';
  static const nextStepNavigatorJsonFile =
      'macos_computer_use_next_step_navigator.json';
  static const nextStepNavigatorMarkdownFile =
      'macos_computer_use_next_step_navigator.md';
  static const automationSafeNextStepNavigatorJsonFile =
      'macos_computer_use_next_step_navigator_automation_safe.json';
  static const automationSafeNextStepNavigatorMarkdownFile =
      'macos_computer_use_next_step_navigator_automation_safe.md';
  static const releasePackagingJsonFile =
      'macos_computer_use_release_packaging.json';
  static const releasePackagingMarkdownFile =
      'macos_computer_use_release_packaging.md';
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
      'Run `$manualTccHandoffCommand` first to print the split permission targets without running M8. Ask the user to run `$manualTccCommand` and provide `$manualTccSummaryFile`.';
  static const desktopActionCanaryNextAction =
      'Run `$desktopActionCanaryHandoffCommand` first to print the safe target checklist without running the desktop action. Ask the user to run `$desktopActionCanaryCommand` after preparing the safe target and provide `$desktopActionSummaryFile`.';
  static const spacesCanaryNextAction =
      'Run `$spacesCanaryHandoffCommand` first to print the Spaces setup checklist without switching Spaces. Ask the user to prepare two macOS Spaces with a harmless inactive-Space window, run `$spacesCanaryCommand`, and provide `canary_summary.json`.';
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
      'It separates ready artifacts, missing evidence, user-operated blockers, automation-safe blockers, blocked M15 action-proposal review evidence, blocked M15 LLM review evidence, blocked M16 approval packet evidence, blocked M17 execution rehearsal evidence, blocked M18 execution handoff evidence, blocked M20 execution result intake evidence, blocked M22 post-action review evidence, blocked M23 cycle outcome evidence, blocked M25 next-cycle seed evidence, blocked M26 observe restart evidence, blocked M27 screenshot request evidence, blocked M28 screenshot evidence intake, blocked M29 observe run packet evidence, blocked M30 observe result intake evidence, blocked M36 Live LLM evaluation evidence, blocked M46 element-grounded LLM evaluation evidence, blocked M47 real-app observe pilot evidence, blocked M48 user-operated action pilot evidence, blocked M49 privacy and audit release-pack evidence, blocked M50 signed beta evidence, blocked M51 production launch evidence, blocked M52 product release rollout evidence, blocked M53 post-release guardrail evidence, blocked M54 rollout expansion evidence, blocked M55 post-expansion monitoring evidence, blocked M56 rollout decision handoff evidence, blocked M39 beta sign-off evidence, blocked M40 production launch evidence, and M15 review/gate consistency.';

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

String _macosComputerUseGrantInstruction({
  required String accessibilityOwnerName,
  required List<String> permissionLabels,
}) {
  final labels = <String>[
    if (permissionLabels.contains('Accessibility')) 'Accessibility',
    if (permissionLabels.contains('Screen & System Audio Recording'))
      'Screen & System Audio Recording',
  ];
  if (labels.isEmpty) {
    return 'the missing macOS permissions';
  }
  final joined = labels.length == 1
      ? labels.single
      : '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
  return '$joined to $accessibilityOwnerName';
}

String _macosComputerUseReenableInstruction({
  required String accessibilityOwnerName,
  required List<String> permissionLabels,
}) {
  final labels = <String>[
    if (permissionLabels.contains('Accessibility')) 'Accessibility',
    if (permissionLabels.contains('Screen & System Audio Recording'))
      'Screen & System Audio Recording',
  ];
  if (labels.isEmpty) {
    return 'the disabled macOS permissions';
  }
  final joined = labels.length == 1
      ? labels.single
      : '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
  return '$joined for $accessibilityOwnerName';
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
    required this.mainAppOwnsTccPermissions,
    required this.tccPermissionOwnerBundleIdentifier,
    required this.tccPermissionOwnerDisplayName,
    required this.helperActsAsOsActionExecutor,
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
  final bool mainAppOwnsTccPermissions;
  final String tccPermissionOwnerBundleIdentifier;
  final String tccPermissionOwnerDisplayName;
  final bool helperActsAsOsActionExecutor;
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
      'mainAppOwnsTccPermissions': mainAppOwnsTccPermissions,
      'tccPermissionOwnerBundleIdentifier': tccPermissionOwnerBundleIdentifier,
      'tccPermissionOwnerDisplayName': tccPermissionOwnerDisplayName,
      'helperActsAsOsActionExecutor': helperActsAsOsActionExecutor,
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
  static const mainAppOwnsTccPermissions = false;
  static const tccPermissionOwnerBundleIdentifier =
      MacosComputerUseBackends.helperBundleIdentifier;
  static const tccPermissionOwnerDisplayName =
      MacosComputerUseBackends.helperDisplayName;
  static const helperActsAsOsActionExecutor = true;
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
    'ping_show_main_window_permission_status_open_settings_show_permission_overlay_start_onboarding_permission_flow_stop_all_screenshot_list_displays_list_windows_accessibility_snapshot_focus_window_screenshot_window_move_mouse_click_drag_scroll_type_text_press_key_system_audio_match_dnc',
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
    mainAppOwnsTccPermissions: mainAppOwnsTccPermissions,
    tccPermissionOwnerBundleIdentifier: tccPermissionOwnerBundleIdentifier,
    tccPermissionOwnerDisplayName: tccPermissionOwnerDisplayName,
    helperActsAsOsActionExecutor: helperActsAsOsActionExecutor,
    mainAppUnsafeOsActionsAllowed: mainAppUnsafeOsActionsAllowed,
    helperOwnsUnsafeOsActions: helperOwnsUnsafeOsActions,
    helperOwnedActionCategories: helperOwnedActionCategories,
    xpcNextParityCommands: xpcNextParityCommands,
    xpcProductionReadinessCriteria: xpcProductionReadinessCriteria,
  );
}

class MacosComputerUseInstallMigrationGuardrails {
  const MacosComputerUseInstallMigrationGuardrails._();

  static const schemaName = 'macos_computer_use_install_migration_guardrails';
  static const schemaVersion = 1;
  static const milestone = 'M38';
  static const requiredGuardrailIds = [
    'preserve_helper_identity_when_possible',
    'detect_tcc_regrant_required',
    'explain_regrant_reason',
    'block_old_helper_action_requests',
    'surface_restart_before_release_signoff',
  ];

  static Map<String, dynamic> fromState({
    Map<String, dynamic>? helperStatus,
    Map<String, dynamic>? helperIpcRuntime,
  }) {
    final embeddedHelperPath = _stringFromMaps('embeddedHelperPath', [
      helperStatus,
      helperIpcRuntime,
    ]);
    final runningHelperPath = _stringFromMaps('runningHelperPath', [
      helperStatus,
      helperIpcRuntime,
    ]);
    final helperPathMismatch =
        _boolFromMaps('helperPathMismatch', [helperStatus, helperIpcRuntime]) ==
            true ||
        _boolFromMaps('preservedMismatchedHelperPath', [
              helperStatus,
              helperIpcRuntime,
            ]) ==
            true ||
        (embeddedHelperPath != null &&
            runningHelperPath != null &&
            embeddedHelperPath != runningHelperPath);
    final helperPathMatchesRunning =
        _boolFromMaps('helperPathMatchesRunningHelper', [
          helperStatus,
          helperIpcRuntime,
        ]) ==
        true;
    final staleReasons = _uniqueStrings([
      ..._stringListFromMaps('helperSharedDiagnosticsStaleReasons', [
        helperStatus,
        helperIpcRuntime,
      ]),
      ..._stringListFromMaps('helperDiagnosticsLatestStaleReasons', [
        _mapValue(helperIpcRuntime?['xpcRuntimeDiagnostics']),
      ]),
    ]);
    final helperDiagnosticsStale =
        staleReasons.isNotEmpty ||
        _boolFromMaps('helperSharedDiagnosticsStale', [
              helperStatus,
              helperIpcRuntime,
            ]) ==
            true;
    final oldHelperActionRequestsBlocked =
        _boolFromMaps('oldHelperActionRequestsBlocked', [
          helperStatus,
          helperIpcRuntime,
        ]) ??
        true;
    final tccRegrantRequired =
        helperPathMismatch ||
        staleReasons.contains('helper_bundle_path_mismatch') ||
        staleReasons.contains('helper_executable_path_mismatch');
    final blockers = <String>[
      if (helperPathMismatch) 'helper_path_mismatch',
      if (helperDiagnosticsStale) 'stale_helper_diagnostics',
      if (!oldHelperActionRequestsBlocked)
        'old_helper_action_requests_not_blocked',
    ];
    final status = blockers.isEmpty ? 'ready' : 'blocked';
    final regrantReason = tccRegrantRequired
        ? 'Helper Accessibility grants are tied to the helper app identity. Regrant may be required after the helper path, executable, or signing identity changes.'
        : 'The current helper identity matches the expected embedded helper path.';

    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'milestone': milestone,
      'status': status,
      'ready': blockers.isEmpty,
      'requiredGuardrailIds': requiredGuardrailIds,
      'm38InstallMigrationGate': {
        'status': status,
        'ready': blockers.isEmpty,
        'blockers': blockers,
      },
      'helperIdentityPreservedWhenPossible': true,
      'expectedHelperPath': embeddedHelperPath,
      'runningHelperPath': runningHelperPath,
      'helperPathMatchesRunningHelper': helperPathMatchesRunning,
      'helperPathMismatch': helperPathMismatch,
      'helperDiagnosticsStale': helperDiagnosticsStale,
      'helperDiagnosticsStaleReasons': staleReasons,
      'tccRegrantRequired': tccRegrantRequired,
      'tccRegrantReason': regrantReason,
      'oldHelperActionRequestsBlocked': oldHelperActionRequestsBlocked,
      'allowedDuringMigration': [
        'status',
        'open_helper_ui',
        'permission_recovery',
        'emergency_stop',
      ],
      'blockedDuringMigration': [
        'screenshot',
        'window_capture',
        'focus',
        'pointer_input',
        'keyboard_input',
        'system_audio_recording',
      ],
      'nextAction': blockers.isEmpty
          ? 'Install and migration guardrails are ready.'
          : 'Restart Caverno Computer Use from the installed Caverno bundle, recheck helper identity, and ask the user to regrant TCC only if macOS reports the new helper as missing permissions.',
    };
  }

  static bool? _boolFromMaps(String key, List<Map<String, dynamic>?> sources) {
    for (final source in sources) {
      final value = source?[key];
      if (value is bool) {
        return value;
      }
    }
    return null;
  }

  static String? _stringFromMaps(
    String key,
    List<Map<String, dynamic>?> sources,
  ) {
    for (final source in sources) {
      final value = source?[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static List<String> _stringListFromMaps(
    String key,
    List<Map<String, dynamic>?> sources,
  ) {
    return [
      for (final source in sources)
        if (source?[key] is Iterable)
          for (final value in source![key] as Iterable)
            if (value is String && value.isNotEmpty) value,
    ];
  }

  static Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static List<String> _uniqueStrings(Iterable<String> values) {
    return LinkedHashSet<String>.from(values).toList(growable: false);
  }
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
    this.permissionRecoverySummary,
    this.productionActionPolicy,
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
    this.auditPrivacyControls,
    this.installMigrationGuardrails,
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
  final Map<String, dynamic>? permissionRecoverySummary;
  final Map<String, dynamic>? productionActionPolicy;
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
  final Map<String, dynamic>? auditPrivacyControls;
  final Map<String, dynamic>? installMigrationGuardrails;
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
      'permissionRecoverySummary': permissionRecoverySummary,
      'productionActionPolicy': productionActionPolicy,
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
      'auditPrivacyControls': auditPrivacyControls,
      'installMigrationGuardrails': installMigrationGuardrails,
      'lastLiveSmokeReport': lastLiveSmokeReport,
      'lastExistingHelperProbeReport': lastExistingHelperProbeReport,
      if (lastDiagnosticExportPath != null)
        'lastDiagnosticExportPath': lastDiagnosticExportPath,
    };
  }
}

class MacosComputerUsePermissionRecoverySummary {
  const MacosComputerUsePermissionRecoverySummary({
    required this.status,
    required this.issueIds,
    required this.missingPermissionLabels,
    required this.revokedPermissionLabels,
    required this.helperSharedDiagnosticsStale,
    required this.helperSharedDiagnosticsStaleReasons,
    required this.helperPathMismatch,
    required this.debugReleaseHelperMismatch,
    required this.helperUnreachable,
    required this.mainAppPermissionPromptsBlocked,
    required this.mainAppPermissionPromptBoundary,
    required this.nextAction,
  });

  factory MacosComputerUsePermissionRecoverySummary.fromState({
    required MacosComputerUseBackendInfo backend,
    MacosComputerUsePermissionSnapshot? permissions,
    Map<String, dynamic>? helperStatus,
    Map<String, dynamic>? helperIpcRuntime,
    Map<String, dynamic>? onboardingVerification,
    Map<String, dynamic>? helperStatusPersistence,
  }) {
    final helperUnreachable =
        permissions?.helperReachable == false ||
        _boolFromMaps('helperReachable', [helperStatus, helperIpcRuntime]) ==
            false;
    final previousAccessibilityGrant = _previousPermissionGrant(
      'accessibilityGranted',
      helperStatus: helperStatus,
      helperIpcRuntime: helperIpcRuntime,
      onboardingVerification: onboardingVerification,
      helperStatusPersistence: helperStatusPersistence,
    );
    final previousScreenCaptureGrant = _previousPermissionGrant(
      'screenCaptureGranted',
      helperStatus: helperStatus,
      helperIpcRuntime: helperIpcRuntime,
      onboardingVerification: onboardingVerification,
      helperStatusPersistence: helperStatusPersistence,
    );

    final revokedPermissionLabels = <String>[
      if (permissions?.accessibilityGranted == false &&
          previousAccessibilityGrant)
        'Accessibility',
      if (permissions?.screenCaptureGranted == false &&
          previousScreenCaptureGrant)
        'Screen & System Audio Recording',
    ];
    final missingPermissionLabels = <String>[
      if (!helperUnreachable &&
          permissions?.accessibilityGranted != true &&
          !revokedPermissionLabels.contains('Accessibility'))
        'Accessibility',
      if (!helperUnreachable &&
          permissions?.screenCaptureGranted != true &&
          !revokedPermissionLabels.contains('Screen & System Audio Recording'))
        'Screen & System Audio Recording',
    ];

    final staleReasons = _uniqueStrings([
      ..._stringListFromMaps('helperSharedDiagnosticsStaleReasons', [
        helperStatus,
        helperIpcRuntime,
      ]),
      ..._stringListFromMaps('helperDiagnosticsLatestStaleReasons', [
        _mapValue(helperIpcRuntime?['xpcRuntimeDiagnostics']),
      ]),
    ]);
    final helperSharedDiagnosticsStale =
        _boolFromMaps('helperSharedDiagnosticsStale', [
              helperStatus,
              helperIpcRuntime,
            ]) ==
            true ||
        _boolFromMaps('helperDiagnosticsLatestStale', [
              _mapValue(helperIpcRuntime?['xpcRuntimeDiagnostics']),
            ]) ==
            true ||
        staleReasons.isNotEmpty;
    final helperPathMismatch =
        _boolFromMaps('helperPathMismatch', [helperStatus, helperIpcRuntime]) ==
            true ||
        _boolFromMaps('preservedMismatchedHelperPath', [
              helperStatus,
              helperIpcRuntime,
            ]) ==
            true ||
        _pathsDiffer(helperStatus, helperIpcRuntime);
    final debugReleaseHelperMismatch =
        helperPathMismatch &&
        _pathsSuggestBuildMismatch(helperStatus, helperIpcRuntime);

    final issueIds = <String>[
      if (helperUnreachable) 'helper_unreachable',
      if (helperSharedDiagnosticsStale) 'stale_helper_diagnostics',
      if (debugReleaseHelperMismatch) 'debug_release_helper_mismatch',
      if (helperPathMismatch && !debugReleaseHelperMismatch)
        'helper_path_mismatch',
      if (revokedPermissionLabels.isNotEmpty) 'revoked_permissions',
      if (missingPermissionLabels.isNotEmpty) 'missing_permissions',
    ];
    final mainAppPermissionPromptsBlocked = backend.usesSeparateHelper;
    final nextAction = _nextAction(
      backend: backend,
      helperUnreachable: helperUnreachable,
      helperSharedDiagnosticsStale: helperSharedDiagnosticsStale,
      helperPathMismatch: helperPathMismatch,
      revokedPermissionLabels: revokedPermissionLabels,
      missingPermissionLabels: missingPermissionLabels,
    );

    return MacosComputerUsePermissionRecoverySummary(
      status: issueIds.isEmpty ? 'ready' : 'needs_recovery',
      issueIds: issueIds,
      missingPermissionLabels: missingPermissionLabels,
      revokedPermissionLabels: revokedPermissionLabels,
      helperSharedDiagnosticsStale: helperSharedDiagnosticsStale,
      helperSharedDiagnosticsStaleReasons: staleReasons,
      helperPathMismatch: helperPathMismatch,
      debugReleaseHelperMismatch: debugReleaseHelperMismatch,
      helperUnreachable: helperUnreachable,
      mainAppPermissionPromptsBlocked: mainAppPermissionPromptsBlocked,
      mainAppPermissionPromptBoundary: mainAppPermissionPromptsBlocked
          ? 'split_permission_owner'
          : 'in_process_compatibility',
      nextAction: nextAction,
    );
  }

  final String status;
  final List<String> issueIds;
  final List<String> missingPermissionLabels;
  final List<String> revokedPermissionLabels;
  final bool helperSharedDiagnosticsStale;
  final List<String> helperSharedDiagnosticsStaleReasons;
  final bool helperPathMismatch;
  final bool debugReleaseHelperMismatch;
  final bool helperUnreachable;
  final bool mainAppPermissionPromptsBlocked;
  final String mainAppPermissionPromptBoundary;
  final String nextAction;

  bool get isReady => status == 'ready';

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'ready': isReady,
      'issueIds': issueIds,
      'missingPermissionLabels': missingPermissionLabels,
      'revokedPermissionLabels': revokedPermissionLabels,
      'helperSharedDiagnosticsStale': helperSharedDiagnosticsStale,
      'helperSharedDiagnosticsStaleReasons':
          helperSharedDiagnosticsStaleReasons,
      'helperPathMismatch': helperPathMismatch,
      'debugReleaseHelperMismatch': debugReleaseHelperMismatch,
      'helperUnreachable': helperUnreachable,
      'mainAppPermissionPromptsBlocked': mainAppPermissionPromptsBlocked,
      'mainAppPermissionPromptBoundary': mainAppPermissionPromptBoundary,
      'nextAction': nextAction,
    };
  }

  static String _nextAction({
    required MacosComputerUseBackendInfo backend,
    required bool helperUnreachable,
    required bool helperSharedDiagnosticsStale,
    required bool helperPathMismatch,
    required List<String> revokedPermissionLabels,
    required List<String> missingPermissionLabels,
  }) {
    if (helperUnreachable) {
      return 'Launch ${backend.permissionOwnerName}, then recheck permissions.';
    }
    if (helperPathMismatch) {
      return 'Restart ${backend.permissionOwnerName} from Caverno, then recheck helper reachability before sign-off.';
    }
    if (helperSharedDiagnosticsStale) {
      return 'Refresh or restart ${backend.permissionOwnerName} so Caverno reads current helper diagnostics.';
    }
    if (revokedPermissionLabels.isNotEmpty) {
      final grants = _macosComputerUseReenableInstruction(
        accessibilityOwnerName: backend.permissionOwnerName,
        permissionLabels: revokedPermissionLabels,
      );
      return 'Ask the user to re-enable $grants in System Settings, then recheck permissions.';
    }
    if (missingPermissionLabels.isNotEmpty) {
      final grants = _macosComputerUseGrantInstruction(
        accessibilityOwnerName: backend.permissionOwnerName,
        permissionLabels: missingPermissionLabels,
      );
      return 'Open System Settings, grant $grants, then recheck permissions.';
    }
    return 'No recovery action is needed.';
  }

  static bool _previousPermissionGrant(
    String key, {
    Map<String, dynamic>? helperStatus,
    Map<String, dynamic>? helperIpcRuntime,
    Map<String, dynamic>? onboardingVerification,
    Map<String, dynamic>? helperStatusPersistence,
  }) {
    final candidates = <Map<String, dynamic>?>[
      onboardingVerification,
      helperStatusPersistence?['onboardingVerification'] is Map
          ? Map<String, dynamic>.from(
              helperStatusPersistence!['onboardingVerification'] as Map,
            )
          : null,
      helperStatus?['onboardingVerification'] is Map
          ? Map<String, dynamic>.from(
              helperStatus!['onboardingVerification'] as Map,
            )
          : null,
      helperStatus?['helperStatusPersistence'] is Map
          ? _mapValue(
              (helperStatus!['helperStatusPersistence']
                  as Map)['onboardingVerification'],
            )
          : null,
      helperIpcRuntime?['onboardingVerification'] is Map
          ? Map<String, dynamic>.from(
              helperIpcRuntime!['onboardingVerification'] as Map,
            )
          : null,
      helperIpcRuntime?['helperStatusPersistence'] is Map
          ? _mapValue(
              (helperIpcRuntime!['helperStatusPersistence']
                  as Map)['onboardingVerification'],
            )
          : null,
    ];
    for (final candidate in candidates) {
      final permissions = _mapValue(candidate?['permissions']);
      if (permissions?[key] == true) {
        return true;
      }
    }
    return false;
  }

  static bool _pathsDiffer(
    Map<String, dynamic>? helperStatus,
    Map<String, dynamic>? helperIpcRuntime,
  ) {
    final explicitMatch = _boolFromMaps('helperPathMatchesRunningHelper', [
      helperStatus,
      helperIpcRuntime,
    ]);
    if (explicitMatch == false) {
      return true;
    }
    final embedded = _stringFromMaps('embeddedHelperPath', [
      helperStatus,
      helperIpcRuntime,
    ]);
    final running = _stringFromMaps('runningHelperPath', [
      helperStatus,
      helperIpcRuntime,
    ]);
    return embedded != null && running != null && embedded != running;
  }

  static bool _pathsSuggestBuildMismatch(
    Map<String, dynamic>? helperStatus,
    Map<String, dynamic>? helperIpcRuntime,
  ) {
    final embeddedPath = _stringFromMaps('embeddedHelperPath', [
      helperStatus,
      helperIpcRuntime,
    ]);
    final runningPath = _stringFromMaps('runningHelperPath', [
      helperStatus,
      helperIpcRuntime,
    ]);
    final mismatchedPath = _stringFromMaps('mismatchedHelperPath', [
      helperStatus,
      helperIpcRuntime,
    ]);
    final paths = <String>[
      ..._stringListFromMaps('mismatchedHelperPaths', [
        helperStatus,
        helperIpcRuntime,
      ]),
      ?embeddedPath,
      ?runningPath,
      ?mismatchedPath,
    ];
    final hasDebug = paths.any(
      (path) => path.contains('/Build/Products/Debug/'),
    );
    final hasRelease = paths.any(
      (path) =>
          path.contains('/Build/Products/Release/') ||
          path.startsWith('/Applications/'),
    );
    final hasEmbedded = paths.any(
      (path) => path.contains('/Contents/Helpers/'),
    );
    final hasStandaloneDebug = paths.any(
      (path) =>
          path.contains('/Build/Products/Debug/') &&
          !path.contains('/Contents/Helpers/'),
    );
    return (hasDebug && hasRelease) || (hasEmbedded && hasStandaloneDebug);
  }

  static bool? _boolFromMaps(String key, List<Map<String, dynamic>?> sources) {
    for (final source in sources) {
      final value = source?[key];
      if (value is bool) {
        return value;
      }
    }
    return null;
  }

  static String? _stringFromMaps(
    String key,
    List<Map<String, dynamic>?> sources,
  ) {
    for (final source in sources) {
      final value = source?[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static List<String> _stringListFromMaps(
    String key,
    List<Map<String, dynamic>?> sources,
  ) {
    return [
      for (final source in sources)
        if (source?[key] is Iterable)
          for (final value in source![key] as Iterable)
            if (value is String && value.isNotEmpty) value,
    ];
  }

  static Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static List<String> _uniqueStrings(Iterable<String> values) {
    return LinkedHashSet<String>.from(values).toList(growable: false);
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
      final grants = _macosComputerUseGrantInstruction(
        accessibilityOwnerName: backend.permissionOwnerName,
        permissionLabels: missingPermissionLabels,
      );
      return 'Open System Settings, grant $grants, then refresh permissions.';
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
