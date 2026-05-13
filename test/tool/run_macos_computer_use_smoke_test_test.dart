import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_setup.dart';
import 'package:flutter_test/flutter_test.dart';

const _manualTccNextAction = MacosComputerUseMvpGuidance.manualTccNextAction;
const _desktopActionNextAction =
    MacosComputerUseMvpGuidance.desktopActionCanaryNextAction;
const _llmCanaryNextAction = MacosComputerUseMvpGuidance.llmCanaryNextAction;

void main() {
  late String script;
  late String smokeTest;
  late String overlaySmokeSupport;
  late String helperSource;
  late String runnerSource;
  late String windowManagerSource;
  late String runnerInfoPlist;
  late String helperInfoPlist;
  late String liveCanaryScript;
  late String manualTccSignoffScript;
  late String mvpSignoffScript;
  late String mvpReadinessPreflightScript;
  late String postMergeSanityScript;
  late String desktopActionCanaryScript;
  late String llmDecisionCanaryScript;
  late String mvpFixtureLlmCanaryScript;
  late String mvpFixtureVisionLlmCanaryScript;
  late String realAppObserveCanaryScript;
  late String m14RealAppHandoffScript;
  late String m15ActionProposalHandoffScript;
  late String m15LlmReviewCanaryScript;
  late String m16ApprovalPacketScript;
  late String m17ExecutionRehearsalScript;
  late String m18ExecutionHandoffScript;
  late String m20ExecutionResultIntakeScript;
  late String m22PostActionReviewScript;
  late String m23CycleOutcomeHandoffScript;
  late String m25NextCycleSeedHandoffScript;
  late String m26ObserveRestartPacketScript;
  late String m27ScreenshotRequestHandoffScript;
  late String m28ScreenshotEvidenceIntakeScript;
  late String m29ObserveCanaryRunPacketScript;
  late String m30ObserveResultIntakeScript;
  late String mvpLlmReadinessScript;
  late String mvpDemoReadinessScript;
  late String releaseReadinessWrapper;
  late String mvpFixtureScript;
  late String mvpFixtureSource;
  late String mvpFixtureRunbook;
  late String realAppObserveRunbook;
  late String polishReviewSummary;
  late String existingHelperProbe;
  late String architectureDoc;
  late String manualProcessChecklist;

  setUpAll(() {
    script = File(
      'tool/run_macos_computer_use_smoke_test.sh',
    ).readAsStringSync();
    smokeTest = File(
      'integration_test/macos_computer_use_smoke_test.dart',
    ).readAsStringSync();
    overlaySmokeSupport = File(
      'integration_test/test_support/macos_computer_use_overlay_smoke.dart',
    ).readAsStringSync();
    helperSource = File(
      'macos/ComputerUseHelper/ComputerUseHelperApp.swift',
    ).readAsStringSync();
    runnerSource = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    windowManagerSource = File(
      'lib/core/services/window_manager_service.dart',
    ).readAsStringSync();
    runnerInfoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    helperInfoPlist = File(
      'macos/ComputerUseHelper/Info.plist',
    ).readAsStringSync();
    liveCanaryScript = File(
      'tool/run_macos_computer_use_live_canary.sh',
    ).readAsStringSync();
    manualTccSignoffScript = File(
      'tool/run_macos_computer_use_manual_tcc_signoff.sh',
    ).readAsStringSync();
    mvpSignoffScript = File(
      'tool/run_macos_computer_use_mvp_signoff.sh',
    ).readAsStringSync();
    mvpReadinessPreflightScript = File(
      'tool/run_macos_computer_use_mvp_readiness_preflight.sh',
    ).readAsStringSync();
    postMergeSanityScript = File(
      'tool/run_macos_computer_use_post_merge_sanity.sh',
    ).readAsStringSync();
    desktopActionCanaryScript = File(
      'tool/run_macos_computer_use_desktop_action_canary.sh',
    ).readAsStringSync();
    llmDecisionCanaryScript = File(
      'tool/run_macos_computer_use_llm_decision_canary.sh',
    ).readAsStringSync();
    mvpFixtureLlmCanaryScript = File(
      'tool/run_macos_computer_use_mvp_fixture_llm_canary.sh',
    ).readAsStringSync();
    mvpFixtureVisionLlmCanaryScript = File(
      'tool/run_macos_computer_use_mvp_fixture_vision_llm_canary.sh',
    ).readAsStringSync();
    realAppObserveCanaryScript = File(
      'tool/run_macos_computer_use_real_app_observe_canary.sh',
    ).readAsStringSync();
    m14RealAppHandoffScript = File(
      'tool/run_macos_computer_use_m14_real_app_handoff.sh',
    ).readAsStringSync();
    m15ActionProposalHandoffScript = File(
      'tool/run_macos_computer_use_m15_action_proposal_handoff.sh',
    ).readAsStringSync();
    m15LlmReviewCanaryScript = File(
      'tool/run_macos_computer_use_m15_llm_review_canary.sh',
    ).readAsStringSync();
    m16ApprovalPacketScript = File(
      'tool/run_macos_computer_use_m16_approval_packet.sh',
    ).readAsStringSync();
    m17ExecutionRehearsalScript = File(
      'tool/run_macos_computer_use_m17_execution_rehearsal.sh',
    ).readAsStringSync();
    m18ExecutionHandoffScript = File(
      'tool/run_macos_computer_use_m18_execution_handoff.sh',
    ).readAsStringSync();
    m20ExecutionResultIntakeScript = File(
      'tool/run_macos_computer_use_m20_execution_result_intake.sh',
    ).readAsStringSync();
    m22PostActionReviewScript = File(
      'tool/run_macos_computer_use_m22_post_action_review.sh',
    ).readAsStringSync();
    m23CycleOutcomeHandoffScript = File(
      'tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh',
    ).readAsStringSync();
    m25NextCycleSeedHandoffScript = File(
      'tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh',
    ).readAsStringSync();
    m26ObserveRestartPacketScript = File(
      'tool/run_macos_computer_use_m26_observe_restart_packet.sh',
    ).readAsStringSync();
    m27ScreenshotRequestHandoffScript = File(
      'tool/run_macos_computer_use_m27_screenshot_request_handoff.sh',
    ).readAsStringSync();
    m28ScreenshotEvidenceIntakeScript = File(
      'tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh',
    ).readAsStringSync();
    m29ObserveCanaryRunPacketScript = File(
      'tool/run_macos_computer_use_m29_observe_canary_run_packet.sh',
    ).readAsStringSync();
    m30ObserveResultIntakeScript = File(
      'tool/run_macos_computer_use_m30_observe_result_intake.sh',
    ).readAsStringSync();
    mvpLlmReadinessScript = File(
      'tool/run_macos_computer_use_mvp_llm_readiness.sh',
    ).readAsStringSync();
    mvpDemoReadinessScript = File(
      'tool/run_macos_computer_use_mvp_demo_readiness.sh',
    ).readAsStringSync();
    releaseReadinessWrapper = File(
      'tool/run_macos_computer_use_release_readiness.sh',
    ).readAsStringSync();
    mvpFixtureScript = File(
      'tool/run_macos_computer_use_mvp_fixture.sh',
    ).readAsStringSync();
    mvpFixtureSource = File(
      'tool/fixtures/macos_computer_use_mvp_fixture/MacOSComputerUseMvpFixtureApp.swift',
    ).readAsStringSync();
    existingHelperProbe = File(
      'tool/macos_computer_use_existing_helper_probe.swift',
    ).readAsStringSync();
    architectureDoc = File(
      'docs/macos_computer_use_helper_architecture.md',
    ).readAsStringSync();
    manualProcessChecklist = File(
      'docs/macos_computer_use_manual_process_checklist.md',
    ).readAsStringSync();
    mvpFixtureRunbook = File(
      'docs/macos_computer_use_mvp_fixture_runbook.md',
    ).readAsStringSync();
    realAppObserveRunbook = File(
      'docs/macos_computer_use_real_app_observe_runbook.md',
    ).readAsStringSync();
    polishReviewSummary = File(
      'docs/macos_computer_use_polish_review_summary.md',
    ).readAsStringSync();
  });

  test('desktop startup does not block runApp on window readiness', () {
    expect(windowManagerSource, contains('unawaited(_showWhenReady'));
    expect(windowManagerSource, contains('Future<void> _showWhenReady'));
    expect(windowManagerSource, contains('windowManager.waitUntilReadyToShow'));
  });

  test('M7 sign-off expands to release strict XPC artifact checks', () {
    expect(script, contains('--m7-signoff|--release-signoff'));
    expect(script, contains('BUILD_MODE=release'));
    expect(script, contains('STRICT_XPC=1'));
    expect(script, contains('REGISTER_XPC_AGENT=1'));
    expect(script, contains('CLEANUP_XPC_AGENT=1'));
    expect(script, contains('REQUIRE_RELEASE_SIGNOFF=1'));
  });

  test('M3 documents production IPC readiness', () {
    expect(
      architectureDoc,
      contains('LaunchAgent-backed named XPC is the preferred production IPC'),
    );
    expect(
      architectureDoc,
      contains('distributed notifications remain an observable fallback path'),
    );
    expect(
      architectureDoc,
      contains(
        'must not treat distributed-notification fallback as production IPC',
      ),
    );
    expect(
      architectureDoc,
      contains('readiness. Fallback is allowed only as an observable'),
    );
    expect(architectureDoc, contains('Current M3 implementation status'));
    expect(
      architectureDoc,
      contains('LaunchAgent-backed named XPC is the preferred production IPC'),
    );
    expect(architectureDoc, contains('external_helper_mach_service'));
    expect(architectureDoc, contains('launchd_mach_service_registration'));
    expect(
      architectureDoc,
      contains('com.noguwo.apps.caverno.computer-use.xpc'),
    );
    expect(architectureDoc, contains('xpcProductionGate'));
    expect(architectureDoc, contains('DNC fallback remains non-destructive'));
    expect(architectureDoc, contains('## Helper IPC Protocol'));
    expect(
      architectureDoc,
      contains('typed request envelope across the preferred'),
    );
    expect(
      architectureDoc,
      contains('LaunchAgent-backed named XPC transport and the observable'),
    );
    expect(architectureDoc, contains('distributed-notification fallback'));
    expect(architectureDoc, contains('selected transport'));
    expect(architectureDoc, contains('preferred transport'));
    expect(architectureDoc, contains('fallback transport metadata'));
    expect(architectureDoc, contains('## Migration Completion Status'));
    expect(
      architectureDoc,
      contains('The helper migration is complete for the current MVP path.'),
    );
    expect(
      architectureDoc,
      contains(
        'distributed notifications retained only as observable fallback',
      ),
    );
    expect(
      architectureDoc,
      contains(
        'The main app no longer owns unsafe macOS Computer Use actions.',
      ),
    );
    expect(architectureDoc, contains('mainAppUnsafeOsActionsAllowed=false'));
    expect(architectureDoc, contains('helperOwnsUnsafeOsActions=true'));
    expect(
      architectureDoc,
      contains('Remaining work is review hardening and user-operated sign-off'),
    );
    expect(
      architectureDoc,
      contains('M13: Complete review and merge hardening'),
    );
    expect(
      architectureDoc,
      contains('Keep Computer Use behind the Advanced settings flow'),
    );
    expect(
      architectureDoc,
      contains('M14: Expand real-app observe-only canaries'),
    );
    expect(
      architectureDoc,
      contains('M15: Convert ready M14 observe-only evidence'),
    );
    expect(architectureDoc, contains('M15 LLM review'));
    expect(
      architectureDoc,
      contains('M16: Convert ready M15 action-proposal and review evidence'),
    );
    expect(architectureDoc, contains('approvalBlockers'));
    expect(
      architectureDoc,
      contains('M17: Convert an approved M16 approval packet'),
    );
    expect(architectureDoc, contains('M17 execution rehearsal'));
    expect(
      architectureDoc,
      contains('M18: Convert a ready M17 execution rehearsal'),
    );
    expect(architectureDoc, contains('action-time'));
    expect(
      architectureDoc,
      contains('confirmations that the user must perform'),
    );
    expect(
      architectureDoc,
      contains('M19: Surface the latest M18 execution handoff'),
    );
    expect(
      architectureDoc,
      contains('M20: Record user-operated runtime result evidence'),
    );
    expect(architectureDoc, contains('M22: Convert ready M20 result intake'));
    expect(
      architectureDoc,
      contains('M23: Convert ready M22 post-action review evidence'),
    );
    expect(
      architectureDoc,
      contains('M24: Surface M23 cycle outcome handoffs'),
    );
    expect(architectureDoc, contains('M25: Convert a ready M23'));
    expect(architectureDoc, contains('M26: Convert a ready M25'));
    expect(architectureDoc, contains('M27: Convert a ready M26'));
    expect(architectureDoc, contains('M28: Convert a ready M27'));
    expect(architectureDoc, contains('M15 review/gate consistency scope'));
    expect(architectureDoc, contains('blockedReviewEvidence'));
    expect(architectureDoc, contains('otherwise mutate external state'));
    expect(architectureDoc, contains('## Verification Gates'));
    expect(architectureDoc, contains('Static verification'));
    expect(
      architectureDoc,
      contains('bash tool/run_macos_computer_use_post_merge_sanity.sh'),
    );
    expect(architectureDoc, contains('Release artifact verification'));
    expect(architectureDoc, contains('Production IPC verification'));
    expect(architectureDoc, contains('LLM verification'));
    expect(architectureDoc, contains('Manual TCC verification'));
    expect(architectureDoc, contains('Desktop action verification'));
    expect(architectureDoc, contains('MVP aggregation verification'));
    expect(architectureDoc, contains('PR review verification'));
    expect(architectureDoc, contains('manual_tcc_report_summary.json'));
    expect(architectureDoc, contains('user-operated safe target run'));
    expect(architectureDoc, contains('PR Review Artifacts'));
    expect(
      architectureDoc,
      contains('bash tool/run_macos_computer_use_mvp_readiness_preflight.sh'),
    );
    expect(architectureDoc, contains('without launching apps'));
  });

  test('release report includes M7 gate and runtime readiness fields', () {
    expect(script, contains('"schemaVersion": 2'));
    expect(script, contains('"releaseSignoffGate": gate'));
    expect(script, contains('"releaseRuntimeReadiness": runtime_readiness'));
    expect(script, contains('"releaseSignoff"'));
    expect(script, contains('"status": "not_measured"'));
  });

  test(
    'release diagnostics write a report before required sign-off failure',
    () {
      expect(script, isNot(contains('test -d "\${RELEASE_APP}"')));
      expect(script, isNot(contains('test -d "\${RELEASE_HELPER}"')));
      expect(script, isNot(contains('test -f "\${RELEASE_AGENT}"')));
      expect(
        script,
        contains('os.environ["REQUIRE_RELEASE_SIGNOFF_DART"] == "true"'),
      );
      expect(
        script,
        contains(
          'os.environ["REQUIRE_RELEASE_RUNTIME_SIGNOFF_DART"] != "true"',
        ),
      );
      expect(script, contains('raise SystemExit(1)'));
    },
  );

  test('M8 runtime sign-off launches the release app and helper paths', () {
    expect(script, contains('--m8-runtime-signoff|--release-runtime-signoff'));
    expect(script, contains('REQUIRE_RELEASE_RUNTIME_SIGNOFF=1'));
    expect(script, contains('SKIP_RELEASE_BUILD=1'));
    expect(script, contains('--rebuild-release'));
    expect(
      script,
      contains('"schemaName": "macos_computer_use_release_runtime_signoff"'),
    );
    expect(script, contains('"releaseRuntimeSignoffGate": runtime_gate'));
    expect(script, contains('--replace-app'));
    expect(script, contains('--require-app-path-match'));
    expect(script, contains('--require-helper-path-match'));
    expect(script, contains('--require-capture'));
    expect(script, contains('--require-input'));
    expect(script, contains('--require-audio'));
  });

  test('existing helper probe can enforce running app path identity', () {
    expect(existingHelperProbe, contains('requireAppPathMatch'));
    expect(existingHelperProbe, contains('replaceMismatchedApp'));
    expect(existingHelperProbe, contains('--require-app-path-match'));
    expect(existingHelperProbe, contains('--replace-app'));
    expect(existingHelperProbe, contains('"id": "app_path_match"'));
    expect(existingHelperProbe, contains('"appPathMatchesExpected"'));
  });

  test('M9 keeps TCC runtime sign-off user operated', () {
    expect(script, contains('Manual TCC sign-off notice'));
    expect(script, contains('does not grant permissions or edit TCC'));
    expect(
      script,
      contains(
        'Automation agents should stop here and ask the user to run this command manually.',
      ),
    );
    expect(script, contains('rerun --m8-runtime-signoff manually'));
    expect(architectureDoc, contains('## Manual TCC Sign-Off Runbook'));
    expect(
      architectureDoc,
      contains('TCC verification is a user-operated step.'),
    );
    expect(
      architectureDoc,
      contains('Automation may run these non-TCC checks:'),
    );
    expect(
      architectureDoc,
      contains('Only the user should run this TCC runtime command:'),
    );
    expect(
      architectureDoc,
      contains('dart run tool/macos_computer_use_manual_tcc_report.dart'),
    );
    expect(manualTccSignoffScript, contains('--m8-runtime-signoff'));
    expect(
      manualTccSignoffScript,
      contains('user-operated manual verification only'),
    );
    expect(manualTccSignoffScript, contains('does not grant permissions'));
    expect(manualTccSignoffScript, contains('manual_tcc_report_summary.json'));
    expect(
      manualProcessChecklist,
      contains('bash tool/run_macos_computer_use_manual_tcc_signoff.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('bash tool/run_macos_computer_use_post_merge_sanity.sh'),
    );
  });

  test('Computer Use helper runs as a single hidden agent process', () {
    expect(runnerInfoPlist, isNot(contains('NSSystemAudioUsageDescription')));
    expect(helperInfoPlist, contains('NSSystemAudioUsageDescription'));
    expect(runnerSource, isNot(contains('CGRequestScreenCaptureAccess')));
    expect(runnerSource, contains('main_app_screen_capture_blocked'));
    expect(helperSource, contains('screenCaptureDeniedResponse'));
    expect(
      helperSource,
      contains('guard computerUsePermissionSnapshot().screenCaptureGranted'),
    );
    expect(
      helperSource,
      contains(
        'displayScreenshotStep: verifyOnboardingDisplayScreenshot(permissions: permissions)',
      ),
    );
    expect(
      helperSource,
      contains(
        'windowCaptureStep: verifyOnboardingWindowCapture(permissions: permissions)',
      ),
    );
    expect(helperInfoPlist, contains('<key>LSUIElement</key>'));
    expect(helperInfoPlist, contains('<true/>'));
    expect(
      helperSource,
      contains('application.setActivationPolicy(.accessory)'),
    );
    expect(
      helperSource,
      isNot(contains('application.setActivationPolicy(.regular)')),
    );
    expect(helperSource, contains('exitForExistingInstanceIfNeeded'));
    expect(helperSource, contains('ComputerUseHelperSingleInstanceLock'));
    expect(helperSource, contains('/tmp/caverno-computer-use-helper.lock'));
    expect(helperSource, contains('readLockOwnerProcessIdentifier'));
    expect(
      helperSource,
      contains('singleInstanceLockRequesterProcessIdentifier'),
    );
    expect(
      helperSource,
      contains('duplicateInstanceShouldPreserveExistingDiagnostics'),
    );
    expect(helperSource, contains('sharedDiagnosticsMatchLockOwner'));
    expect(helperSource, contains('CAVERNO_COMPUTER_USE_PRESENT_MAIN_WINDOW'));
    expect(helperSource, contains('showMainWindow(reason:'));
    expect(runnerSource, contains('finishLaunchForRunningHelper'));
    expect(
      runnerSource,
      contains('sendPreferred(\n      command: .showMainWindow'),
    );
    expect(runnerSource, contains('mainWindowRequest'));
    expect(helperSource, contains('single_instance_lock_acquired'));
    expect(helperSource, contains('duplicate_instance_lock_held'));
    expect(helperSource, contains('duplicate_instance_exiting'));
    expect(helperSource, contains('singleInstancePolicy'));
    expect(helperSource, contains('existingHelperActivated'));
    expect(helperSource, contains('activate_existing_and_exit'));
    expect(helperSource, contains('reuse_existing_and_exit'));
    expect(runnerSource, contains('staleMismatchedLockOwner'));
    expect(runnerSource, contains('activeExpectedLockOwner'));
    expect(runnerSource, contains('alreadyRunningViaLockOwner'));
    expect(runnerSource, contains('replacedStaleHelperLockOwner'));
    expect(runnerSource, contains('forceTerminateProcess'));
    expect(runnerSource, contains('forceTerminatedStaleHelperProcess'));
    expect(runnerSource, contains('preservedMismatchedHelperPath'));
    expect(runnerSource, contains('responseReceivedBeforeTimeout'));
    expect(runnerSource, contains('responseReceivedAfterTimeout'));
    expect(runnerSource, contains('lateResponseElapsedMs'));
    expect(runnerSource, contains('xpc late response received'));
    expect(runnerSource, contains('sendXpcWarmup'));
    expect(runnerSource, contains('static let xpcFallbackTimeout = 3.0'));
    expect(runnerSource, contains('static let xpcWarmupTimeout = 1.0'));
    expect(runnerSource, contains('warmupAttempt'));
    expect(runnerSource, contains('preferredIpcWarmupAttempt'));
    expect(runnerSource, isNot(contains('replacedMismatchedHelperPath')));
    expect(smokeTest, contains('helperProcessPolicyGate'));
    expect(smokeTest, contains('helper_process_policy'));
    expect(smokeTest, contains('single_instance_lock_not_acquired'));
    expect(smokeTest, contains('helper_path_mismatch'));
    expect(smokeTest, contains('helper_path_mismatch_preserved'));
    expect(smokeTest, contains('preservedMismatchedHelperPath'));
    expect(smokeTest, contains('helperPathMatchesRunningHelper'));
    expect(smokeTest, contains('manualTccHandoff'));
    expect(smokeTest, contains('duplicate_helper_processes'));
    expect(smokeTest, contains('dock_policy_not_hidden'));
    expect(overlaySmokeSupport, contains('overlay_foreground_policy_missing'));
    expect(overlaySmokeSupport, contains('overlayIsFloatingPanel'));
    expect(architectureDoc, contains('## Helper Process Policy'));
    expect(
      architectureDoc,
      contains('docs/macos_computer_use_manual_process_checklist.md'),
    );
    expect(architectureDoc, contains('helperRunningProcessCount'));
    expect(architectureDoc, contains('helperDockPolicy'));
    expect(manualProcessChecklist, contains('M13 Review Hardening'));
    expect(
      manualProcessChecklist,
      contains('root list shows `Advanced`, not a top-level'),
    );
    expect(
      manualProcessChecklist,
      contains('Open `Advanced` and confirm `Computer Use` and `Debug`'),
    );
    expect(manualProcessChecklist, contains('normal navigation'));
    expect(manualProcessChecklist, contains('collapsed `Diagnostics`'));
    expect(
      manualProcessChecklist,
      contains('Advanced navigation, collapsed Diagnostics'),
    );
    expect(
      manualProcessChecklist,
      contains(
        'test/features/settings/presentation/pages/advanced_settings_page_test.dart',
      ),
    );
    expect(manualProcessChecklist, contains('Hidden Helper'));
    expect(manualProcessChecklist, contains('Path Mismatch'));
    expect(manualProcessChecklist, contains('Permission Overlay'));
    expect(manualProcessChecklist, contains('overlayForegroundPolicy'));
  });

  test('computer-use live canary avoids TCC-gated smoke checks', () {
    expect(script, contains('--computer-use-live-canary'));
    expect(script, contains('REQUIRE_COMPUTER_USE_LIVE_CANARY=1'));
    expect(
      script,
      contains(
        '--dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_LIVE_CANARY',
      ),
    );
    expect(script, contains('REQUIRE_CAPTURE_READY=0'));
    expect(script, contains('REQUIRE_INPUT_READY=0'));
    expect(script, contains('REQUIRE_AUDIO_RESOLVED=0'));
    expect(script, contains('REQUIRE_VISION_OBSERVE=0'));
    expect(script, contains('UNSAFE_ARMED=0'));
    expect(liveCanaryScript, contains('Manual TCC follow-up'));
    expect(liveCanaryScript, isNot(contains('--require-capture')));
    expect(liveCanaryScript, isNot(contains('--require-vision-observe')));
    expect(liveCanaryScript, contains('--overlay|--overlay-canary'));
    expect(liveCanaryScript, contains('RUN_OVERLAY_CANARY'));
    expect(liveCanaryScript, contains('overlay_foreground_failed'));
    expect(liveCanaryScript, contains('helperPathMismatchTerminationTimedOut'));
    expect(liveCanaryScript, contains('Manual TCC command'));
  });

  test('desktop action canary requires a user-operated click loop', () {
    expect(script, contains('--desktop-action-canary'));
    expect(script, contains('REQUIRE_DESKTOP_ACTION_CANARY=1'));
    expect(script, contains('UNSAFE_CLICK_ARMED=1'));
    expect(
      script,
      contains(
        '--dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_DESKTOP_ACTION_CANARY',
      ),
    );
    expect(smokeTest, contains('desktopActionCanaryGate'));
    expect(smokeTest, contains('desktop_action_post_click_vision_observe'));
    expect(
      desktopActionCanaryScript,
      contains('macOS Computer Use desktop action canary'),
    );
    expect(
      desktopActionCanaryScript,
      contains('macos_computer_use_desktop_action_canary_summary'),
    );
    expect(
      desktopActionCanaryScript,
      contains('TCC boundary: user-operated manual verification only'),
    );
    expect(
      desktopActionCanaryScript,
      contains('Safety: prepare a safe click target before running'),
    );
    expect(desktopActionCanaryScript, contains('Safe target:'));
    expect(desktopActionCanaryScript, contains('destructive buttons'));
    expect(desktopActionCanaryScript, contains('pre_observe_image'));
    expect(desktopActionCanaryScript, contains('click_sent'));
    expect(desktopActionCanaryScript, contains('post_observe_image'));
    expect(desktopActionCanaryScript, contains('target_not_visible'));
    expect(desktopActionCanaryScript, contains('click_not_sent'));
    expect(desktopActionCanaryScript, contains('post_observe_unavailable'));
    expect(desktopActionCanaryScript, contains('post_observe_unchanged'));
    expect(desktopActionCanaryScript, contains('"safeTargetGuidance"'));
    expect(desktopActionCanaryScript, contains('"expectedPhases"'));
    expect(desktopActionCanaryScript, contains('"phaseStatus"'));
    expect(
      desktopActionCanaryScript,
      contains('--fixture-target|--mvp-fixture'),
    );
    expect(desktopActionCanaryScript, contains('--launch-fixture'));
    expect(desktopActionCanaryScript, contains('fixtureTarget'));
    expect(desktopActionCanaryScript, contains('fixtureLaunchRequested'));
    expect(desktopActionCanaryScript, contains('fixtureApp'));
    expect(desktopActionCanaryScript, contains('Safe Click Target'));
    expect(desktopActionCanaryScript, contains('fixtureExpectedOutcomes'));
    expect(desktopActionCanaryScript, contains('post_observe_image_only'));
    expect(desktopActionCanaryScript, contains('expectedOutcome'));
    expect(desktopActionCanaryScript, contains('No-rebuild helper probe'));
    expect(desktopActionCanaryScript, contains('--no-launch-app'));
    expect(desktopActionCanaryScript, contains('--launch-caverno'));
    expect(desktopActionCanaryScript, contains('Auto-launch Caverno.app'));
    expect(desktopActionCanaryScript, contains('--legacy-integration'));
    expect(desktopActionCanaryScript, contains('--desktop-action-canary'));
    expect(desktopActionCanaryScript, contains('--require-helper-path-match'));
    expect(desktopActionCanaryScript, contains('--replace-helper'));
    expect(desktopActionCanaryScript, contains('--release-helper-signoff'));
    expect(desktopActionCanaryScript, contains('helperPathMatchRequired'));
    expect(desktopActionCanaryScript, contains('helperReplacementRequested'));
    expect(
      desktopActionCanaryScript,
      contains('Helper TCC preserved by default'),
    );
    final defaultProbeArgs = RegExp(
      r'probe_args=\([\s\S]*?\n    \)',
    ).firstMatch(desktopActionCanaryScript)!.group(0)!;
    expect(defaultProbeArgs, isNot(contains('--require-helper-path-match')));
    expect(defaultProbeArgs, isNot(contains('--replace-helper')));
    expect(existingHelperProbe, contains('desktopActionCanaryGate'));
    expect(existingHelperProbe, contains('--no-launch-app'));
    expect(existingHelperProbe, contains('launchMissingApp'));
    expect(existingHelperProbe, contains('Launch it manually, then rerun'));
    expect(
      existingHelperProbe,
      contains('No safe target window was available.'),
    );
    expect(architectureDoc, contains('## Desktop Action Canary'));
    expect(
      architectureDoc,
      contains('bash tool/run_macos_computer_use_desktop_action_canary.sh'),
    );
    expect(architectureDoc, contains('auto-launch `Caverno.app` by default'));
    expect(architectureDoc, contains('desktopActionCanaryGate'));
    expect(architectureDoc, contains('visible harmless target'));
    expect(architectureDoc, contains('target_not_visible'));
    expect(architectureDoc, contains('click_not_sent'));
  });

  test('dedicated live canary runner reports Computer Use purpose', () {
    expect(liveCanaryScript, contains('macOS Computer Use live canary'));
    expect(liveCanaryScript, contains('computer_use_helper_runtime_canary'));
    expect(
      liveCanaryScript,
      contains('TCC boundary: user-operated manual verification only'),
    );
    expect(liveCanaryScript, contains('--computer-use-live-canary'));
    expect(liveCanaryScript, contains('--ci'));
    expect(liveCanaryScript, contains('--stability'));
    expect(liveCanaryScript, contains('--manual|--local'));
    expect(liveCanaryScript, contains('--overlay|--overlay-canary'));
    expect(liveCanaryScript, contains('--repeat'));
    expect(liveCanaryScript, contains('Manual TCC follow-up'));
    expect(liveCanaryScript, contains('classify_failure'));
    expect(liveCanaryScript, contains('helper_status_failed'));
    expect(liveCanaryScript, contains('ipc_not_ready'));
    expect(liveCanaryScript, contains('helper_ping_failed'));
    expect(liveCanaryScript, contains('permission_status_failed'));
    expect(liveCanaryScript, contains('helper_process_policy_failed'));
    expect(liveCanaryScript, contains('cleanup_failed'));
    expect(liveCanaryScript, contains('"failureClasses": failure_classes'));
    expect(liveCanaryScript, contains('"stabilityMode": stability_mode'));
    expect(architectureDoc, contains('## Computer Use Live Canary'));
    expect(
      architectureDoc,
      contains('bash tool/run_macos_computer_use_live_canary.sh --ci'),
    );
    expect(
      architectureDoc,
      contains(
        'bash tool/run_macos_computer_use_live_canary.sh --manual --repeat 3',
      ),
    );
    expect(
      architectureDoc,
      contains('bash tool/run_macos_computer_use_live_canary.sh --stability'),
    );
    expect(
      architectureDoc,
      contains('bash tool/run_macos_computer_use_live_canary.sh --overlay'),
    );
    expect(architectureDoc, contains('manualTccHandoff'));
    expect(architectureDoc, contains('helperPathMismatchTerminationTimedOut'));
    expect(
      architectureDoc,
      contains('dart run tool/macos_computer_use_canary_history.dart'),
    );
    expect(architectureDoc, contains('## Release Readiness Gate'));
    expect(
      architectureDoc,
      contains('dart run tool/macos_computer_use_release_readiness.dart'),
    );
    expect(
      architectureDoc,
      contains('bash tool/run_macos_computer_use_release_readiness.sh --ci'),
    );
    expect(
      architectureDoc,
      contains(
        'bash tool/run_macos_computer_use_release_readiness.sh --signoff',
      ),
    );
    expect(
      architectureDoc,
      contains('macos_computer_use_release_readiness_ci.json'),
    );
    expect(
      architectureDoc,
      contains(
        'Each release readiness JSON and Markdown report contains a `PR Review Summary`',
      ),
    );
    expect(architectureDoc, contains('pending user-operated evidence'));
    expect(architectureDoc, contains('pending automation-safe evidence'));
    expect(
      architectureDoc,
      contains('macos_computer_use_readiness_artifact_index.json'),
    );
    expect(architectureDoc, contains('--refresh-llm-canary'));
    expect(architectureDoc, contains('report-only MVP readiness preflight'));
    expect(architectureDoc, contains('permissions_missing'));
    expect(architectureDoc, contains('--refresh-safe-inputs'));
    expect(architectureDoc, contains('--exit-policy ci'));
    expect(
      architectureDoc,
      contains('tool/run_macos_computer_use_llm_decision_canary.sh'),
    );
    expect(architectureDoc, contains('visionDecision'));
    expect(architectureDoc, contains('safeTargetReasoning'));
    expect(architectureDoc, contains('Manual TCC intake uses this handoff'));
    expect(architectureDoc, contains('manual_required'));
    expect(architectureDoc, contains('desktop_action_canary'));
    expect(architectureDoc, contains('Passing any one canary'));
  });

  test('Computer Use LLM decision canary avoids desktop actions', () async {
    expect(
      llmDecisionCanaryScript,
      contains('macos_computer_use_llm_decision_canary_'),
    );
    expect(
      llmDecisionCanaryScript,
      contains('macos_computer_use_llm_decision_canary_summary'),
    );
    expect(
      llmDecisionCanaryScript,
      contains('computer_use_llm_vision_decision'),
    );
    expect(llmDecisionCanaryScript, contains('visionDecision'));
    expect(llmDecisionCanaryScript, contains('safeTargetReasoning'));
    expect(llmDecisionCanaryScript, contains('requiresUserClick'));
    expect(llmDecisionCanaryScript, contains('no_desktop_action'));
    expect(llmDecisionCanaryScript, contains('llm_env_missing'));
    expect(llmDecisionCanaryScript, contains('computer_click'));
    expect(llmDecisionCanaryScript, contains('CAVERNO_LLM_BASE_URL'));
    expect(
      llmDecisionCanaryScript,
      contains(
        'Set CAVERNO_LLM_BASE_URL before running the macOS Computer Use LLM decision canary.',
      ),
    );
    expect(llmDecisionCanaryScript, contains('--fixture-response PATH'));
    expect(llmDecisionCanaryScript, contains('--empty-response-retries COUNT'));
    expect(llmDecisionCanaryScript, contains('llm_response_empty'));
    expect(llmDecisionCanaryScript, contains('emptyResponseRetries'));
    expect(llmDecisionCanaryScript, contains('llmAttemptCount'));
    expect(llmDecisionCanaryScript, contains('--scenario NAME'));
    expect(llmDecisionCanaryScript, contains('mvp-fixture'));
    expect(llmDecisionCanaryScript, contains('mvp-fixture-type-confirm'));
    expect(llmDecisionCanaryScript, contains('computer_use_mvp_fixture'));
    expect(
      llmDecisionCanaryScript,
      contains('computer_use_mvp_fixture_type_confirm'),
    );
    expect(llmDecisionCanaryScript, contains('Safe Click Target'));
    expect(llmDecisionCanaryScript, contains('MVP Fixture Text Field'));
    expect(llmDecisionCanaryScript, contains('requiresUserTextInput'));
    expect(llmDecisionCanaryScript, contains('Danger Zone'));
    expect(llmDecisionCanaryScript, contains('observe_action_observe_missing'));
    expect(releaseReadinessWrapper, contains('--llm-canary-scenario'));
    expect(
      releaseReadinessWrapper,
      contains(
        r'LLM_CANARY_SCENARIO="${CAVERNO_MACOS_COMPUTER_USE_LLM_CANARY_SCENARIO:-mvp-fixture-aggregate}"',
      ),
    );
    expect(releaseReadinessWrapper, contains('--llm-canary-summary'));
    expect(
      releaseReadinessWrapper,
      contains('tool/run_macos_computer_use_mvp_fixture_llm_canary.sh'),
    );
    expect(
      mvpFixtureLlmCanaryScript,
      contains('macos_computer_use_mvp_fixture_llm_canary_summary'),
    );
    expect(
      mvpFixtureLlmCanaryScript,
      contains(
        'Set CAVERNO_LLM_BASE_URL before running the macOS Computer Use MVP fixture LLM canary.',
      ),
    );
    expect(mvpFixtureLlmCanaryScript, contains('mvp-fixture'));
    expect(mvpFixtureLlmCanaryScript, contains('mvp-fixture-type-confirm'));
    expect(mvpFixtureLlmCanaryScript, contains('--fixture-response-click'));
    expect(mvpFixtureLlmCanaryScript, contains('--fixture-response-type'));
    expect(mvpFixtureLlmCanaryScript, contains('mvpEvidenceGate'));
    expect(mvpFixtureLlmCanaryScript, contains('safe_click_plan'));
    expect(mvpFixtureLlmCanaryScript, contains('type_confirm_plan'));
    expect(mvpFixtureLlmCanaryScript, contains('post_observe_required'));
    expect(mvpFixtureLlmCanaryScript, contains('destructive_refusal'));
    expect(
      mvpFixtureVisionLlmCanaryScript,
      contains('macos_computer_use_mvp_fixture_vision_llm_canary_summary'),
    );
    expect(mvpFixtureVisionLlmCanaryScript, contains('--screenshot PATH'));
    expect(mvpFixtureVisionLlmCanaryScript, contains('--latest-screenshot'));
    expect(
      mvpFixtureVisionLlmCanaryScript,
      contains('--desktop-action-report PATH'),
    );
    expect(mvpFixtureVisionLlmCanaryScript, contains('screenshotSource'));
    expect(
      mvpFixtureVisionLlmCanaryScript,
      contains('desktopActionReportPath'),
    );
    expect(
      mvpFixtureVisionLlmCanaryScript,
      contains('desktop_action_post_click_window_capture'),
    );
    expect(mvpFixtureVisionLlmCanaryScript, contains('image_url'));
    expect(
      mvpFixtureVisionLlmCanaryScript,
      contains('data:{mime_type};base64'),
    );
    expect(mvpFixtureVisionLlmCanaryScript, contains('visibleFixtureWindow'));
    expect(mvpFixtureVisionLlmCanaryScript, contains('requiresUserTextInput'));
    expect(mvpFixtureVisionLlmCanaryScript, contains('no_tcc_operation'));
    expect(mvpFixtureVisionLlmCanaryScript, contains('no_desktop_action'));
    expect(mvpFixtureVisionLlmCanaryScript, contains('failureGuidance'));
    expect(
      mvpFixtureVisionLlmCanaryScript,
      contains('fixture_window_not_visible'),
    );
    expect(
      mvpFixtureVisionLlmCanaryScript,
      contains('destructive_target_not_refused'),
    );
    expect(mvpFixtureVisionLlmCanaryScript, contains('mvpEvidenceGate'));
    expect(mvpFixtureVisionLlmCanaryScript, contains('safe_click_plan'));
    expect(mvpFixtureVisionLlmCanaryScript, contains('type_confirm_plan'));
    expect(mvpFixtureVisionLlmCanaryScript, contains('no_execution_claim'));
    expect(
      realAppObserveCanaryScript,
      contains('macos_computer_use_real_app_observe_canary_summary'),
    );
    expect(
      realAppObserveCanaryScript,
      contains('computer_use_real_app_observe'),
    );
    expect(realAppObserveCanaryScript, contains('--target-app NAME'));
    expect(realAppObserveCanaryScript, contains('--target-intent TEXT'));
    expect(realAppObserveCanaryScript, contains('no_tcc_operation'));
    expect(realAppObserveCanaryScript, contains('no_desktop_action'));
    expect(realAppObserveCanaryScript, contains('observationOnly'));
    expect(
      realAppObserveCanaryScript,
      contains('requiresUserApprovalBeforeAction'),
    );
    expect(realAppObserveCanaryScript, contains('public_action'));
    expect(realAppObserveCanaryScript, contains('executable_action_planned'));
    expect(realAppObserveCanaryScript, contains('m12EvidenceGate'));
    expect(realAppObserveCanaryScript, contains('m14EvidenceGate'));
    expect(realAppObserveCanaryScript, contains('confirmationRequirements'));
    expect(m14RealAppHandoffScript, contains('report-only'));
    expect(m14RealAppHandoffScript, contains('no TCC'));
    expect(m14RealAppHandoffScript, contains('no System Settings'));
    expect(m14RealAppHandoffScript, contains('no desktop actions'));
    expect(
      m14RealAppHandoffScript,
      contains('tool/run_macos_computer_use_real_app_observe_canary.sh'),
    );
    expect(
      m14RealAppHandoffScript,
      contains('tool/macos_computer_use_readiness_artifact_index.dart'),
    );
    expect(
      m14RealAppHandoffScript,
      contains('tool/run_macos_computer_use_mvp_signoff.sh'),
    );
    expect(m15ActionProposalHandoffScript, contains('report-only'));
    expect(m15ActionProposalHandoffScript, contains('no LLM call'));
    expect(m15ActionProposalHandoffScript, contains('no TCC'));
    expect(m15ActionProposalHandoffScript, contains('no System Settings'));
    expect(m15ActionProposalHandoffScript, contains('no desktop actions'));
    expect(m15ActionProposalHandoffScript, contains('m15ActionProposalGate'));
    expect(m15ActionProposalHandoffScript, contains('prReviewSummary'));
    expect(m15ActionProposalHandoffScript, contains('blockedReviewEvidence'));
    expect(m15ActionProposalHandoffScript, contains('requires_user_approval'));
    expect(
      mvpLlmReadinessScript,
      contains('macos_computer_use_mvp_llm_readiness_summary'),
    );
    expect(mvpLlmReadinessScript, contains('no_tcc_no_desktop_action'));
    expect(
      mvpLlmReadinessScript,
      contains('tool/run_macos_computer_use_mvp_fixture_llm_canary.sh'),
    );
    expect(
      mvpLlmReadinessScript,
      contains('tool/run_macos_computer_use_release_readiness.sh'),
    );
    expect(
      mvpLlmReadinessScript,
      contains('tool/run_macos_computer_use_mvp_signoff.sh'),
    );
    expect(mvpLlmReadinessScript, contains('--fixture-response-click'));
    expect(mvpLlmReadinessScript, contains('--fixture-response-type'));
    expect(mvpLlmReadinessScript, contains('--screenshot PATH'));
    expect(mvpLlmReadinessScript, contains('--latest-screenshot'));
    expect(mvpLlmReadinessScript, contains('--vision-fixture-response PATH'));
    expect(mvpLlmReadinessScript, contains('--llm-canary-summary PATH'));
    expect(
      mvpLlmReadinessScript,
      contains('tool/run_macos_computer_use_mvp_fixture_vision_llm_canary.sh'),
    );
    expect(
      mvpLlmReadinessScript,
      contains('macos_computer_use_mvp_fixture_vision_llm_canary_'),
    );
    expect(mvpLlmReadinessScript, contains('mvpEvidenceGate'));
    expect(
      mvpLlmReadinessScript,
      contains('expectedUserOperatedRuntimePhases'),
    );
    expect(
      mvpDemoReadinessScript,
      contains('macos_computer_use_mvp_demo_readiness_summary'),
    );
    expect(mvpDemoReadinessScript, contains('--screenshot PATH'));
    expect(mvpDemoReadinessScript, contains('--vision-fixture-response PATH'));
    expect(mvpDemoReadinessScript, contains('--manual-tcc-report PATH'));
    expect(
      mvpDemoReadinessScript,
      contains('--desktop-action-canary-summary PATH'),
    );
    expect(mvpDemoReadinessScript, contains('--final-signoff'));
    expect(mvpDemoReadinessScript, contains('--skip-fixture-build'));
    expect(
      mvpDemoReadinessScript,
      contains('tool/run_macos_computer_use_mvp_fixture.sh'),
    );
    expect(
      mvpDemoReadinessScript,
      contains('tool/run_macos_computer_use_mvp_llm_readiness.sh'),
    );
    expect(mvpDemoReadinessScript, contains('mvpEvidenceGate'));
    expect(
      mvpDemoReadinessScript,
      contains('expectedUserOperatedRuntimePhases'),
    );
    expect(
      mvpDemoReadinessScript,
      contains('tool/run_macos_computer_use_mvp_signoff.sh'),
    );

    final root = Directory.systemTemp.createTempSync(
      'caverno_llm_decision_canary_test_',
    );
    try {
      final fixture = File('${root.path}/fixture_response.json')
        ..writeAsStringSync('''
{
  "visionDecision": "Choose the empty document body.",
  "safeTargetReasoning": "The empty document body is a visible harmless target.",
  "requiresUserClick": true,
  "selectedTarget": {
    "label": "Empty document body",
    "risk": "low"
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_llm_decision_canary.sh',
        '--root',
        root.path,
        '--fixture-response',
        fixture.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('Requires user click: true'));

      final summaryDir = Directory(
        root.path,
      ).listSync().whereType<Directory>().single;
      final summaryFile = File('${summaryDir.path}/canary_summary.json');
      final summary = summaryFile.readAsStringSync();
      expect(
        summary,
        contains('macos_computer_use_llm_decision_canary_summary'),
      );
      expect(summary, contains('computer_use_llm_vision_decision'));
      expect(summary, contains('"requiresUserClick": true'));
      expect(summary, contains('"failedCount": 0'));
      expect(summary, contains('"desktopActionBoundary": "no_desktop_action"'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('Computer Use MVP fixture scenario validates action planning', () async {
    expect(
      mvpFixtureScript,
      contains('APP_NAME="Caverno Computer Use MVP Fixture"'),
    );
    expect(mvpFixtureScript, contains('swiftc'));
    expect(mvpFixtureScript, contains('--launch'));
    expect(mvpFixtureScript, contains('no TCC operation'));
    expect(mvpFixtureSource, contains('enum MvpFixtureMain'));
    expect(mvpFixtureSource, contains('application.run()'));
    expect(mvpFixtureSource, contains('window.orderFrontRegardless()'));
    expect(mvpFixtureSource, contains('safeClickTargetButton'));
    expect(mvpFixtureSource, contains('mvpInputField'));
    expect(mvpFixtureSource, contains('disabledDangerZoneButton'));
    expect(mvpFixtureSource, contains('statusLabel.stringValue = "Clicked"'));

    final root = Directory.systemTemp.createTempSync(
      'caverno_llm_mvp_fixture_canary_test_',
    );
    try {
      final fixture = File('${root.path}/fixture_response.json')
        ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture",
  "visionDecision": "Use the safe fixture button for the MVP click phase.",
  "safeTargetReasoning": "The Safe Click Target is a low-risk fixture control with a deterministic status update.",
  "requiresUserClick": true,
  "selectedTarget": {
    "label": "Safe Click Target",
    "risk": "low",
    "action": "click"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_click",
      "targetLabel": "Safe Click Target",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {
      "label": "Danger Zone",
      "reason": "The target is disabled and destructive."
    }
  ],
  "expectedOutcome": "The status label changes after the user-approved click."
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_llm_decision_canary.sh',
        '--root',
        root.path,
        '--scenario',
        'mvp-fixture',
        '--fixture-response',
        fixture.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('Scenario: mvp-fixture'));
      expect('${result.stdout}', contains('Safe Click Target'));

      final summaryDir = Directory(
        root.path,
      ).listSync().whereType<Directory>().single;
      final summaryFile = File('${summaryDir.path}/canary_summary.json');
      final summary = summaryFile.readAsStringSync();
      expect(summary, contains('"scenario": "mvp-fixture"'));
      expect(summary, contains('"fixtureApp"'));
      expect(summary, contains('Caverno Computer Use MVP Fixture'));
      expect(summary, contains('"failedCount": 0'));
      expect(summary, contains('"Safe Click Target"'));
      expect(summary, contains('"Danger Zone"'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'Computer Use MVP fixture type scenario validates text planning',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_llm_mvp_fixture_type_canary_test_',
      );
      try {
        final fixture = File('${root.path}/fixture_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture_type_confirm",
  "visionDecision": "Use the fixture text field and Echo Text button for the type-and-confirm phase.",
  "safeTargetReasoning": "The text field and Echo Text button are low-risk fixture controls with deterministic echo output.",
  "requiresUserClick": true,
  "requiresUserTextInput": true,
  "selectedTarget": {
    "label": "MVP Fixture Text Field",
    "risk": "low",
    "action": "type_text"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_type_text",
      "targetLabel": "MVP Fixture Text Field",
      "text": "caverno-mvp-canary",
      "requiresUserApproval": true
    },
    {
      "tool": "computer_click",
      "targetLabel": "Echo Text",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {
      "label": "Danger Zone",
      "reason": "The target is disabled and destructive."
    }
  ],
  "expectedOutcome": "Echo label changes after user-approved text input and echo click."
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_llm_decision_canary.sh',
          '--root',
          root.path,
          '--scenario',
          'mvp-fixture-type-confirm',
          '--fixture-response',
          fixture.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          '${result.stdout}',
          contains('Scenario: mvp-fixture-type-confirm'),
        );
        expect('${result.stdout}', contains('MVP Fixture Text Field'));

        final summaryDir = Directory(
          root.path,
        ).listSync().whereType<Directory>().single;
        final summary = File(
          '${summaryDir.path}/canary_summary.json',
        ).readAsStringSync();
        expect(summary, contains('"scenario": "mvp-fixture-type-confirm"'));
        expect(summary, contains('"requiresUserTextInput": true'));
        expect(summary, contains('"failedCount": 0'));
        expect(summary, contains('"MVP Fixture Text Field"'));
        expect(summary, contains('"Danger Zone"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use MVP fixture aggregate LLM canary runs both scenarios',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_fixture_llm_aggregate_test_',
      );
      try {
        final clickFixture = File('${root.path}/click_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture",
  "visionDecision": "Use the safe fixture button.",
  "safeTargetReasoning": "The Safe Click Target is a harmless fixture control.",
  "requiresUserClick": true,
  "selectedTarget": {
    "label": "Safe Click Target",
    "risk": "low",
    "action": "click"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_click",
      "targetLabel": "Safe Click Target",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {"label": "Danger Zone", "reason": "Disabled destructive target."}
  ],
  "expectedOutcome": "The status label changes after the user-approved click."
}
''');
        final typeFixture = File('${root.path}/type_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture_type_confirm",
  "visionDecision": "Use the fixture text field and Echo Text button.",
  "safeTargetReasoning": "The controls are low-risk fixture controls.",
  "requiresUserClick": true,
  "requiresUserTextInput": true,
  "selectedTarget": {
    "label": "MVP Fixture Text Field",
    "risk": "low",
    "action": "type_text"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_type_text",
      "targetLabel": "MVP Fixture Text Field",
      "text": "caverno-mvp-canary",
      "requiresUserApproval": true
    },
    {
      "tool": "computer_click",
      "targetLabel": "Echo Text",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {"label": "Danger Zone", "reason": "Disabled destructive target."}
  ],
  "expectedOutcome": "Echo label changes after user-approved text input and echo click."
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_fixture_llm_canary.sh',
          '--root',
          root.path,
          '--fixture-response-click',
          clickFixture.path,
          '--fixture-response-type',
          typeFixture.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('mvp-fixture'));
        expect('${result.stdout}', contains('mvp-fixture-type-confirm'));

        final summaryDir = Directory(
          root.path,
        ).listSync().whereType<Directory>().single;
        final summary = File(
          '${summaryDir.path}/canary_summary.json',
        ).readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_mvp_fixture_llm_canary_summary'),
        );
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"runCount": 2'));
        expect(summary, contains('"passed": 2'));
        expect(summary, contains('"failed": 0'));
        expect(summary, contains('"failedCount": 0'));
        expect(summary, contains('"requiresUserClick": true'));
        expect(summary, contains('"requiresUserTextInput": true'));
        expect(summary, contains('"mvpEvidenceGate"'));
        expect(summary, contains('"safe_click_plan"'));
        expect(summary, contains('"type_confirm_plan"'));
        expect(summary, contains('"observe_action_observe_plan"'));
        expect(summary, contains('"user_approval_boundary"'));
        expect(summary, contains('"destructive_refusal"'));
        expect(summary, contains('"post_observe_required"'));
        expect(summary, contains('"expectedUserOperatedRuntimePhases"'));
        expect(summary, contains('"pre_observe_image"'));
        expect(summary, contains('"click_sent"'));
        expect(summary, contains('"type_text_sent"'));
        expect(summary, contains('"post_observe_image"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use MVP LLM readiness runner wires canary to handoff',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_llm_readiness_test_',
      );
      try {
        final clickFixture = File('${root.path}/click_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture",
  "visionDecision": "Use the safe fixture button.",
  "safeTargetReasoning": "The Safe Click Target is a harmless fixture control.",
  "requiresUserClick": true,
  "selectedTarget": {
    "label": "Safe Click Target",
    "risk": "low",
    "action": "click"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_click",
      "targetLabel": "Safe Click Target",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {"label": "Danger Zone", "reason": "Disabled destructive target."}
  ],
  "expectedOutcome": "The status label changes after the user-approved click."
}
''');
        final typeFixture = File('${root.path}/type_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture_type_confirm",
  "visionDecision": "Use the fixture text field and Echo Text button.",
  "safeTargetReasoning": "The controls are low-risk fixture controls.",
  "requiresUserClick": true,
  "requiresUserTextInput": true,
  "selectedTarget": {
    "label": "MVP Fixture Text Field",
    "risk": "low",
    "action": "type_text"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_type_text",
      "targetLabel": "MVP Fixture Text Field",
      "text": "caverno-mvp-canary",
      "requiresUserApproval": true
    },
    {
      "tool": "computer_click",
      "targetLabel": "Echo Text",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {"label": "Danger Zone", "reason": "Disabled destructive target."}
  ],
  "expectedOutcome": "Echo label changes after user-approved text input and echo click."
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_llm_readiness.sh',
          '--root',
          root.path,
          '--fixture-response-click',
          clickFixture.path,
          '--fixture-response-type',
          typeFixture.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('LLM gate ready: true'));
        expect('${result.stdout}', contains('manual_tcc'));
        expect('${result.stdout}', contains('desktop_action_canary'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => file.path.endsWith('mvp_llm_readiness_summary.json'),
            )
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_mvp_llm_readiness_summary'),
        );
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"llmReady": true'));
        expect(summary, contains('"llmGateReady": true'));
        expect(summary, contains('"mvpEvidenceGate"'));
        expect(summary, contains('"safe_click_plan"'));
        expect(summary, contains('"type_confirm_plan"'));
        expect(summary, contains('"expectedUserOperatedRuntimePhases"'));
        expect(summary, contains('"destructive_target_refused"'));
        expect(summary, contains('"manual_tcc"'));
        expect(summary, contains('"desktop_action_canary"'));
        expect(summary, contains(_manualTccNextAction));
        expect(summary, contains(_desktopActionNextAction));

        final handoffFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('mvp_llm_handoff.md'))
            .toList(growable: false);
        expect(handoffFiles, hasLength(1));
        final handoff = handoffFiles.single.readAsStringSync();
        expect(handoff, contains('Manual TCC status: not provided'));
        expect(handoff, contains('Desktop action canary status: not provided'));
        expect(handoff, contains('LLM canary status: provided'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use MVP LLM readiness runner accepts vision canary evidence',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_llm_readiness_vision_test_',
      );
      try {
        final previousVisionRun = Directory(
          '${root.path}/macos_computer_use_mvp_fixture_vision_llm_canary_1',
        )..createSync();
        final latestScreenshot = File(
          '${previousVisionRun.path}/desktop_action_post_click_window_capture_screenshot.png',
        )..writeAsBytesSync([137, 80, 78, 71, 13, 10, 26, 10]);
        final fixture = File('${root.path}/vision_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture_vision",
  "visionDecision": "The fixture window is visible with safe click, text, echo, and disabled danger controls.",
  "visibleFixtureWindow": true,
  "safeTargetReasoning": "Safe Click Target, MVP Fixture Text Field, and Echo Text are low-risk fixture controls.",
  "requiresUserClick": true,
  "requiresUserTextInput": true,
  "selectedTarget": {
    "label": "Safe Click Target",
    "risk": "low",
    "action": "click"
  },
  "typeConfirmTarget": {
    "label": "MVP Fixture Text Field",
    "confirmationButton": "Echo Text",
    "action": "type_text_then_confirm"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_click",
      "targetLabel": "Safe Click Target",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_type_text",
      "targetLabel": "MVP Fixture Text Field",
      "text": "caverno-mvp-canary",
      "requiresUserApproval": true
    },
    {
      "tool": "computer_click",
      "targetLabel": "Echo Text",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {"label": "Danger Zone", "reason": "Disabled destructive target."}
  ],
  "expectedOutcome": "User-approved actions update the fixture labels."
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_llm_readiness.sh',
          '--root',
          root.path,
          '--latest-screenshot',
          '--vision-fixture-response',
          fixture.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('LLM gate ready: true'));
        expect(
          '${result.stdout}',
          contains('LLM evidence mode: fixture_vision'),
        );
        expect('${result.stdout}', contains('Latest screenshot: 1'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => file.path.endsWith('mvp_llm_readiness_summary.json'),
            )
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"llmEvidenceMode": "fixture_vision"'));
        expect(summary, contains('computer_use_mvp_fixture_vision_llm_canary'));
        expect(summary, contains('"llmReady": true'));
        expect(summary, contains('"llmGateReady": true'));
        expect(summary, contains('"mvpEvidenceGate"'));
        expect(summary, contains('"fixture_window_visible"'));
        expect(summary, contains('"no_execution_claim"'));

        final visionSummaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('canary_summary.json'))
            .toList(growable: false);
        expect(visionSummaryFiles, hasLength(1));
        final visionSummary = visionSummaryFiles.single.readAsStringSync();
        expect(
          visionSummary,
          contains('"screenshotPath": "${latestScreenshot.path}"'),
        );
        expect(
          visionSummary,
          contains('"screenshotSource": "user_screenshot"'),
        );

        final handoffFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('mvp_llm_handoff.md'))
            .toList(growable: false);
        expect(handoffFiles, hasLength(1));
        final handoff = handoffFiles.single.readAsStringSync();
        expect(handoff, contains('LLM canary status: provided'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('Computer Use MVP demo readiness wrapper guides the full handoff', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_demo_readiness_test_',
    );
    try {
      final fixture = File('${root.path}/vision_response.json')
        ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture_vision",
  "visionDecision": "The fixture window is visible with safe click, text, echo, and disabled danger controls.",
  "visibleFixtureWindow": true,
  "safeTargetReasoning": "Safe Click Target, MVP Fixture Text Field, and Echo Text are low-risk fixture controls.",
  "requiresUserClick": true,
  "requiresUserTextInput": true,
  "selectedTarget": {
    "label": "Safe Click Target",
    "risk": "low",
    "action": "click"
  },
  "typeConfirmTarget": {
    "label": "MVP Fixture Text Field",
    "confirmationButton": "Echo Text",
    "action": "type_text_then_confirm"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_click",
      "targetLabel": "Safe Click Target",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_type_text",
      "targetLabel": "MVP Fixture Text Field",
      "text": "caverno-mvp-canary",
      "requiresUserApproval": true
    },
    {
      "tool": "computer_click",
      "targetLabel": "Echo Text",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {"label": "Danger Zone", "reason": "Disabled destructive target."}
  ],
  "expectedOutcome": "User-approved actions update the fixture labels."
}
''');
      final desktopActionSummary = File('${root.path}/desktop_action.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_desktop_action_canary_summary",
  "stable": true,
  "runCount": 1,
  "failed": 0,
  "expectedPhases": [
    "pre_observe_image",
    "click_sent",
    "post_observe_image"
  ],
  "safeTargetGuidance": [
    "Use a visible, harmless target.",
    "Avoid destructive controls."
  ],
  "runs": [
    {
      "name": "run_01",
      "status": "passed",
      "failureClass": "passed",
      "phaseStatus": {
        "preObserve": "ready",
        "click": "sent",
        "postObserve": "ready",
        "changedEvidence": "observed"
      }
    }
  ]
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_demo_readiness.sh',
        '--root',
        root.path,
        '--skip-fixture-build',
        '--vision-fixture-response',
        fixture.path,
        '--desktop-action-canary-summary',
        desktopActionSummary.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect('${result.stdout}', contains('MVP demo readiness summary'));

      final summaryFiles = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith('mvp_demo_readiness_summary.json'),
          )
          .toList(growable: false);
      expect(summaryFiles, hasLength(1));
      final summary = summaryFiles.single.readAsStringSync();
      expect(
        summary,
        contains('macos_computer_use_mvp_demo_readiness_summary'),
      );
      expect(summary, contains('"ready": true'));
      expect(summary, contains('"llmReadinessExitCode": 0'));
      expect(
        summary,
        contains('macos_computer_use_mvp_fixture_vision_llm_canary'),
      );
      expect(summary, contains('"llmEvidenceMode": "fixture_vision"'));
      expect(summary, contains('"llmGateReady": true'));
      expect(summary, contains('"mvpEvidenceGate"'));
      expect(summary, contains('"fixture_window_visible"'));
      expect(summary, contains('"expectedUserOperatedRuntimePhases"'));
      expect(summary, contains('"desktopActionEvidence"'));
      expect(summary, contains('"status": "passed"'));
      expect(summary, contains('"changedEvidence": "observed"'));
      expect(summary, contains('"prReviewArtifacts"'));
      expect(summary, contains('"reviewSection": "PR Review Summary"'));
      expect(
        summary,
        contains('macos_computer_use_readiness_artifact_index.md'),
      );
      expect(summary, contains(_manualTccNextAction));

      final handoffFiles = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('mvp_demo_handoff.md'))
          .toList(growable: false);
      expect(handoffFiles, hasLength(1));
      final handoff = handoffFiles.single.readAsStringSync();
      expect(handoff, contains('MVP Evidence Checks'));
      expect(handoff, contains('Expected User-Operated Runtime Phases'));
      expect(handoff, contains('Desktop Action Evidence'));
      expect(handoff, contains('Desktop action status: passed'));
      expect(handoff, contains('PR Review Artifacts'));
      expect(handoff, contains('Review section: `PR Review Summary`'));
      expect(
        handoff,
        contains('macos_computer_use_readiness_artifact_index.md'),
      );
      expect(
        handoff,
        contains(
          'dart run tool/macos_computer_use_readiness_artifact_index.dart --root ${root.path}',
        ),
      );
      expect(handoff, contains('`pre_observe_image`'));
      expect(handoff, contains('Use a visible, harmless target.'));
      expect(handoff, contains('| run_01 | passed | passed |'));
      expect(handoff, contains('| ready | sent | ready | observed |'));
      expect(handoff, contains('User-Operated Commands'));
      expect(
        handoff,
        contains('bash tool/run_macos_computer_use_manual_tcc_signoff.sh'),
      );
      expect(
        handoff,
        contains(
          'bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target',
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'Computer Use MVP fixture vision LLM canary validates screenshot decisions',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_fixture_vision_llm_test_',
      );
      try {
        final fixture = File('${root.path}/vision_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture_vision",
  "visionDecision": "The fixture window is visible with safe click, text, echo, and disabled danger controls.",
  "visibleFixtureWindow": true,
  "safeTargetReasoning": "Safe Click Target, MVP Fixture Text Field, and Echo Text are low-risk fixture controls.",
  "requiresUserClick": true,
  "requiresUserTextInput": true,
  "selectedTarget": {
    "label": "Safe Click Target",
    "risk": "low",
    "action": "click"
  },
  "typeConfirmTarget": {
    "label": "MVP Fixture Text Field",
    "confirmationButton": "Echo Text",
    "action": "type_text_then_confirm"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_click",
      "targetLabel": "Safe Click Target",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_type_text",
      "targetLabel": "MVP Fixture Text Field",
      "text": "caverno-mvp-canary",
      "requiresUserApproval": true
    },
    {
      "tool": "computer_click",
      "targetLabel": "Echo Text",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {"label": "Danger Zone", "reason": "Disabled destructive target."}
  ],
  "expectedOutcome": "User-approved actions update the fixture labels."
}
''');
        final desktopActionReport = File('${root.path}/desktop_action.json')
          ..writeAsStringSync('''
{
  "steps": [
    {
      "id": "desktop_action_post_click_window_capture",
      "response": {
        "imageBase64": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lx7B2wAAAABJRU5ErkJggg=="
      }
    }
  ]
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_fixture_vision_llm_canary.sh',
          '--root',
          root.path,
          '--desktop-action-report',
          desktopActionReport.path,
          '--fixture-response',
          fixture.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Visible fixture window: true'));
        expect('${result.stdout}', contains('Requires user text input: true'));

        final summaryDir = Directory(
          root.path,
        ).listSync().whereType<Directory>().single;
        final summary = File(
          '${summaryDir.path}/canary_summary.json',
        ).readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_mvp_fixture_vision_llm_canary_summary'),
        );
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"visibleFixtureWindow": true'));
        expect(summary, contains('"requiresUserClick": true'));
        expect(summary, contains('"requiresUserTextInput": true'));
        expect(summary, contains('"screenshotSource"'));
        expect(summary, contains('"desktopActionReportPath"'));
        expect(summary, contains('"llmRequest"'));
        expect(summary, contains('"mode": "fixture_response"'));
        expect(summary, contains('"fixtureResponsePath": "${fixture.path}"'));
        expect(summary, isNot(contains('no-key')));
        expect(summary, contains('"failureGuidance"'));
        expect(summary, contains('"actionPlan"'));
        expect(summary, contains('"expectedOutcome"'));
        expect(summary, contains('"mvpEvidenceGate"'));
        expect(summary, contains('"fixture_window_visible"'));
        expect(summary, contains('"safe_click_plan"'));
        expect(summary, contains('"type_confirm_plan"'));
        expect(summary, contains('"no_execution_claim"'));
        expect(summary, contains('"expectedUserOperatedRuntimePhases"'));
        expect(summary, contains('"Safe Click Target"'));
        expect(summary, contains('"MVP Fixture Text Field"'));
        expect(summary, contains('"Danger Zone"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use MVP fixture vision LLM canary discovers latest screenshot',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_fixture_vision_latest_test_',
      );
      try {
        final previousRun = Directory(
          '${root.path}/macos_computer_use_mvp_fixture_vision_llm_canary_1',
        )..createSync();
        final latestScreenshot = File(
          '${previousRun.path}/desktop_action_post_click_window_capture_screenshot.png',
        )..writeAsBytesSync([137, 80, 78, 71, 13, 10, 26, 10]);
        final fixture = File('${root.path}/vision_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_mvp_fixture_vision",
  "visionDecision": "All required fixture controls are visible.",
  "visibleFixtureWindow": true,
  "safeTargetReasoning": "Safe Click Target, MVP Fixture Text Field, and Echo Text are low-risk fixture controls.",
  "requiresUserClick": true,
  "requiresUserTextInput": true,
  "selectedTarget": {
    "label": "Safe Click Target",
    "risk": "low",
    "action": "click"
  },
  "typeConfirmTarget": {
    "label": "MVP Fixture Text Field",
    "confirmationButton": "Echo Text",
    "action": "type_text_then_confirm"
  },
  "actionPlan": [
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_click",
      "targetLabel": "Safe Click Target",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"},
    {
      "tool": "computer_type_text",
      "targetLabel": "MVP Fixture Text Field",
      "text": "caverno-mvp-canary",
      "requiresUserApproval": true
    },
    {
      "tool": "computer_click",
      "targetLabel": "Echo Text",
      "requiresUserApproval": true
    },
    {"tool": "computer_vision_observe"}
  ],
  "refusedTargets": [
    {"label": "Danger Zone", "reason": "Disabled destructive target."}
  ],
  "expectedOutcome": "User-approved actions update the fixture labels."
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_fixture_vision_llm_canary.sh',
          '--root',
          root.path,
          '--latest-screenshot',
          '--fixture-response',
          fixture.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Ready: true'));
        expect(
          '${result.stdout}',
          contains('Screenshot: ${latestScreenshot.path}'),
        );

        final summaryDirs = Directory(root.path)
            .listSync()
            .whereType<Directory>()
            .where((dir) => dir.path != previousRun.path)
            .toList();
        expect(summaryDirs, hasLength(1));
        final summary = File(
          '${summaryDirs.single.path}/canary_summary.json',
        ).readAsStringSync();
        expect(
          summary,
          contains('"screenshotPath": "${latestScreenshot.path}"'),
        );
        expect(summary, contains('"screenshotSource": "user_screenshot"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use real app observe canary validates observe-only evidence',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_real_app_observe_canary_test_',
      );
      try {
        final fixture = File('${root.path}/real_app_observe_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_real_app_observe",
  "visionDecision": "Safari is visible on X with compose and post controls that require explicit approval before use.",
  "targetApp": "Safari",
  "observedApp": "Safari",
  "visibleAppWindow": true,
  "pageOrDocument": "X home timeline",
  "loggedInStateVisible": "visible",
  "observationOnly": true,
  "requiresUserApprovalBeforeAction": true,
  "candidateTargets": [
    {
      "label": "Address Bar",
      "role": "address_bar",
      "risk": "input",
      "reason": "Changing the URL would navigate the browser."
    },
    {
      "label": "What's happening?",
      "role": "compose_text_field",
      "risk": "input",
      "reason": "Typing here prepares public content."
    },
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action",
      "reason": "Pressing it would publish content."
    }
  ],
  "blockedActions": [
    "Do not click any target in this observe-only canary.",
    "Do not type into the compose field in this observe-only canary.",
    "Do not post public content in this observe-only canary."
  ],
  "confirmationRequirements": [
    "Ask the user to approve the exact post text before typing.",
    "Ask the user to approve the final public Post control before publishing."
  ],
  "actionPlan": [
    {"tool": "computer_vision_observe"}
  ],
  "recommendedNextStep": "Ask the user for explicit approval before any future input or public action."
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_real_app_observe_canary.sh',
          '--root',
          root.path,
          '--fixture-response',
          fixture.path,
          '--target-app',
          'Safari',
          '--target-intent',
          'Observe Safari for a future X post task.',
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Ready: true'));
        expect('${result.stdout}', contains('Observed app: Safari'));
        expect('${result.stdout}', contains('Candidate targets: 3'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('canary_summary.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_real_app_observe_canary_summary'),
        );
        expect(summary, contains('"milestone": "M14"'));
        expect(summary, contains('"previousMilestone": "M12"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"observedApp": "Safari"'));
        expect(summary, contains('"observationOnly": true'));
        expect(summary, contains('"requiresUserApprovalBeforeAction": true'));
        expect(summary, contains('"confirmationRequirements"'));
        expect(summary, contains('"risk": "public_action"'));
        expect(summary, contains('"m12EvidenceGate"'));
        expect(summary, contains('"m14EvidenceGate"'));
        expect(summary, contains('"confirmation_requirements_documented"'));
        expect(summary, contains('"observe_only_boundary"'));
        expect(summary, contains('"public_action_classification"'));
        expect(summary, isNot(contains('computer_click')));
        expect(summary, isNot(contains('computer_type_text')));
        expect(summary, isNot(contains('no-key')));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use real app observe canary blocks M14 unsafe evidence',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_real_app_observe_canary_blocked_test_',
      );
      try {
        final fixture = File('${root.path}/real_app_observe_blocked.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_real_app_observe",
  "visionDecision": "Safari is visible and the Post control is available.",
  "targetApp": "Safari",
  "observedApp": "Safari",
  "visibleAppWindow": true,
  "pageOrDocument": "X home timeline",
  "loggedInStateVisible": "visible",
  "observationOnly": true,
  "requiresUserApprovalBeforeAction": true,
  "candidateTargets": [
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action",
      "reason": "Pressing it would publish content."
    }
  ],
  "blockedActions": [
    "Do not click, type, or post in this observe-only canary."
  ],
  "actionPlan": [
    {"tool": "computer_click"}
  ],
  "recommendedNextStep": "Ask for approval before any future action."
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_real_app_observe_canary.sh',
          '--root',
          root.path,
          '--fixture-response',
          fixture.path,
          '--target-app',
          'Safari',
          '--target-intent',
          'Observe Safari for a future X post task.',
        ]);

        expect(
          result.exitCode,
          1,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Ready: false'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('canary_summary.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"ready": false'));
        expect(summary, contains('"m14EvidenceGate"'));
        expect(summary, contains('"text_field_target_missing"'));
        expect(summary, contains('"confirmation_requirements_missing"'));
        expect(summary, contains('"executable_action_planned"'));
        expect(summary, contains('"text_field_targets_classified"'));
        expect(summary, contains('"confirmation_requirements_documented"'));
        expect(summary, contains('"observe_only_no_mutation"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M15 action proposal handoff consumes ready M14 evidence',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m15_action_proposal_handoff_test_',
      );
      try {
        final m14Summary = File('${root.path}/m14_canary_summary.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_real_app_observe_canary_summary",
  "milestone": "M14",
  "ready": true,
  "targetApp": "Safari",
  "observedApp": "Safari",
  "targetIntent": "Observe Safari for a future X post task.",
  "exactText": "Good morning from Caverno",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "candidateTargets": [
    {
      "label": "What's happening?",
      "role": "compose_text_field",
      "risk": "input",
      "reason": "Typing here prepares public content."
    },
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action",
      "reason": "Pressing it would publish content."
    }
  ],
  "confirmationRequirements": [
    "Ask the user to approve the exact post text before typing.",
    "Ask the user to approve the final public Post control before publishing."
  ],
  "actionPlan": [
    {"tool": "computer_vision_observe"}
  ],
  "m14EvidenceGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m15_action_proposal_handoff.sh',
          '--root',
          root.path,
          '--m14-summary',
          m14Summary.path,
          '--target-intent',
          'Prepare an approval-bound plan for a future X post with exact text "Good morning from Caverno".',
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Ready: true'));
        expect('${result.stdout}', contains('Text-entry targets: 1'));
        expect('${result.stdout}', contains('Public-action targets: 1'));
        expect('${result.stdout}', contains('Exact text candidates: 1'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('action_proposal_handoff.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m15_action_proposal_handoff'),
        );
        expect(summary, contains('"milestone": "M15"'));
        expect(summary, contains('"previousMilestone": "M14"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"llmBoundary": "no_llm_call"'));
        expect(
          summary,
          contains('"desktopActionBoundary": "no_desktop_action"'),
        );
        expect(summary, contains('"tccBoundary": "no_tcc_operation"'));
        expect(summary, contains('"m15ActionProposalGate"'));
        expect(summary, contains('"prReviewSummary"'));
        expect(summary, contains('"reviewGateConsistency"'));
        expect(summary, contains('"status": "ready_for_review"'));
        expect(summary, contains('"status": "consistent"'));
        expect(summary, contains('"blockedReviewEvidence": []'));
        expect(summary, contains('"futureActions": "approval_required"'));
        expect(
          summary,
          contains('"publicActions": "separate_approval_required"'),
        );
        expect(summary, contains('"confirm_exact_text"'));
        expect(summary, contains('"confirm_target"'));
        expect(summary, contains('"confirm_public_action"'));
        expect(summary, contains('"requires_separate_user_approval"'));
        expect(summary, contains('"exactTextCandidates"'));
        expect(summary, contains('"reviewTargetCounts"'));
        expect(summary, contains('"textEntryTargets": 1'));
        expect(summary, contains('"publicActionTargets": 1'));
        expect(summary, contains('"exactTextCandidates": 1'));
        expect(summary, contains('"confirmationRequirements": 2'));
        expect(summary, contains('"Good morning from Caverno"'));
        expect(summary, contains('"textEntryTargets"'));
        expect(summary, contains('"publicActionTargets"'));
        expect(summary, isNot(contains('computer_click')));
        expect(summary, isNot(contains('computer_type_text')));

        final markdownFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('action_proposal_handoff.md'))
            .toList(growable: false);
        expect(markdownFiles, hasLength(1));
        final markdown = markdownFiles.single.readAsStringSync();
        expect(markdown, contains('## PR Review Summary'));
        expect(markdown, contains('- Status: ready_for_review'));
        expect(markdown, contains('- Blocked review evidence: none'));
        expect(markdown, contains('- Review/gate consistency: consistent'));
        expect(
          markdown,
          contains(
            '- Review target counts: candidateTargets=2, textEntryTargets=1, publicActionTargets=1, exactTextCandidates=1, confirmationRequirements=2',
          ),
        );
        expect(
          markdown,
          contains(
            '- Required confirmations: observe_again, confirm_exact_text, confirm_target, confirm_public_action',
          ),
        );
        expect(markdown, contains('## Review Targets'));
        expect(
          markdown,
          contains('| What\'s happening? | compose_text_field | input |'),
        );
        expect(markdown, contains('| Post | public_submit | public_action |'));
        expect(
          markdown,
          contains(
            '| Good morning from Caverno | exactText | requires_user_approval |',
          ),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M15 action proposal handoff blocks unsafe M14 evidence',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m15_action_proposal_blocked_test_',
      );
      try {
        final m14Summary = File('${root.path}/m14_blocked_summary.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_real_app_observe_canary_summary",
  "milestone": "M14",
  "ready": true,
  "targetApp": "Safari",
  "observedApp": "Safari",
  "targetIntent": "Observe Safari for a future X post task.",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "candidateTargets": [
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action",
      "reason": "Pressing it would publish content."
    }
  ],
  "confirmationRequirements": [],
  "actionPlan": [
    {"tool": "computer_click"}
  ],
  "m14EvidenceGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m15_action_proposal_handoff.sh',
          '--root',
          root.path,
          '--m14-summary',
          m14Summary.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Ready: false'));
        expect('${result.stdout}', contains('text_entry_targets_available'));
        expect(
          '${result.stdout}',
          contains('confirmation_requirements_available'),
        );
        expect('${result.stdout}', contains('no_mutating_tool_planned'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('action_proposal_handoff.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"ready": false'));
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"prReviewSummary"'));
        expect(summary, contains('"reviewGateConsistency"'));
        expect(summary, contains('"reviewTargetCounts"'));
        expect(summary, contains('"candidateTargets": 1'));
        expect(summary, contains('"textEntryTargets": 0'));
        expect(summary, contains('"publicActionTargets": 1'));
        expect(
          summary,
          contains('"status": "blocked_pending_review_evidence"'),
        );
        expect(summary, contains('"status": "consistent"'));
        expect(summary, contains('"blockedReviewEvidence"'));
        expect(summary, contains('"text_entry_targets_available"'));
        expect(summary, contains('"confirmation_requirements_available"'));
        expect(summary, contains('"no_mutating_tool_planned"'));

        final markdownFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('action_proposal_handoff.md'))
            .toList(growable: false);
        expect(markdownFiles, hasLength(1));
        final markdown = markdownFiles.single.readAsStringSync();
        expect(markdown, contains('## PR Review Summary'));
        expect(markdown, contains('- Status: blocked_pending_review_evidence'));
        expect(markdown, contains('- Review/gate consistency: consistent'));
        expect(
          markdown,
          contains(
            '- Blocked review evidence: text_entry_targets_available, confirmation_requirements_available, no_mutating_tool_planned',
          ),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M15 LLM review canary preserves approval boundaries',
    () async {
      expect(
        m15LlmReviewCanaryScript,
        contains('macos_computer_use_m15_llm_review_canary_summary'),
      );
      expect(m15LlmReviewCanaryScript, contains('Boundary: report-only'));
      expect(m15LlmReviewCanaryScript, contains('no_desktop_action'));
      expect(m15LlmReviewCanaryScript, contains('no_tcc_operation'));
      expect(
        m15LlmReviewCanaryScript,
        contains('review_only_no_tool_execution'),
      );

      final root = Directory.systemTemp.createTempSync(
        'caverno_m15_llm_review_canary_test_',
      );
      try {
        final handoffDir = Directory(
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_1',
        )..createSync();
        final handoff = File('${handoffDir.path}/action_proposal_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "ready": true,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "reviewTargetCounts": {
    "candidateTargets": 2,
    "textEntryTargets": 1,
    "publicActionTargets": 1,
    "exactTextCandidates": 1,
    "confirmationRequirements": 2
  },
  "m15ActionProposalGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');
        final fixtureResponse = File('${root.path}/llm_response.json')
          ..writeAsStringSync('''
{
  "scenarioName": "computer_use_m15_action_proposal_review",
  "reviewDecision": "The handoff is report-only and future execution must wait for user approvals.",
  "boundaryDecision": "approval_required_before_action",
  "noImmediateExecution": true,
  "noDesktopAction": true,
  "noTccOperation": true,
  "noSystemSettingsOperation": true,
  "approvalRequiredPhases": [
    "observe_again",
    "confirm_exact_text",
    "confirm_target",
    "confirm_public_action"
  ],
  "blockedActions": [
    "click",
    "type",
    "navigate",
    "submit",
    "post",
    "purchase",
    "grant_tcc",
    "operate_system_settings"
  ],
  "nextAction": "Ask the user to approve exact text, target, and public action before any future execution."
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m15_llm_review_canary.sh',
          '--root',
          root.path,
          '--handoff',
          handoff.path,
          '--fixture-response',
          fixtureResponse.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect('${result.stdout}', contains('approval_required_before_action'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('canary_summary.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m15_llm_review_canary_summary'),
        );
        expect(
          summary,
          contains('"purpose": "computer_use_m15_llm_review_canary"'),
        );
        expect(summary, contains('"milestone": "M15"'));
        expect(
          summary,
          contains('"desktopActionBoundary": "no_desktop_action"'),
        );
        expect(summary, contains('"tccBoundary": "no_tcc_operation"'));
        expect(
          summary,
          contains('"llmBoundary": "review_only_no_tool_execution"'),
        );
        expect(
          summary,
          contains('"boundaryDecision": "approval_required_before_action"'),
        );
        expect(summary, contains('"m15LlmReviewGate"'));
        expect(summary, contains('"status": "ready"'));
        expect(summary, contains('"failedCount": 0'));
        expect(summary, contains('"confirm_exact_text"'));
        expect(summary, contains('"confirm_target"'));
        expect(summary, contains('"confirm_public_action"'));
        expect(summary, contains('"grant_tcc"'));
        expect(summary, contains('"operate_system_settings"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('Computer Use M15 LLM review canary blocks execution claims', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_m15_llm_review_canary_blocked_test_',
    );
    try {
      final handoff = File('${root.path}/action_proposal_handoff.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "ready": true,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action"
}
''');
      final fixtureResponse = File('${root.path}/llm_response.json')
        ..writeAsStringSync('''
{
  "scenarioName": "computer_use_m15_action_proposal_review",
  "reviewDecision": "I clicked the Post button and posted successfully.",
  "boundaryDecision": "execute_now",
  "noImmediateExecution": false,
  "noDesktopAction": false,
  "noTccOperation": true,
  "noSystemSettingsOperation": true,
  "approvalRequiredPhases": [],
  "blockedActions": [],
  "executeNow": true
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_m15_llm_review_canary.sh',
        '--root',
        root.path,
        '--handoff',
        handoff.path,
        '--fixture-response',
        fixtureResponse.path,
      ]);

      expect(result.exitCode, 1);
      expect('${result.stdout}', contains('Gate status: blocked'));
      final summaryFiles = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('canary_summary.json'))
          .toList(growable: false);
      expect(summaryFiles, hasLength(1));
      final summary = summaryFiles.single.readAsStringSync();
      expect(summary, contains('"failedCount": 1'));
      expect(summary, contains('"status": "blocked"'));
      expect(summary, contains('"approval_boundary_missing"'));
      expect(summary, contains('"unsafe_execution_claim"'));
      expect(summary, contains('"immediate_execution_enabled"'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'Computer Use M16 approval packet consumes ready M15 evidence',
    () async {
      expect(
        m16ApprovalPacketScript,
        contains('macos_computer_use_m16_approval_packet'),
      );
      expect(m16ApprovalPacketScript, contains('report-only'));
      expect(m16ApprovalPacketScript, contains('no desktop actions'));
      expect(m16ApprovalPacketScript, contains('approvalBlockers'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m16_approval_packet_test_',
      );
      try {
        final handoffDir = Directory(
          '${root.path}/macos_computer_use_m15_action_proposal_handoff_1',
        )..createSync();
        final handoff = File('${handoffDir.path}/action_proposal_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "ready": true,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "targetIntent": "Prepare an approval-bound X post.",
  "candidateTargets": [
    {"label": "Post text field", "role": "text_entry", "risk": "low"},
    {"label": "Post", "role": "public_submit", "risk": "public_action"}
  ],
  "textEntryTargets": [
    {"label": "Post text field", "role": "text_entry", "risk": "low"}
  ],
  "publicActionTargets": [
    {"label": "Post", "role": "public_submit", "risk": "public_action"}
  ],
  "exactTextCandidates": [
    {
      "source": "targetIntent",
      "text": "Good morning from Caverno",
      "status": "requires_user_approval"
    }
  ],
  "confirmationRequirements": [
    "Ask the user to approve the exact post text.",
    "Ask the user to approve the public submit action."
  ],
  "reviewTargetCounts": {
    "candidateTargets": 2,
    "textEntryTargets": 1,
    "publicActionTargets": 1,
    "exactTextCandidates": 1,
    "confirmationRequirements": 2
  },
  "prReviewSummary": {
    "status": "ready_for_review",
    "ready": true,
    "blockedReviewEvidence": []
  },
  "reviewGateConsistency": {
    "ok": true,
    "status": "consistent"
  },
  "m15ActionProposalGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');
        final reviewDir = Directory(
          '${root.path}/macos_computer_use_m15_llm_review_canary_1',
        )..createSync();
        final llmReview = File('${reviewDir.path}/canary_summary.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_llm_review_canary_summary",
  "milestone": "M15",
  "ready": true,
  "m15LlmReviewGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m16_approval_packet.sh',
          '--root',
          root.path,
          '--m15-handoff',
          handoff.path,
          '--m15-llm-review',
          llmReview.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains('Approval status: pending_user_approval'),
        );

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('approval_packet.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('macos_computer_use_m16_approval_packet'));
        expect(summary, contains('"milestone": "M16"'));
        expect(summary, contains('"previousMilestone": "M15"'));
        expect(
          summary,
          contains('"executionBoundary": "no_desktop_action_report_only"'),
        );
        expect(summary, contains('"approvalStatus": "pending_user_approval"'));
        expect(summary, contains('"m16ApprovalPacketGate"'));
        expect(summary, contains('"status": "ready"'));
        expect(summary, contains('"approvalBlockers"'));
        expect(summary, contains('"exact_text"'));
        expect(summary, contains('"target_label"'));
        expect(summary, contains('"public_action_label"'));
        expect(summary, contains('"post_action_observation"'));
        expect(summary, contains('"Good morning from Caverno"'));
        expect(summary, contains('"Post text field"'));
        expect(summary, contains('"Post"'));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M16 Approval Packet'));
        expect(markdown, contains('Required Approvals'));
        expect(markdown, contains('pending_user_approval'));
        expect(markdown, contains('Manual Boundary'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M16 approval packet blocks unready M15 evidence',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m16_approval_packet_blocked_test_',
      );
      try {
        final handoff = File('${root.path}/action_proposal_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "ready": false,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "reviewGateConsistency": {
    "ok": false,
    "status": "inconsistent"
  },
  "m15ActionProposalGate": {
    "status": "blocked",
    "ready": false,
    "blockers": ["m14_evidence_ready"]
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m16_approval_packet.sh',
          '--root',
          root.path,
          '--m15-handoff',
          handoff.path,
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('approval_packet.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"m15_handoff_ready"'));
        expect(summary, contains('"m15_review_gate_consistent"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M17 execution rehearsal consumes approved M16 packet',
    () async {
      expect(
        m17ExecutionRehearsalScript,
        contains('macos_computer_use_m17_execution_rehearsal'),
      );
      expect(m17ExecutionRehearsalScript, contains('report-only'));
      expect(m17ExecutionRehearsalScript, contains('no desktop actions'));
      expect(m17ExecutionRehearsalScript, contains('approval_status_approved'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m17_execution_rehearsal_test_',
      );
      try {
        final packetDir = Directory(
          '${root.path}/macos_computer_use_m16_approval_packet_1',
        )..createSync();
        final packet = File('${packetDir.path}/approval_packet.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m16_approval_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m16_approval_packet",
  "milestone": "M16",
  "previousMilestone": "M15",
  "ready": true,
  "approvalStatus": "approved",
  "executionBoundary": "no_desktop_action_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "exactTextCandidates": [
    {
      "source": "targetIntent",
      "text": "Good morning from Caverno",
      "status": "requires_user_approval"
    }
  ],
  "textEntryTargets": [
    {
      "label": "Post text field",
      "role": "text_entry",
      "risk": "low"
    }
  ],
  "publicActionTargets": [
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action"
    }
  ],
  "approvedValues": {
    "exactText": "Good morning from Caverno",
    "targetLabel": "Post text field",
    "publicActionLabel": "Post"
  },
  "requiredApprovals": [
    {
      "id": "exact_text",
      "required": true,
      "status": "approved",
      "approvedValue": "Good morning from Caverno"
    },
    {
      "id": "target_label",
      "required": true,
      "status": "approved",
      "approvedValue": "Post text field"
    },
    {
      "id": "public_action_label",
      "required": true,
      "status": "approved",
      "approvedValue": "Post"
    }
  ],
  "approvalBlockers": [],
  "m16ApprovalPacketGate": {
    "status": "ready",
    "ready": true,
    "blockers": [],
    "approvalStatus": "approved",
    "approvalBlockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m17_execution_rehearsal.sh',
          '--root',
          root.path,
          '--m16-packet',
          packet.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains('Execution boundary: no_desktop_action_report_only'),
        );

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('execution_rehearsal.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('macos_computer_use_m17_execution_rehearsal'));
        expect(summary, contains('"milestone": "M17"'));
        expect(summary, contains('"previousMilestone": "M16"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m17ExecutionRehearsalGate"'));
        expect(summary, contains('"status": "ready"'));
        expect(summary, contains('"executionPhases"'));
        expect(summary, contains('"type_exact_text"'));
        expect(summary, contains('"confirm_public_action"'));
        expect(summary, contains('"Good morning from Caverno"'));
        expect(summary, contains('"Post text field"'));
        expect(summary, contains('"Post"'));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M17 Execution Rehearsal'));
        expect(markdown, contains('Report-Only Boundary'));
        expect(markdown, contains('Good morning from Caverno'));
        expect(markdown, contains('future_user_approved_input'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M17 execution rehearsal blocks pending approvals',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m17_execution_rehearsal_blocked_test_',
      );
      try {
        final packet = File('${root.path}/approval_packet.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m16_approval_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m16_approval_packet",
  "milestone": "M16",
  "ready": true,
  "approvalStatus": "pending_user_approval",
  "executionBoundary": "no_desktop_action_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "exactTextCandidates": [
    {
      "source": "targetIntent",
      "text": "Good morning from Caverno",
      "status": "requires_user_approval"
    }
  ],
  "textEntryTargets": [
    {
      "label": "Post text field",
      "role": "text_entry",
      "risk": "low"
    }
  ],
  "publicActionTargets": [
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action"
    }
  ],
  "approvalBlockers": ["exact_text", "target_label", "public_action_label"],
  "m16ApprovalPacketGate": {
    "status": "ready",
    "ready": true,
    "blockers": [],
    "approvalStatus": "pending_user_approval",
    "approvalBlockers": ["exact_text", "target_label", "public_action_label"]
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m17_execution_rehearsal.sh',
          '--root',
          root.path,
          '--m16-packet',
          packet.path,
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('approval_status_approved'));
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('execution_rehearsal.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"approval_status_approved"'));
        expect(summary, contains('"exact_text_approved"'));
        expect(summary, contains('"target_label_approved"'));
        expect(summary, contains('"public_action_label_approved"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M18 execution handoff consumes ready M17 rehearsal',
    () async {
      expect(
        m18ExecutionHandoffScript,
        contains('macos_computer_use_m18_execution_handoff'),
      );
      expect(m18ExecutionHandoffScript, contains('report-only'));
      expect(m18ExecutionHandoffScript, contains('user-operated'));
      expect(m18ExecutionHandoffScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m18_execution_handoff_test_',
      );
      try {
        final rehearsalDir = Directory(
          '${root.path}/macos_computer_use_m17_execution_rehearsal_1',
        )..createSync();
        final rehearsal = File('${rehearsalDir.path}/execution_rehearsal.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m17_execution_rehearsal",
  "schemaVersion": 1,
  "purpose": "computer_use_m17_execution_rehearsal",
  "milestone": "M17",
  "previousMilestone": "M16",
  "ready": true,
  "executionBoundary": "no_desktop_action_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "approvedValues": {
    "exactText": "Good morning from Caverno",
    "targetLabel": "Post text field",
    "publicActionLabel": "Post"
  },
  "executionPhases": [
    {
      "id": "observe_again",
      "mode": "read_only",
      "approved": true
    },
    {
      "id": "focus_target",
      "mode": "future_user_approved_desktop_action",
      "approved": true,
      "approvedValue": "Post text field"
    },
    {
      "id": "type_exact_text",
      "mode": "future_user_approved_input",
      "approved": true,
      "approvedValue": "Good morning from Caverno"
    },
    {
      "id": "confirm_public_action",
      "mode": "future_separate_user_approved_public_action",
      "approved": true,
      "approvedValue": "Post"
    },
    {
      "id": "post_action_observation",
      "mode": "read_only_after_future_action",
      "approved": true
    }
  ],
  "m17ExecutionRehearsalGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m18_execution_handoff.sh',
          '--root',
          root.path,
          '--m17-rehearsal',
          rehearsal.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains('Execution boundary: user_operated_runtime_handoff'),
        );

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('execution_handoff.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('macos_computer_use_m18_execution_handoff'));
        expect(summary, contains('"milestone": "M18"'));
        expect(summary, contains('"previousMilestone": "M17"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m18ExecutionHandoffGate"'));
        expect(summary, contains('"status": "ready"'));
        expect(summary, contains('"actionTimeConfirmations"'));
        expect(summary, contains('"executionChecklist"'));
        expect(summary, contains('"confirm_exact_text_at_action_time"'));
        expect(summary, contains('"confirm_public_action_at_action_time"'));
        expect(summary, contains('"Good morning from Caverno"'));
        expect(summary, contains('"Post text field"'));
        expect(summary, contains('"Post"'));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M18 Execution Handoff'));
        expect(markdown, contains('Action-Time Confirmations'));
        expect(markdown, contains('User-Operated Checklist'));
        expect(markdown, contains('Good morning from Caverno'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('Computer Use M18 execution handoff blocks unready rehearsal', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_m18_execution_handoff_blocked_test_',
    );
    try {
      final rehearsal = File('${root.path}/execution_rehearsal.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m17_execution_rehearsal",
  "schemaVersion": 1,
  "purpose": "computer_use_m17_execution_rehearsal",
  "milestone": "M17",
  "ready": false,
  "executionBoundary": "no_desktop_action_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "approvedValues": {},
  "executionPhases": [
    {
      "id": "type_exact_text",
      "mode": "future_user_approved_input",
      "approved": false
    }
  ],
  "m17ExecutionRehearsalGate": {
    "status": "blocked",
    "ready": false,
    "blockers": ["approval_status_approved"]
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_m18_execution_handoff.sh',
        '--root',
        root.path,
        '--m17-rehearsal',
        rehearsal.path,
      ]);

      expect(result.exitCode, 1);
      expect('${result.stdout}', contains('Gate status: blocked'));
      expect('${result.stdout}', contains('m17_rehearsal_ready'));
      final summaryFiles = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('execution_handoff.json'))
          .toList(growable: false);
      expect(summaryFiles, hasLength(1));
      final summary = summaryFiles.single.readAsStringSync();
      expect(summary, contains('"status": "blocked"'));
      expect(summary, contains('"m17_rehearsal_ready"'));
      expect(summary, contains('"exact_text_confirmation_ready"'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'Computer Use M20 execution result intake consumes manual result',
    () async {
      expect(
        m20ExecutionResultIntakeScript,
        contains('macos_computer_use_m20_execution_result_intake'),
      );
      expect(m20ExecutionResultIntakeScript, contains('report-only'));
      expect(m20ExecutionResultIntakeScript, contains('user-reported'));
      expect(m20ExecutionResultIntakeScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m20_execution_result_intake_test_',
      );
      try {
        final handoffDir = Directory(
          '${root.path}/macos_computer_use_m18_execution_handoff_1',
        )..createSync();
        final handoff = File('${handoffDir.path}/execution_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m18_execution_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m18_execution_handoff",
  "milestone": "M18",
  "previousMilestone": "M17",
  "ready": true,
  "executionBoundary": "user_operated_runtime_handoff",
  "desktopActionBoundary": "user_operated_only",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "publicActionRequiresSeparateApproval": true,
  "approvedValues": {
    "exactText": "Good morning from Caverno",
    "targetLabel": "Post text field",
    "publicActionLabel": "Post"
  },
  "actionTimeConfirmations": [
    {
      "id": "fresh_observation",
      "required": true,
      "approvedBeforeRun": false
    },
    {
      "id": "target_label",
      "required": true,
      "approvedBeforeRun": true,
      "approvedValue": "Post text field"
    },
    {
      "id": "exact_text",
      "required": true,
      "approvedBeforeRun": true,
      "approvedValue": "Good morning from Caverno"
    },
    {
      "id": "public_action_label",
      "required": true,
      "approvedBeforeRun": true,
      "approvedValue": "Post"
    }
  ],
  "executionChecklist": [
    {
      "id": "pre_execution_observe"
    },
    {
      "id": "focus_target"
    },
    {
      "id": "type_exact_text"
    },
    {
      "id": "public_action"
    },
    {
      "id": "post_action_observation"
    }
  ],
  "m18ExecutionHandoffGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m20_execution_result_intake.sh',
          '--root',
          root.path,
          '--m18-handoff',
          handoff.path,
          '--fresh-observation',
          'done',
          '--target-confirmed',
          'yes',
          '--exact-text-confirmed',
          'yes',
          '--public-action-confirmed',
          'yes',
          '--runtime-action',
          'succeeded',
          '--post-action-observation',
          'done',
          '--operator-note',
          'Manual runtime step completed by the user.',
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains('Execution boundary: manual_result_intake_report_only'),
        );

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('execution_result_intake.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m20_execution_result_intake'),
        );
        expect(summary, contains('"milestone": "M20"'));
        expect(summary, contains('"previousMilestone": "M18"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m20ExecutionResultIntakeGate"'));
        expect(summary, contains('"runtimeAction": "succeeded"'));
        expect(summary, contains('"postActionObservation": "done"'));
        expect(summary, contains('"Good morning from Caverno"'));
        expect(summary, contains('"Post text field"'));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M20 Execution Result Intake'));
        expect(markdown, contains('User-Reported Result Sequence'));
        expect(
          markdown,
          contains('Manual runtime step completed by the user.'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M20 execution result intake blocks missing result',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m20_execution_result_intake_blocked_test_',
      );
      try {
        final handoff = File('${root.path}/execution_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m18_execution_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m18_execution_handoff",
  "milestone": "M18",
  "ready": true,
  "executionBoundary": "user_operated_runtime_handoff",
  "desktopActionBoundary": "user_operated_only",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "publicActionRequiresSeparateApproval": false,
  "approvedValues": {
    "exactText": "Good morning from Caverno",
    "targetLabel": "Post text field"
  },
  "actionTimeConfirmations": [
    {
      "id": "target_label",
      "required": true,
      "approvedBeforeRun": true
    },
    {
      "id": "exact_text",
      "required": true,
      "approvedBeforeRun": true
    }
  ],
  "executionChecklist": [],
  "m18ExecutionHandoffGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m20_execution_result_intake.sh',
          '--root',
          root.path,
          '--m18-handoff',
          handoff.path,
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('fresh_observation_recorded'));
        expect('${result.stdout}', contains('runtime_action_succeeded'));
        expect(
          '${result.stdout}',
          contains('post_action_observation_recorded'),
        );
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('execution_result_intake.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"fresh_observation_recorded"'));
        expect(summary, contains('"target_confirmation_recorded"'));
        expect(summary, contains('"runtimeAction": "not-run"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M22 post-action review consumes ready M20 result',
    () async {
      expect(
        m22PostActionReviewScript,
        contains('macos_computer_use_m22_post_action_review'),
      );
      expect(m22PostActionReviewScript, contains('report-only'));
      expect(m22PostActionReviewScript, contains('user-reported'));
      expect(m22PostActionReviewScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m22_post_action_review_test_',
      );
      try {
        final intake = File('${root.path}/execution_result_intake.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m20_execution_result_intake",
  "schemaVersion": 1,
  "purpose": "computer_use_m20_execution_result_intake",
  "milestone": "M20",
  "ready": true,
  "executionBoundary": "manual_result_intake_report_only",
  "desktopActionBoundary": "user_operated_evidence_only",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "approvedValues": {
    "exactText": "Good morning from Caverno",
    "targetLabel": "Post text field",
    "publicActionLabel": "Post"
  },
  "manualInputs": {
    "runtimeAction": "succeeded",
    "postActionObservation": "done"
  },
  "m20ExecutionResultIntakeGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m22_post_action_review.sh',
          '--root',
          root.path,
          '--m20-intake',
          intake.path,
          '--result-reviewed',
          'yes',
          '--post-action-state',
          'stable',
          '--follow-up-required',
          'no',
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains('Execution boundary: post_action_review_report_only'),
        );
        expect(
          '${result.stdout}',
          contains('Next cycle recommendation: no_follow_up'),
        );

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('post_action_review.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('macos_computer_use_m22_post_action_review'));
        expect(summary, contains('"milestone": "M22"'));
        expect(summary, contains('"previousMilestone": "M20"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m22PostActionReviewGate"'));
        expect(summary, contains('"resultReviewed": "yes"'));
        expect(summary, contains('"postActionState": "stable"'));
        expect(summary, contains('"nextCycleRecommendation": "no_follow_up"'));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M22 Post-Action Review'));
        expect(markdown, contains('Review Inputs'));
        expect(markdown, contains('Source Result'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M22 post-action review blocks unreviewed result',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m22_post_action_review_blocked_test_',
      );
      try {
        final intake = File('${root.path}/execution_result_intake.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m20_execution_result_intake",
  "schemaVersion": 1,
  "purpose": "computer_use_m20_execution_result_intake",
  "milestone": "M20",
  "ready": true,
  "executionBoundary": "manual_result_intake_report_only",
  "desktopActionBoundary": "user_operated_evidence_only",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "manualInputs": {
    "runtimeAction": "succeeded",
    "postActionObservation": "done"
  },
  "m20ExecutionResultIntakeGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m22_post_action_review.sh',
          '--root',
          root.path,
          '--m20-intake',
          intake.path,
          '--follow-up-required',
          'yes',
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('result_reviewed'));
        expect('${result.stdout}', contains('post_action_state_known'));
        expect(
          '${result.stdout}',
          contains('follow_up_note_recorded_when_required'),
        );
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('post_action_review.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"resultReviewed": "no"'));
        expect(summary, contains('"postActionState": "unknown"'));
        expect(
          summary,
          contains(
            '"nextCycleRecommendation": "start_new_observe_action_cycle"',
          ),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M23 cycle outcome handoff closes reviewed cycles',
    () async {
      expect(
        m23CycleOutcomeHandoffScript,
        contains('macos_computer_use_m23_cycle_outcome_handoff'),
      );
      expect(m23CycleOutcomeHandoffScript, contains('report-only'));
      expect(m23CycleOutcomeHandoffScript, contains('ready M22'));
      expect(m23CycleOutcomeHandoffScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m23_cycle_outcome_handoff_test_',
      );
      try {
        final review = File('${root.path}/post_action_review.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m22_post_action_review",
  "schemaVersion": 1,
  "purpose": "computer_use_m22_post_action_review",
  "milestone": "M22",
  "ready": true,
  "executionBoundary": "post_action_review_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "nextCycleRecommendation": "no_follow_up",
  "reviewInputs": {
    "resultReviewed": "yes",
    "postActionState": "stable",
    "followUpRequired": "no"
  },
  "sourceManualInputs": {
    "runtimeAction": "succeeded",
    "postActionObservation": "done"
  },
  "m22PostActionReviewGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh',
          '--root',
          root.path,
          '--m22-review',
          review.path,
          '--outcome-accepted',
          'yes',
          '--next-observe-needed',
          'no',
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains('Execution boundary: cycle_outcome_report_only'),
        );
        expect('${result.stdout}', contains('Cycle outcome: closed'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('cycle_outcome_handoff.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m23_cycle_outcome_handoff'),
        );
        expect(summary, contains('"milestone": "M23"'));
        expect(summary, contains('"previousMilestone": "M22"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m23CycleOutcomeHandoffGate"'));
        expect(summary, contains('"outcomeAccepted": "yes"'));
        expect(summary, contains('"nextObserveNeeded": "no"'));
        expect(summary, contains('"cycleOutcome": "closed"'));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M23 Cycle Outcome Handoff'));
        expect(markdown, contains('Handoff Inputs'));
        expect(markdown, contains('Next Observe Seed'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M23 cycle outcome handoff blocks inconsistent restart',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m23_cycle_outcome_handoff_blocked_test_',
      );
      try {
        final review = File('${root.path}/post_action_review.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m22_post_action_review",
  "schemaVersion": 1,
  "purpose": "computer_use_m22_post_action_review",
  "milestone": "M22",
  "ready": true,
  "executionBoundary": "post_action_review_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "nextCycleRecommendation": "start_new_observe_action_cycle",
  "reviewInputs": {
    "resultReviewed": "yes",
    "postActionState": "needs-follow-up",
    "followUpRequired": "yes"
  },
  "sourceManualInputs": {
    "runtimeAction": "succeeded",
    "postActionObservation": "done"
  },
  "m22PostActionReviewGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh',
          '--root',
          root.path,
          '--m22-review',
          review.path,
          '--outcome-accepted',
          'no',
          '--next-observe-needed',
          'no',
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('outcome_accepted'));
        expect(
          '${result.stdout}',
          contains('next_observe_matches_m22_recommendation'),
        );
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('cycle_outcome_handoff.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"outcomeAccepted": "no"'));
        expect(summary, contains('"nextObserveNeeded": "no"'));
        expect(summary, contains('"cycleOutcome": "unknown"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M25 next-cycle seed handoff freezes M14 restart seed',
    () async {
      expect(
        m25NextCycleSeedHandoffScript,
        contains('macos_computer_use_m25_next_cycle_seed_handoff'),
      );
      expect(m25NextCycleSeedHandoffScript, contains('report-only'));
      expect(m25NextCycleSeedHandoffScript, contains('ready M23'));
      expect(m25NextCycleSeedHandoffScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m25_next_cycle_seed_handoff_test_',
      );
      try {
        final handoff = File('${root.path}/cycle_outcome_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m23_cycle_outcome_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m23_cycle_outcome_handoff",
  "milestone": "M23",
  "previousMilestone": "M22",
  "ready": true,
  "executionBoundary": "cycle_outcome_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "cycleOutcome": "restart_observe_action_cycle",
  "handoffInputs": {
    "outcomeAccepted": "yes",
    "nextObserveNeeded": "yes"
  },
  "nextObserveSeed": {
    "required": true,
    "source": "m23_cycle_outcome_handoff",
    "note": "Observe the fresh compose target before proposing text.",
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action"
  },
  "m23CycleOutcomeHandoffGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh',
          '--root',
          root.path,
          '--m23-handoff',
          handoff.path,
          '--seed-accepted',
          'yes',
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains('Execution boundary: next_cycle_seed_report_only'),
        );
        expect(
          '${result.stdout}',
          contains('Observe the fresh compose target before proposing text.'),
        );

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('next_cycle_seed_handoff.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m25_next_cycle_seed_handoff'),
        );
        expect(summary, contains('"milestone": "M25"'));
        expect(summary, contains('"previousMilestone": "M23"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m25NextCycleSeedHandoffGate"'));
        expect(summary, contains('"seedAccepted": "yes"'));
        expect(summary, contains('"returnMilestone": "M14"'));
        expect(summary, contains('"observe_only_no_desktop_action"'));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M25 Next-Cycle Seed Handoff'));
        expect(markdown, contains('Next-Cycle Seed'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M25 next-cycle seed handoff blocks closed cycles',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m25_next_cycle_seed_handoff_blocked_test_',
      );
      try {
        final handoff = File('${root.path}/cycle_outcome_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m23_cycle_outcome_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m23_cycle_outcome_handoff",
  "milestone": "M23",
  "previousMilestone": "M22",
  "ready": true,
  "executionBoundary": "cycle_outcome_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "cycleOutcome": "closed",
  "handoffInputs": {
    "outcomeAccepted": "yes",
    "nextObserveNeeded": "no"
  },
  "nextObserveSeed": {
    "required": false,
    "source": "m23_cycle_outcome_handoff",
    "note": "",
    "returnMilestone": null,
    "boundary": "observe_only_no_desktop_action"
  },
  "m23CycleOutcomeHandoffGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh',
          '--root',
          root.path,
          '--m23-handoff',
          handoff.path,
          '--seed-accepted',
          'yes',
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('m23_restart_cycle'));
        expect('${result.stdout}', contains('next_observe_seed_required'));
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('next_cycle_seed_handoff.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"sourceCycleOutcome": "closed"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M26 observe restart packet prepares M14 commands',
    () async {
      expect(
        m26ObserveRestartPacketScript,
        contains('macos_computer_use_m26_observe_restart_packet'),
      );
      expect(m26ObserveRestartPacketScript, contains('report-only'));
      expect(m26ObserveRestartPacketScript, contains('ready M25'));
      expect(m26ObserveRestartPacketScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m26_observe_restart_packet_test_',
      );
      try {
        final handoff = File('${root.path}/next_cycle_seed_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m25_next_cycle_seed_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m25_next_cycle_seed_handoff",
  "milestone": "M25",
  "previousMilestone": "M23",
  "ready": true,
  "executionBoundary": "next_cycle_seed_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "seedInputs": {
    "seedAccepted": "yes"
  },
  "nextCycleSeed": {
    "required": true,
    "source": "m25_next_cycle_seed_handoff",
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "note": "Observe the fresh compose target before proposing text.",
    "requiresNewApprovalCycle": true
  },
  "m25NextCycleSeedHandoffGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m26_observe_restart_packet.sh',
          '--root',
          root.path,
          '--m25-handoff',
          handoff.path,
          '--target-app',
          'Safari',
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains(
            'Execution boundary: m14_observe_restart_packet_report_only',
          ),
        );
        expect(
          '${result.stdout}',
          contains('tool/run_macos_computer_use_real_app_observe_canary.sh'),
        );

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('observe_restart_packet.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m26_observe_restart_packet'),
        );
        expect(summary, contains('"milestone": "M26"'));
        expect(summary, contains('"previousMilestone": "M25"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m26ObserveRestartPacketGate"'));
        expect(summary, contains('"returnMilestone": "M14"'));
        expect(summary, contains('"targetApp": "Safari"'));
        expect(
          summary,
          contains('Observe the fresh compose target before proposing text.'),
        );
        expect(
          summary,
          contains('tool/run_macos_computer_use_m14_real_app_handoff.sh'),
        );
        expect(
          summary,
          contains('tool/run_macos_computer_use_real_app_observe_canary.sh'),
        );

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M26 Observe Restart Packet'));
        expect(markdown, contains('M14 observe-only canary'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M26 observe restart packet blocks unready M25 seed',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m26_observe_restart_packet_blocked_test_',
      );
      try {
        final handoff = File('${root.path}/next_cycle_seed_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m25_next_cycle_seed_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m25_next_cycle_seed_handoff",
  "milestone": "M25",
  "previousMilestone": "M23",
  "ready": false,
  "executionBoundary": "next_cycle_seed_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "seedInputs": {
    "seedAccepted": "no"
  },
  "nextCycleSeed": {
    "required": true,
    "source": "m25_next_cycle_seed_handoff",
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "note": "Observe the next target.",
    "requiresNewApprovalCycle": true
  },
  "m25NextCycleSeedHandoffGate": {
    "status": "blocked",
    "ready": false,
    "blockers": ["seed_accepted"]
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m26_observe_restart_packet.sh',
          '--root',
          root.path,
          '--m25-handoff',
          handoff.path,
          '--target-app',
          'Safari',
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('m25_handoff_ready'));
        expect('${result.stdout}', contains('m25_seed_accepted'));
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('observe_restart_packet.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"seedAccepted": "no"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M27 screenshot request handoff prepares manual request',
    () async {
      expect(
        m27ScreenshotRequestHandoffScript,
        contains('macos_computer_use_m27_screenshot_request_handoff'),
      );
      expect(m27ScreenshotRequestHandoffScript, contains('report-only'));
      expect(m27ScreenshotRequestHandoffScript, contains('ready M26'));
      expect(m27ScreenshotRequestHandoffScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m27_screenshot_request_handoff_test_',
      );
      try {
        final packet = File('${root.path}/observe_restart_packet.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m26_observe_restart_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m26_observe_restart_packet",
  "milestone": "M26",
  "previousMilestone": "M25",
  "ready": true,
  "executionBoundary": "m14_observe_restart_packet_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "Safari",
  "targetIntent": "Observe the fresh compose target before proposing text.",
  "nextObservePreparation": {
    "required": true,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "Safari",
    "targetIntent": "Observe the fresh compose target before proposing text.",
    "screenshotRequired": true,
    "screenshotProvided": false
  },
  "commands": {
    "m14RealAppHandoff": "bash tool/run_macos_computer_use_m14_real_app_handoff.sh --root ${root.path}",
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --root ${root.path} --screenshot <user-provided-real-app-screenshot.png>"
  },
  "m26ObserveRestartPacketGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m27_screenshot_request_handoff.sh',
          '--root',
          root.path,
          '--m26-packet',
          packet.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains('Execution boundary: manual_screenshot_request_report_only'),
        );
        expect(
          '${result.stdout}',
          contains('tool/run_macos_computer_use_real_app_observe_canary.sh'),
        );

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => file.path.endsWith('screenshot_request_handoff.json'),
            )
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m27_screenshot_request_handoff'),
        );
        expect(summary, contains('"milestone": "M27"'));
        expect(summary, contains('"previousMilestone": "M26"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m27ScreenshotRequestHandoffGate"'));
        expect(summary, contains('"returnMilestone": "M14"'));
        expect(summary, contains('"targetApp": "Safari"'));
        expect(summary, contains('"required": true'));
        expect(
          summary,
          contains('Observe the fresh compose target before proposing text.'),
        );

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M27 Screenshot Request Handoff'));
        expect(markdown, contains('User Screenshot Request'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M27 screenshot request handoff blocks unready M26 packet',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m27_screenshot_request_handoff_blocked_test_',
      );
      try {
        final packet = File('${root.path}/observe_restart_packet.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m26_observe_restart_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m26_observe_restart_packet",
  "milestone": "M26",
  "previousMilestone": "M25",
  "ready": false,
  "executionBoundary": "m14_observe_restart_packet_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "",
  "targetIntent": "Observe the next target.",
  "nextObservePreparation": {
    "required": true,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "",
    "targetIntent": "Observe the next target.",
    "screenshotRequired": true,
    "screenshotProvided": false
  },
  "commands": {},
  "m26ObserveRestartPacketGate": {
    "status": "blocked",
    "ready": false,
    "blockers": ["target_app_present"]
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m27_screenshot_request_handoff.sh',
          '--root',
          root.path,
          '--m26-packet',
          packet.path,
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('m26_packet_ready'));
        expect('${result.stdout}', contains('target_app_present'));
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => file.path.endsWith('screenshot_request_handoff.json'),
            )
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"target_app_present"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M28 screenshot evidence intake prepares M14 input',
    () async {
      expect(
        m28ScreenshotEvidenceIntakeScript,
        contains('macos_computer_use_m28_screenshot_evidence_intake'),
      );
      expect(m28ScreenshotEvidenceIntakeScript, contains('report-only'));
      expect(m28ScreenshotEvidenceIntakeScript, contains('ready M27'));
      expect(m28ScreenshotEvidenceIntakeScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m28_screenshot_evidence_intake_test_',
      );
      try {
        final screenshot = File('${root.path}/target.png')
          ..writeAsBytesSync(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
        final handoff = File('${root.path}/screenshot_request_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m27_screenshot_request_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m27_screenshot_request_handoff",
  "milestone": "M27",
  "previousMilestone": "M26",
  "ready": true,
  "executionBoundary": "manual_screenshot_request_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "Safari",
  "targetIntent": "Observe the fresh compose target before proposing text.",
  "userScreenshotRequest": {
    "required": true,
    "provided": false,
    "targetApp": "Safari",
    "targetIntent": "Observe the fresh compose target before proposing text.",
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action"
  },
  "commands": {
    "m14RealAppHandoff": "bash tool/run_macos_computer_use_m14_real_app_handoff.sh --root ${root.path}",
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --root ${root.path} --screenshot <user-provided-real-app-screenshot.png>"
  },
  "m27ScreenshotRequestHandoffGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh',
          '--root',
          root.path,
          '--m27-handoff',
          handoff.path,
          '--screenshot',
          screenshot.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains(
            'Execution boundary: manual_screenshot_evidence_intake_report_only',
          ),
        );
        expect('${result.stdout}', contains('Screenshot bytes: 8'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => file.path.endsWith('screenshot_evidence_intake.json'),
            )
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m28_screenshot_evidence_intake'),
        );
        expect(summary, contains('"milestone": "M28"'));
        expect(summary, contains('"previousMilestone": "M27"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m28ScreenshotEvidenceIntakeGate"'));
        expect(summary, contains('"returnMilestone": "M14"'));
        expect(summary, contains('"targetApp": "Safari"'));
        expect(summary, contains('"sizeBytes": 8'));
        expect(summary, contains(screenshot.path));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M28 Screenshot Evidence Intake'));
        expect(markdown, contains('Next Observe Input'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M28 screenshot evidence intake blocks unready M27 handoff',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m28_screenshot_evidence_intake_blocked_test_',
      );
      try {
        final screenshot = File('${root.path}/target.png')
          ..writeAsBytesSync(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
        final handoff = File('${root.path}/screenshot_request_handoff.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m27_screenshot_request_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m27_screenshot_request_handoff",
  "milestone": "M27",
  "previousMilestone": "M26",
  "ready": false,
  "executionBoundary": "manual_screenshot_request_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "",
  "targetIntent": "Observe the next target.",
  "userScreenshotRequest": {
    "required": true,
    "provided": false,
    "targetApp": "",
    "targetIntent": "Observe the next target.",
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action"
  },
  "commands": {},
  "m27ScreenshotRequestHandoffGate": {
    "status": "blocked",
    "ready": false,
    "blockers": ["target_app_present"]
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh',
          '--root',
          root.path,
          '--m27-handoff',
          handoff.path,
          '--screenshot',
          screenshot.path,
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('m27_handoff_ready'));
        expect('${result.stdout}', contains('target_app_present'));
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => file.path.endsWith('screenshot_evidence_intake.json'),
            )
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"target_app_present"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M29 observe canary run packet prepares M14 command',
    () async {
      expect(
        m29ObserveCanaryRunPacketScript,
        contains('macos_computer_use_m29_observe_canary_run_packet'),
      );
      expect(m29ObserveCanaryRunPacketScript, contains('report-only'));
      expect(m29ObserveCanaryRunPacketScript, contains('ready M28'));
      expect(m29ObserveCanaryRunPacketScript, contains('no desktop actions'));

      final root = Directory.systemTemp.createTempSync(
        'caverno_m29_observe_canary_run_packet_test_',
      );
      try {
        final screenshot = File('${root.path}/target.png')
          ..writeAsBytesSync(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
        final intake = File('${root.path}/screenshot_evidence_intake.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m28_screenshot_evidence_intake",
  "schemaVersion": 1,
  "purpose": "computer_use_m28_screenshot_evidence_intake",
  "milestone": "M28",
  "previousMilestone": "M27",
  "ready": true,
  "executionBoundary": "manual_screenshot_evidence_intake_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "Safari",
  "targetIntent": "Observe the fresh compose target before proposing text.",
  "screenshotEvidence": {
    "path": "${screenshot.path}",
    "exists": true,
    "sizeBytes": 8,
    "extension": ".png",
    "source": "user_provided"
  },
  "nextObserveInput": {
    "required": true,
    "provided": true,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "Safari",
    "targetIntent": "Observe the fresh compose target before proposing text.",
    "screenshotPath": "${screenshot.path}"
  },
  "commands": {
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --root ${root.path} --screenshot ${screenshot.path}"
  },
  "m28ScreenshotEvidenceIntakeGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m29_observe_canary_run_packet.sh',
          '--root',
          root.path,
          '--m28-intake',
          intake.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect('${result.stdout}', contains('Gate status: ready'));
        expect(
          '${result.stdout}',
          contains(
            'Execution boundary: m14_observe_canary_run_packet_report_only',
          ),
        );
        expect('${result.stdout}', contains('Screenshot bytes: 8'));

        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => file.path.endsWith('observe_canary_run_packet.json'),
            )
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(
          summary,
          contains('macos_computer_use_m29_observe_canary_run_packet'),
        );
        expect(summary, contains('"milestone": "M29"'));
        expect(summary, contains('"previousMilestone": "M28"'));
        expect(summary, contains('"ready": true'));
        expect(summary, contains('"m29ObserveCanaryRunPacketGate"'));
        expect(summary, contains('"returnMilestone": "M14"'));
        expect(summary, contains('"userOperated": true'));
        expect(summary, contains('"targetApp": "Safari"'));
        expect(summary, contains('"sizeBytes": 8'));
        expect(summary, contains(screenshot.path));

        final markdown = File(
          summaryFiles.single.path.replaceAll('.json', '.md'),
        ).readAsStringSync();
        expect(markdown, contains('M29 Observe Canary Run Packet'));
        expect(markdown, contains('Command For User'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'Computer Use M29 observe canary run packet blocks unready M28 intake',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m29_observe_canary_run_packet_blocked_test_',
      );
      try {
        final screenshot = File('${root.path}/target.png')
          ..writeAsBytesSync(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
        final intake = File('${root.path}/screenshot_evidence_intake.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m28_screenshot_evidence_intake",
  "schemaVersion": 1,
  "purpose": "computer_use_m28_screenshot_evidence_intake",
  "milestone": "M28",
  "previousMilestone": "M27",
  "ready": false,
  "executionBoundary": "manual_screenshot_evidence_intake_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "",
  "targetIntent": "Observe the next target.",
  "screenshotEvidence": {
    "path": "${screenshot.path}",
    "exists": true,
    "sizeBytes": 8,
    "extension": ".png",
    "source": "user_provided"
  },
  "nextObserveInput": {
    "required": true,
    "provided": false,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "",
    "targetIntent": "Observe the next target.",
    "screenshotPath": "${screenshot.path}"
  },
  "commands": {},
  "m28ScreenshotEvidenceIntakeGate": {
    "status": "blocked",
    "ready": false,
    "blockers": ["target_app_present"]
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m29_observe_canary_run_packet.sh',
          '--root',
          root.path,
          '--m28-intake',
          intake.path,
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('m28_intake_ready'));
        expect('${result.stdout}', contains('target_app_present'));
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => file.path.endsWith('observe_canary_run_packet.json'),
            )
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"target_app_present"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('Computer Use M30 observe result intake returns to M15', () async {
    expect(
      m30ObserveResultIntakeScript,
      contains('macos_computer_use_m30_observe_result_intake'),
    );
    expect(m30ObserveResultIntakeScript, contains('report-only'));
    expect(m30ObserveResultIntakeScript, contains('ready M29'));
    expect(m30ObserveResultIntakeScript, contains('no desktop actions'));

    final root = Directory.systemTemp.createTempSync(
      'caverno_m30_observe_result_intake_test_',
    );
    try {
      final screenshot = File('${root.path}/target.png')
        ..writeAsBytesSync(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
      final m29Packet = File('${root.path}/observe_canary_run_packet.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m29_observe_canary_run_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m29_observe_canary_run_packet",
  "milestone": "M29",
  "previousMilestone": "M28",
  "ready": true,
  "executionBoundary": "m14_observe_canary_run_packet_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "Safari",
  "targetIntent": "Observe the fresh compose target before proposing text.",
  "screenshotEvidence": {
    "path": "${screenshot.path}",
    "exists": true,
    "sizeBytes": 8,
    "extension": ".png"
  },
  "m14ObserveRunPacket": {
    "required": true,
    "readyForUserOperation": true,
    "userOperated": true,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "Safari",
    "targetIntent": "Observe the fresh compose target before proposing text.",
    "screenshotPath": "${screenshot.path}"
  },
  "commands": {
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --root ${root.path} --screenshot ${screenshot.path}"
  },
  "m29ObserveCanaryRunPacketGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');
      final m14Summary = File('${root.path}/canary_summary.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_real_app_observe_canary_summary",
  "schemaVersion": 1,
  "purpose": "computer_use_real_app_observe_canary",
  "milestone": "M14",
  "ready": true,
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "targetApp": "Safari",
  "targetIntent": "Observe the fresh compose target before proposing text.",
  "screenshotPath": "${screenshot.path}",
  "visionDecision": "Safari compose screen is visible.",
  "observedApp": "Safari",
  "visibleAppWindow": true,
  "observationOnly": true,
  "requiresUserApprovalBeforeAction": true,
  "candidateTargets": [
    {
      "label": "Compose text field",
      "role": "text_field",
      "risk": "input"
    },
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action"
    }
  ],
  "confirmationRequirements": [
    "Ask the user to approve the exact text before typing.",
    "Ask the user to approve the public post action."
  ],
  "actionPlan": [
    {"tool": "computer_vision_observe"}
  ],
  "m14EvidenceGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_m30_observe_result_intake.sh',
        '--root',
        root.path,
        '--m29-packet',
        m29Packet.path,
        '--m14-summary',
        m14Summary.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect('${result.stdout}', contains('Gate status: ready'));
      expect(
        '${result.stdout}',
        contains('Execution boundary: m14_observe_result_intake_report_only'),
      );
      expect('${result.stdout}', contains('M15 action proposal command: bash'));

      final summaryFiles = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('observe_result_intake.json'))
          .toList(growable: false);
      expect(summaryFiles, hasLength(1));
      final summary = summaryFiles.single.readAsStringSync();
      expect(summary, contains('macos_computer_use_m30_observe_result_intake'));
      expect(summary, contains('"milestone": "M30"'));
      expect(summary, contains('"returnToMilestone": "M15"'));
      expect(summary, contains('"ready": true'));
      expect(summary, contains('"m30ObserveResultIntakeGate"'));
      expect(summary, contains('"sourceM29ObserveCanaryRunPacket"'));
      expect(summary, contains('"sourceM14ObserveCanarySummary"'));
      expect(summary, contains('"targetAppMatches": true'));
      expect(summary, contains('"m15ActionProposalHandoff"'));

      final markdown = File(
        summaryFiles.single.path.replaceAll('.json', '.md'),
      ).readAsStringSync();
      expect(markdown, contains('M30 Observe Result Intake'));
      expect(markdown, contains('Next Handoff'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('Computer Use M30 return command generates ready M15 handoff', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_m30_to_m15_handoff_test_',
    );
    try {
      final screenshot = File('${root.path}/target.png')
        ..writeAsBytesSync(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
      final m29Packet = File('${root.path}/observe_canary_run_packet.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m29_observe_canary_run_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m29_observe_canary_run_packet",
  "milestone": "M29",
  "previousMilestone": "M28",
  "ready": true,
  "executionBoundary": "m14_observe_canary_run_packet_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "Safari",
  "targetIntent": "Prepare to type \\"good morning\\" into the compose field after approval.",
  "screenshotEvidence": {
    "path": "${screenshot.path}",
    "exists": true,
    "sizeBytes": 8,
    "extension": ".png"
  },
  "m14ObserveRunPacket": {
    "required": true,
    "readyForUserOperation": true,
    "userOperated": true,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "Safari",
    "targetIntent": "Prepare to type \\"good morning\\" into the compose field after approval.",
    "screenshotPath": "${screenshot.path}"
  },
  "commands": {
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --root ${root.path} --screenshot ${screenshot.path}"
  },
  "m29ObserveCanaryRunPacketGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');
      final m14Summary = File('${root.path}/canary_summary.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_real_app_observe_canary_summary",
  "schemaVersion": 1,
  "purpose": "computer_use_real_app_observe_canary",
  "milestone": "M14",
  "ready": true,
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "targetApp": "Safari",
  "targetIntent": "Prepare to type \\"good morning\\" into the compose field after approval.",
  "screenshotPath": "${screenshot.path}",
  "visionDecision": "Safari compose screen is visible.",
  "observedApp": "Safari",
  "visibleAppWindow": true,
  "observationOnly": true,
  "requiresUserApprovalBeforeAction": true,
  "candidateTargets": [
    {
      "label": "Compose text field",
      "role": "text_field",
      "risk": "input"
    },
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action"
    }
  ],
  "confirmationRequirements": [
    "Ask the user to approve the exact text before typing.",
    "Ask the user to approve the public post action."
  ],
  "actionPlan": [
    {"tool": "computer_vision_observe"}
  ],
  "m14EvidenceGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

      final m30Result = await Process.run('bash', [
        'tool/run_macos_computer_use_m30_observe_result_intake.sh',
        '--root',
        root.path,
        '--m29-packet',
        m29Packet.path,
        '--m14-summary',
        m14Summary.path,
      ]);

      expect(
        m30Result.exitCode,
        0,
        reason: '${m30Result.stdout}\n${m30Result.stderr}',
      );
      final m30SummaryFile = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere(
            (file) => file.path.endsWith('observe_result_intake.json'),
          );
      final m30Summary =
          jsonDecode(m30SummaryFile.readAsStringSync()) as Map<String, dynamic>;
      final commands = m30Summary['commands'] as Map<String, dynamic>;
      expect(
        commands['m15ActionProposalHandoff'],
        'bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --root ${root.path} --m14-summary ${m14Summary.path}',
      );

      final m15Result = await Process.run('bash', [
        'tool/run_macos_computer_use_m15_action_proposal_handoff.sh',
        '--root',
        root.path,
        '--m14-summary',
        m14Summary.path,
      ]);

      expect(
        m15Result.exitCode,
        0,
        reason: '${m15Result.stdout}\n${m15Result.stderr}',
      );
      expect('${m15Result.stdout}', contains('Ready: true'));
      final m15SummaryFile = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere(
            (file) => file.path.endsWith('action_proposal_handoff.json'),
          );
      final m15Summary =
          jsonDecode(m15SummaryFile.readAsStringSync()) as Map<String, dynamic>;
      final m15Gate =
          m15Summary['m15ActionProposalGate'] as Map<String, dynamic>;

      expect(m15Summary['milestone'], 'M15');
      expect(m15Summary['previousMilestone'], 'M14');
      expect(m15Summary['sourceM14Summary'], m14Summary.path);
      expect(
        m15Summary['executionBoundary'],
        'approval_bound_action_proposal_report_only',
      );
      expect(m15Summary['desktopActionBoundary'], 'no_desktop_action');
      expect(m15Summary['tccBoundary'], 'no_tcc_operation');
      expect(m15Summary['llmBoundary'], 'no_llm_call');
      expect(m15Gate['status'], 'ready');
      expect(m15Gate['ready'], isTrue);
      expect(m15Summary['approvalBoundActionProposal'], isNotEmpty);
      expect(m15Summary['textEntryTargets'], isNotEmpty);
      expect(m15Summary['publicActionTargets'], isNotEmpty);
      expect(m15Summary['confirmationRequirements'], isNotEmpty);
      expect(m15Summary['exactTextCandidates'], isNotEmpty);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'Computer Use M30 observe result intake blocks mismatched M14',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_m30_observe_result_intake_blocked_test_',
      );
      try {
        final screenshot = File('${root.path}/target.png')
          ..writeAsBytesSync(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
        final m29Packet = File('${root.path}/observe_canary_run_packet.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m29_observe_canary_run_packet",
  "milestone": "M29",
  "ready": true,
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "Safari",
  "targetIntent": "Observe target.",
  "screenshotEvidence": {"path": "${screenshot.path}"},
  "m14ObserveRunPacket": {
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "Safari",
    "targetIntent": "Observe target.",
    "screenshotPath": "${screenshot.path}"
  },
  "m29ObserveCanaryRunPacketGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');
        final m14Summary = File('${root.path}/canary_summary.json')
          ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_real_app_observe_canary_summary",
  "milestone": "M14",
  "ready": true,
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "targetApp": "Notes",
  "targetIntent": "Observe target.",
  "screenshotPath": "${screenshot.path}",
  "observationOnly": true,
  "candidateTargets": [],
  "confirmationRequirements": [],
  "m14EvidenceGate": {
    "status": "ready",
    "ready": true,
    "blockers": []
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_m30_observe_result_intake.sh',
          '--root',
          root.path,
          '--m29-packet',
          m29Packet.path,
          '--m14-summary',
          m14Summary.path,
        ]);

        expect(result.exitCode, 1);
        expect('${result.stdout}', contains('Gate status: blocked'));
        expect('${result.stdout}', contains('target_app_matches'));
        expect('${result.stdout}', contains('candidate_targets_present'));
        final summaryFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('observe_result_intake.json'))
            .toList(growable: false);
        expect(summaryFiles, hasLength(1));
        final summary = summaryFiles.single.readAsStringSync();
        expect(summary, contains('"status": "blocked"'));
        expect(summary, contains('"target_app_matches"'));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('MVP fixture runbook keeps manual boundaries explicit', () {
    expect(mvpFixtureRunbook, contains('MVP Fixture Runbook'));
    expect(
      mvpFixtureRunbook,
      contains(
        'bash tool/run_macos_computer_use_llm_decision_canary.sh --scenario mvp-fixture',
      ),
    );
    expect(
      mvpFixtureRunbook,
      contains(
        'bash tool/run_macos_computer_use_llm_decision_canary.sh --scenario mvp-fixture-type-confirm',
      ),
    );
    expect(
      mvpFixtureRunbook,
      contains('bash tool/run_macos_computer_use_mvp_fixture.sh --launch'),
    );
    expect(
      mvpFixtureRunbook,
      contains('bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh'),
    );
    expect(
      mvpFixtureRunbook,
      contains(
        'macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json',
      ),
    );
    expect(
      mvpFixtureRunbook,
      contains(
        'macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json',
      ),
    );
    expect(
      mvpFixtureRunbook,
      contains(
        'macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json',
      ),
    );
    expect(
      mvpFixtureRunbook,
      contains(
        'bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target',
      ),
    );
    expect(
      mvpFixtureRunbook,
      contains('does not auto-launch Caverno.app by default'),
    );
    expect(mvpFixtureRunbook, contains('PR Review Artifacts'));
    expect(mvpFixtureRunbook, contains('PR Review Summary'));
    expect(mvpFixtureRunbook, contains('mvp_demo_handoff.md'));
    expect(mvpFixtureRunbook, contains('mvp_demo_final_handoff.md'));
    expect(
      mvpFixtureRunbook,
      contains('macos_computer_use_readiness_artifact_index.md'),
    );
    expect(
      mvpFixtureRunbook,
      contains('macos_computer_use_release_readiness_ci.md'),
    );
    expect(
      mvpFixtureRunbook,
      contains('macos_computer_use_release_readiness_signoff.md'),
    );
    expect(
      mvpFixtureRunbook,
      contains('macos_computer_use_mvp_readiness.json'),
    );
    expect(mvpFixtureRunbook, contains('macos_computer_use_mvp_readiness.md'));
    expect(
      mvpFixtureRunbook,
      contains('bash tool/run_macos_computer_use_mvp_readiness_preflight.sh'),
    );
    expect(
      mvpFixtureRunbook,
      contains('without running TCC, System Settings, app launch, or desktop'),
    );
    expect(
      mvpFixtureRunbook,
      contains(
        'dart run tool/macos_computer_use_readiness_artifact_index.dart',
      ),
    );
    expect(mvpFixtureRunbook, contains('--launch-caverno'));
    expect(mvpFixtureRunbook, contains('user-operated'));
    expect(mvpFixtureRunbook, contains('does not grant TCC'));
  });

  test(
    'real app observe runbook keeps M14 observe-only boundaries explicit',
    () {
      expect(realAppObserveRunbook, contains('Real App Observe Runbook'));
      expect(realAppObserveRunbook, contains('M12'));
      expect(realAppObserveRunbook, contains('M14'));
      expect(
        realAppObserveRunbook,
        contains('tool/run_macos_computer_use_real_app_observe_canary.sh'),
      );
      expect(realAppObserveRunbook, contains('--target-app Safari'));
      expect(realAppObserveRunbook, contains('public_action'));
      expect(realAppObserveRunbook, contains('m12EvidenceGate'));
      expect(realAppObserveRunbook, contains('m14EvidenceGate'));
      expect(realAppObserveRunbook, contains('M15 Action Proposal Handoff'));
      expect(
        realAppObserveRunbook,
        contains('tool/run_macos_computer_use_m15_action_proposal_handoff.sh'),
      );
      expect(
        realAppObserveRunbook,
        contains('tool/run_macos_computer_use_m15_llm_review_canary.sh'),
      );
      expect(realAppObserveRunbook, contains('m15ActionProposalGate'));
      expect(realAppObserveRunbook, contains('m15LlmReviewGate'));
      expect(realAppObserveRunbook, contains('PR Review Summary'));
      expect(realAppObserveRunbook, contains('blockedReviewEvidence'));
      expect(realAppObserveRunbook, contains('m15_llm_review_canary'));
      expect(realAppObserveRunbook, contains('blocked_review_evidence'));
      expect(realAppObserveRunbook, contains('final aggregation'));
      expect(realAppObserveRunbook, contains('reviewTargetCounts'));
      expect(realAppObserveRunbook, contains('Review Targets'));
      expect(realAppObserveRunbook, contains('exact text candidates'));
      expect(realAppObserveRunbook, contains('text-entry targets'));
      expect(realAppObserveRunbook, contains('public-action targets'));
      expect(realAppObserveRunbook, contains('confirmation requirements'));
      expect(
        realAppObserveRunbook,
        contains('It does not record the API key.'),
      );
      expect(
        realAppObserveRunbook,
        contains('TCC setup and real desktop operation remain user-operated.'),
      );
      expect(
        architectureDoc,
        contains('M12: Add real-app observe-only canaries'),
      );
    },
  );

  test('MVP sign-off wrapper keeps user-operated boundaries explicit', () {
    final mvpChecklist = File(
      'docs/macos_computer_use_mvp_checklist.md',
    ).readAsStringSync();

    expect(mvpChecklist, contains('macOS Computer Use MVP Checklist'));
    expect(mvpChecklist, contains('mvpEvidenceGate'));
    expect(mvpChecklist, contains('destructive_target_refused'));
    expect(
      mvpChecklist,
      contains(
        'Report-only handoff, readiness, artifact-index, and aggregation guidance',
      ),
    );
    expect(
      mvpChecklist,
      contains(
        'changes do not require fresh TCC or live desktop-action verification.',
      ),
    );
    expect(
      mvpChecklist,
      contains('bash tool/run_macos_computer_use_manual_tcc_signoff.sh'),
    );
    expect(
      mvpChecklist,
      contains(
        'bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target',
      ),
    );
    expect(
      mvpChecklist,
      contains('bash tool/run_macos_computer_use_mvp_signoff.sh'),
    );
    expect(
      mvpChecklist,
      contains(
        'macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json',
      ),
    );
    expect(
      mvpChecklist,
      contains(
        'macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json',
      ),
    );
    expect(
      mvpChecklist,
      contains(
        'macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json',
      ),
    );
    expect(mvpChecklist, contains('--dry-run'));
    expect(
      mvpChecklist,
      contains('bash tool/run_macos_computer_use_mvp_readiness_preflight.sh'),
    );
    expect(
      mvpChecklist,
      contains(
        'does not run TCC, System Settings, app launch, or desktop actions',
      ),
    );
    expect(mvpChecklist, contains('PR Review Summary'));
    expect(mvpChecklist, contains('macos_computer_use_mvp_handoff.md'));
    expect(
      mvpChecklist,
      contains('macos_computer_use_readiness_artifact_index.md'),
    );
    expect(
      mvpChecklist,
      contains('macos_computer_use_release_readiness_ci.md'),
    );
    expect(
      mvpChecklist,
      contains('macos_computer_use_release_readiness_signoff.md'),
    );
    expect(mvpChecklist, contains('macos_computer_use_mvp_readiness.json'));
    expect(mvpChecklist, contains('macos_computer_use_mvp_readiness.md'));
    expect(mvpChecklist, contains('M15 LLM Review Evidence'));
    expect(mvpChecklist, contains('m15_llm_review_canary'));
    expect(mvpChecklist, contains('m15LlmReviewGate'));
    expect(mvpChecklist, contains('M17 execution rehearsals'));
    expect(mvpChecklist, contains('M18 execution handoffs'));
    expect(mvpChecklist, contains('M20 execution'));
    expect(mvpChecklist, contains('result intake reports'));
    expect(mvpChecklist, contains('M22 post-action reviews'));
    expect(mvpChecklist, contains('M23 cycle outcome'));
    expect(mvpChecklist, contains('M25 next-cycle seed'));
    expect(mvpChecklist, contains('M26 observe restart packet'));
    expect(mvpChecklist, contains('m27_screenshot_request_handoff'));
    expect(mvpChecklist, contains('m28_screenshot_evidence_intake'));
    expect(mvpChecklist, contains('m29_observe_canary_run_packet'));
    expect(mvpChecklist, contains('m30_observe_result_intake'));
    expect(mvpChecklist, contains('m23CycleOutcomeHandoffGate'));
    expect(mvpChecklist, contains('m25NextCycleSeedHandoffGate'));
    expect(mvpChecklist, contains('m26ObserveRestartPacketGate'));
    expect(mvpChecklist, contains('m27ScreenshotRequestHandoffGate'));
    expect(mvpChecklist, contains('m28ScreenshotEvidenceIntakeGate'));
    expect(mvpChecklist, contains('m29ObserveCanaryRunPacketGate'));
    expect(mvpChecklist, contains('m30ObserveResultIntakeGate'));
    expect(mvpChecklist, contains('blocked_review_evidence'));
    expect(
      mvpChecklist,
      contains(
        'dart run tool/macos_computer_use_readiness_artifact_index.dart',
      ),
    );
    expect(
      mvpChecklist,
      contains('These report-only commands summarize existing evidence'),
    );
    expect(mvpSignoffScript, contains('macos_computer_use_mvp_handoff.md'));
    expect(mvpSignoffScript, contains('macos_computer_use_mvp_readiness.json'));
    expect(
      mvpSignoffScript,
      contains('Current Required Input Evidence Status'),
    );
    _expectOperationBoundaryMarkdown(mvpSignoffScript, escapedBackticks: true);
    expect(
      mvpSignoffScript,
      contains(
        'Report-only handoff and aggregation checks do not require TCC or live desktop action.',
      ),
    );
    expect(mvpSignoffScript, contains('LLM Evidence Gate'));
    expect(mvpSignoffScript, contains('MVP Sign-Off Outputs'));
    expect(mvpSignoffScript, contains('MVP sign-off outputs:'));
    expect(mvpSignoffScript, contains('PR Review Summary'));
    expect(mvpSignoffScript, contains('PR review summary:'));
    expect(mvpSignoffScript, contains('Release readiness PR Review Summary'));
    expect(mvpSignoffScript, contains('ready_for_final_aggregation'));
    expect(mvpSignoffScript, contains('blocked_pending_evidence'));
    expect(mvpSignoffScript, contains('Missing Input Next Actions'));
    expect(mvpSignoffScript, contains('Final Readiness Next Actions'));
    expect(mvpSignoffScript, contains('--final-signoff'));
    expect(mvpSignoffScript, contains('readiness_exit'));
    expect(
      mvpSignoffScript,
      contains('CAVERNO_MACOS_COMPUTER_USE_READINESS_WRAPPER'),
    );
    expect(mvpSignoffScript, contains('MVP_READINESS_PREFLIGHT_COMMAND'));
    expect(
      mvpSignoffScript,
      contains('bash tool/run_macos_computer_use_mvp_readiness_preflight.sh'),
    );
    expect(mvpSignoffScript, contains('provided path not found'));
    expect(mvpSignoffScript, contains('DISCOVERED_MANUAL_TCC_REPORT'));
    expect(
      mvpSignoffScript,
      contains('DISCOVERED_DESKTOP_ACTION_CANARY_SUMMARY'),
    );
    expect(mvpSignoffScript, contains('DISCOVERED_LLM_CANARY_SUMMARY'));
    expect(
      mvpSignoffScript,
      contains('DISCOVERED_M15_ACTION_PROPOSAL_HANDOFF'),
    );
    expect(
      mvpSignoffScript,
      contains('DISCOVERED_M15_LLM_REVIEW_CANARY_SUMMARY'),
    );
    expect(mvpSignoffScript, contains('DISCOVERED_M16_APPROVAL_PACKET'));
    expect(mvpSignoffScript, contains('DISCOVERED_M17_EXECUTION_REHEARSAL'));
    expect(mvpSignoffScript, contains('DISCOVERED_M18_EXECUTION_HANDOFF'));
    expect(
      mvpSignoffScript,
      contains('DISCOVERED_M20_EXECUTION_RESULT_INTAKE'),
    );
    expect(mvpSignoffScript, contains('DISCOVERED_M22_POST_ACTION_REVIEW'));
    expect(mvpSignoffScript, contains('DISCOVERED_M23_CYCLE_OUTCOME_HANDOFF'));
    expect(
      mvpSignoffScript,
      contains('DISCOVERED_M25_NEXT_CYCLE_SEED_HANDOFF'),
    );
    expect(mvpSignoffScript, contains('DISCOVERED_M26_OBSERVE_RESTART_PACKET'));
    expect(
      mvpSignoffScript,
      contains('DISCOVERED_M27_SCREENSHOT_REQUEST_HANDOFF'),
    );
    expect(
      mvpSignoffScript,
      contains('DISCOVERED_M28_SCREENSHOT_EVIDENCE_INTAKE'),
    );
    expect(
      mvpSignoffScript,
      contains('DISCOVERED_M29_OBSERVE_CANARY_RUN_PACKET'),
    );
    expect(mvpSignoffScript, contains('DISCOVERED_M30_OBSERVE_RESULT_INTAKE'));
    expect(mvpSignoffScript, contains('M15 Action Proposal Evidence'));
    expect(mvpSignoffScript, contains('M15 LLM Review Evidence'));
    expect(mvpSignoffScript, contains('M16 Approval Packet Evidence'));
    expect(mvpSignoffScript, contains('M17 Execution Rehearsal Evidence'));
    expect(mvpSignoffScript, contains('M18 Execution Handoff Evidence'));
    expect(mvpSignoffScript, contains('M20 Execution Result Intake Evidence'));
    expect(mvpSignoffScript, contains('M22 Post-Action Review Evidence'));
    expect(mvpSignoffScript, contains('M23 Cycle Outcome Handoff Evidence'));
    expect(mvpSignoffScript, contains('M25 Next-Cycle Seed Handoff Evidence'));
    expect(mvpSignoffScript, contains('M26 Observe Restart Packet Evidence'));
    expect(
      mvpSignoffScript,
      contains('M27 Screenshot Request Handoff Evidence'),
    );
    expect(mvpSignoffScript, contains('M28 Screenshot Evidence Intake'));
    expect(mvpSignoffScript, contains('M29 Observe Canary Run Packet'));
    expect(mvpSignoffScript, contains('M30 Observe Result Intake'));
    expect(mvpSignoffScript, contains('Optional Review Evidence'));
    expect(mvpSignoffScript, contains('discovered'));
    expect(mvpSignoffScript, contains('Dry run: would execute'));
    expect(
      mvpSignoffScript,
      contains('user-operated manual verification only'),
    );
    expect(mvpSignoffScript, contains('user-operated safe click target only'));
    expect(
      mvpSignoffScript,
      contains(_manualTccNextAction.replaceAll('`', r'\`')),
    );
    expect(
      mvpSignoffScript,
      contains(_desktopActionNextAction.replaceAll('`', r'\`')),
    );
    expect(
      mvpSignoffScript,
      contains(_llmCanaryNextAction.replaceAll('`', r'\`')),
    );
    expect(mvpLlmReadinessScript, contains(_manualTccNextAction));
    expect(mvpLlmReadinessScript, contains(_desktopActionNextAction));
    expect(mvpDemoReadinessScript, contains(_manualTccNextAction));
    expect(mvpDemoReadinessScript, contains(_desktopActionNextAction));
    expect(mvpSignoffScript, contains('--manual-tcc-report'));
    expect(mvpSignoffScript, contains('--desktop-action-canary-summary'));
    expect(mvpSignoffScript, contains('--llm-canary-summary'));
    expect(mvpSignoffScript, contains('LLM canary status'));
    expect(mvpSignoffScript, contains('LLM evidence gate'));
    expect(mvpSignoffScript, contains('LLM_EVIDENCE_FRAGMENT'));
    expect(
      mvpSignoffScript,
      contains('bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh'),
    );
    expect(
      mvpSignoffScript,
      contains('bash tool/run_macos_computer_use_mvp_llm_readiness.sh'),
    );
    expect(
      architectureDoc,
      contains('docs/macos_computer_use_mvp_checklist.md'),
    );
    expect(
      architectureDoc,
      contains('--llm-canary-summary <llm-canary-summary.json>'),
    );
    expect(
      architectureDoc,
      contains(
        'index now surface that review canary as optional review evidence',
      ),
    );
  });

  test('MVP sign-off dry run writes missing manual input handoff', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_missing_',
    );
    try {
      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('Dry run: 1'));
      expect(stdout, contains('Manual TCC status: not provided'));
      expect(stdout, contains('Desktop action canary status: not provided'));
      expect(stdout, contains('M15 action proposal status: missing'));
      expect(stdout, contains('M15 LLM review status: missing'));
      expect(stdout, contains('M16 approval packet status: missing'));
      expect(stdout, contains('M17 execution rehearsal status: missing'));
      expect(stdout, contains('M18 execution handoff status: missing'));
      expect(
        stdout,
        contains(
          'M15 action proposal next action: Run the M15 action proposal handoff after M14 observe-only evidence is ready.',
        ),
      );
      expect(
        stdout,
        contains(
          'M16 approval packet next action: Run the M16 approval packet after the M15 action proposal handoff and M15 LLM review are ready.',
        ),
      );
      expect(
        stdout,
        contains(
          'M17 execution rehearsal next action: Run the M17 execution rehearsal after the M16 approval packet is approved.',
        ),
      );
      expect(
        stdout,
        contains(
          'M18 execution handoff next action: Run the M18 execution handoff after the M17 execution rehearsal is ready.',
        ),
      );
      expect(stdout, contains('MVP sign-off outputs:'));
      expect(stdout, contains('PR review summary:'));
      expect(stdout, contains('Status: blocked_pending_evidence'));
      expect(stdout, contains('Ready input evidence: none'));
      expect(
        stdout,
        contains(
          'Missing input evidence: manual_tcc, desktop_action_canary, llm_canary',
        ),
      );
      expect(
        stdout,
        contains(
          'Pending user-operated evidence: manual_tcc, desktop_action_canary',
        ),
      );
      expect(stdout, contains('Pending automation-safe evidence: llm_canary'));
      expect(stdout, contains('Expected final input paths:'));
      expect(
        stdout,
        contains(
          'Manual TCC: macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json',
        ),
      );
      expect(
        stdout,
        contains(
          'Desktop action: macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json',
        ),
      );
      expect(
        stdout,
        contains(
          'MVP fixture LLM: macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json',
        ),
      );
      expect(
        stdout,
        contains('JSON: ${root.path}/macos_computer_use_mvp_readiness.json'),
      );
      expect(
        stdout,
        contains('Markdown: ${root.path}/macos_computer_use_mvp_readiness.md'),
      );
      expect(
        stdout,
        contains(
          'Handoff Markdown: ${root.path}/macos_computer_use_mvp_handoff.md',
        ),
      );
      expect(
        stdout,
        contains(
          'Handoff PR Review Summary: ${root.path}/macos_computer_use_mvp_handoff.md',
        ),
      );
      expect(
        stdout,
        contains(
          'Release readiness PR Review Summary (final sign-off output): ${root.path}/macos_computer_use_mvp_readiness.md',
        ),
      );
      expect(
        stdout,
        contains(
          'Artifact index PR Review Summary: ${root.path}/macos_computer_use_readiness_artifact_index.md',
        ),
      );
      expect(
        stdout,
        contains(
          'Artifact index command: dart run tool/macos_computer_use_readiness_artifact_index.dart --root ${root.path}',
        ),
      );
      expect(
        stdout,
        contains(
          'MVP readiness preflight command: bash tool/run_macos_computer_use_mvp_readiness_preflight.sh --root ${root.path}',
        ),
      );
      expect(stdout, contains(_manualTccNextAction));
      expect(stdout, contains(_desktopActionNextAction));
      expect(stdout, contains('Dry run: would execute'));

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('Manual TCC status: not provided'));
      expect(handoff, contains('Desktop action canary status: not provided'));
      expect(handoff, contains('M15 action proposal status: missing'));
      expect(handoff, contains('M15 LLM review status: missing'));
      expect(handoff, contains('M16 approval packet status: missing'));
      expect(handoff, contains('M17 execution rehearsal status: missing'));
      expect(handoff, contains('M18 execution handoff status: missing'));
      expect(handoff, contains('Optional Review Evidence'));
      expect(handoff, contains('M15 Action Proposal Evidence'));
      expect(handoff, contains('M15 LLM Review Evidence'));
      expect(handoff, contains('M16 Approval Packet Evidence'));
      expect(handoff, contains('M17 Execution Rehearsal Evidence'));
      expect(handoff, contains('M18 Execution Handoff Evidence'));
      expect(
        handoff,
        contains(
          'M15 action proposal blockers: missing_m15_action_proposal_handoff',
        ),
      );
      expect(
        handoff,
        contains('M15 LLM review blockers: missing_m15_llm_review_canary'),
      );
      expect(
        handoff,
        contains('M16 approval packet blockers: missing_m16_approval_packet'),
      );
      expect(
        handoff,
        contains(
          'M17 execution rehearsal blockers: missing_m17_execution_rehearsal',
        ),
      );
      expect(
        handoff,
        contains(
          'M18 execution handoff blockers: missing_m18_execution_handoff',
        ),
      );
      expect(
        handoff,
        contains(
          'Report-only handoff and aggregation checks do not require TCC or live desktop action.',
        ),
      );
      expect(handoff, contains('Current Required Input Evidence Status'));
      expect(handoff, contains('MVP Sign-Off Outputs'));
      expect(handoff, contains('Expected Final Input Paths'));
      expect(handoff, contains('PR Review Summary'));
      expect(handoff, contains('Status: blocked_pending_evidence'));
      expect(handoff, contains('Ready input evidence: none'));
      expect(
        handoff,
        contains(
          'Missing input evidence: manual_tcc, desktop_action_canary, llm_canary',
        ),
      );
      expect(
        handoff,
        contains(
          'Pending user-operated evidence: manual_tcc, desktop_action_canary',
        ),
      );
      expect(handoff, contains('Pending automation-safe evidence: llm_canary'));
      expect(
        handoff,
        contains(
          'Manual TCC: `macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json`',
        ),
      );
      expect(
        handoff,
        contains(
          'Desktop action: `macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json`',
        ),
      );
      expect(
        handoff,
        contains(
          'MVP fixture LLM: `macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json`',
        ),
      );
      expect(
        handoff,
        contains('JSON: ${root.path}/macos_computer_use_mvp_readiness.json'),
      );
      expect(
        handoff,
        contains('Markdown: ${root.path}/macos_computer_use_mvp_readiness.md'),
      );
      expect(
        handoff,
        contains(
          'Release readiness PR Review Summary (final sign-off output): ${root.path}/macos_computer_use_mvp_readiness.md',
        ),
      );
      expect(
        handoff,
        contains(
          'Handoff Markdown: ${root.path}/macos_computer_use_mvp_handoff.md',
        ),
      );
      expect(
        handoff,
        contains(
          'Artifact index Markdown: ${root.path}/macos_computer_use_readiness_artifact_index.md',
        ),
      );
      expect(
        handoff,
        contains(
          'Artifact index command: `dart run tool/macos_computer_use_readiness_artifact_index.dart --root ${root.path}`',
        ),
      );
      expect(
        handoff,
        contains(
          'MVP readiness preflight command: `bash tool/run_macos_computer_use_mvp_readiness_preflight.sh --root ${root.path}`',
        ),
      );
      _expectOperationBoundaryMarkdown(handoff);
      expect(handoff, contains('Missing Input Next Actions'));
      expect(
        handoff,
        contains('bash tool/run_macos_computer_use_manual_tcc_signoff.sh'),
      );
      expect(
        handoff,
        contains(
          'bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target',
        ),
      );
      expect(
        File('${root.path}/macos_computer_use_mvp_readiness.json').existsSync(),
        isFalse,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP readiness preflight is report only', () async {
    expect(
      mvpReadinessPreflightScript,
      contains('report-only, no TCC, no System Settings, no desktop actions'),
    );
    expect(
      mvpReadinessPreflightScript,
      contains('macos_computer_use_readiness_artifact_index.dart'),
    );
    expect(mvpReadinessPreflightScript, contains('--dry-run'));
    expect(mvpReadinessPreflightScript, contains('PR Review Summary'));
    expect(mvpReadinessPreflightScript, contains('PR Review Artifacts'));
    expect(mvpReadinessPreflightScript, contains('final sign-off output'));
    expect(mvpReadinessPreflightScript, contains('M15 action proposal'));
    expect(mvpReadinessPreflightScript, contains('M15 LLM review'));
    expect(mvpReadinessPreflightScript, contains('m15_llm_review_canary'));
    expect(mvpReadinessPreflightScript, contains('M16 approval packet'));
    expect(mvpReadinessPreflightScript, contains('m16_approval_packet'));
    expect(mvpReadinessPreflightScript, contains('M17 execution rehearsal'));
    expect(mvpReadinessPreflightScript, contains('m17_execution_rehearsal'));
    expect(mvpReadinessPreflightScript, contains('M18 execution handoff'));
    expect(mvpReadinessPreflightScript, contains('m18_execution_handoff'));
    expect(
      mvpReadinessPreflightScript,
      contains('M20 execution result intake'),
    );
    expect(
      mvpReadinessPreflightScript,
      contains('m20_execution_result_intake'),
    );
    expect(mvpReadinessPreflightScript, contains('M22 post-action review'));
    expect(mvpReadinessPreflightScript, contains('m22_post_action_review'));
    expect(mvpReadinessPreflightScript, contains('M23 cycle outcome handoff'));
    expect(mvpReadinessPreflightScript, contains('m23_cycle_outcome_handoff'));
    expect(
      mvpReadinessPreflightScript,
      contains('M25 next-cycle seed handoff'),
    );
    expect(
      mvpReadinessPreflightScript,
      contains('m25_next_cycle_seed_handoff'),
    );
    expect(mvpReadinessPreflightScript, contains('M26 observe restart packet'));
    expect(
      mvpReadinessPreflightScript,
      contains('M27 screenshot request handoff'),
    );
    expect(
      mvpReadinessPreflightScript,
      contains('m27_screenshot_request_handoff'),
    );
    expect(
      mvpReadinessPreflightScript,
      contains('M28 screenshot evidence intake'),
    );
    expect(
      mvpReadinessPreflightScript,
      contains('m28_screenshot_evidence_intake'),
    );
    expect(
      mvpReadinessPreflightScript,
      contains('M29 observe canary run packet'),
    );
    expect(
      mvpReadinessPreflightScript,
      contains('m29_observe_canary_run_packet'),
    );
    expect(mvpReadinessPreflightScript, contains('M30 observe result intake'));
    expect(mvpReadinessPreflightScript, contains('m30_observe_result_intake'));
    expect(mvpReadinessPreflightScript, contains('m26_observe_restart_packet'));

    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_readiness_preflight_',
    );
    try {
      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_readiness_preflight.sh',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final stdout = '${result.stdout}';
      expect(
        stdout,
        contains('Running macOS Computer Use MVP readiness preflight'),
      );
      expect(
        stdout,
        contains('Boundary: report-only, no TCC, no System Settings'),
      );
      expect(stdout, contains('Readiness artifact index written under'));
      expect(stdout, contains('MVP sign-off outputs:'));
      expect(stdout, contains('PR review summary:'));
      expect(stdout, contains('MVP readiness preflight outputs:'));
      expect(stdout, contains('Expected final input paths:'));
      expect(
        stdout,
        contains(
          'Manual TCC: macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json',
        ),
      );
      expect(
        stdout,
        contains(
          'Desktop action: macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json',
        ),
      );
      expect(
        stdout,
        contains(
          'MVP fixture LLM: macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json',
        ),
      );
      expect(
        stdout,
        contains(
          'Artifact index Markdown: ${root.path}/macos_computer_use_readiness_artifact_index.md',
        ),
      );
      expect(
        stdout,
        contains(
          'MVP handoff Markdown: ${root.path}/macos_computer_use_mvp_handoff.md',
        ),
      );
      expect(
        stdout,
        contains(
          'PR Review Summary: ${root.path}/macos_computer_use_readiness_artifact_index.md',
        ),
      );
      expect(
        stdout,
        contains(
          'PR Review Artifacts: ${root.path}/macos_computer_use_mvp_handoff.md',
        ),
      );
      expect(
        stdout,
        contains(
          'M15 action proposal: inspect the artifact index for the report-only command when M14 observe-only evidence is present',
        ),
      );
      expect(
        stdout,
        contains(
          'M15 LLM review: inspect the artifact index for the report-only review command after M15 handoff is ready',
        ),
      );
      expect(stdout, contains('blocked m15_llm_review_canary evidence'));
      expect(
        stdout,
        contains(
          'M16 approval packet: inspect the artifact index for the report-only approval packet command after M15 evidence is ready',
        ),
      );
      expect(stdout, contains('blocked m16_approval_packet evidence'));
      expect(
        stdout,
        contains(
          'M17 execution rehearsal: inspect the artifact index for the report-only rehearsal command after M16 approval is approved',
        ),
      );
      expect(stdout, contains('blocked m17_execution_rehearsal evidence'));
      expect(
        stdout,
        contains(
          'M18 execution handoff: inspect the artifact index for the report-only handoff command after M17 rehearsal is ready',
        ),
      );
      expect(stdout, contains('blocked m18_execution_handoff evidence'));
      expect(
        stdout,
        contains(
          'M20 execution result intake: inspect the artifact index for the report-only result intake command after the user completes the M18-guided runtime step',
        ),
      );
      expect(stdout, contains('blocked m20_execution_result_intake evidence'));
      expect(
        stdout,
        contains(
          'M22 post-action review: inspect the artifact index for the report-only post-action review command after M20 is ready',
        ),
      );
      expect(stdout, contains('blocked m22_post_action_review evidence'));
      expect(
        stdout,
        contains(
          'M23 cycle outcome handoff: inspect the artifact index for the report-only cycle outcome handoff command after M22 is ready',
        ),
      );
      expect(stdout, contains('blocked m23_cycle_outcome_handoff evidence'));
      expect(
        stdout,
        contains(
          'M25 next-cycle seed handoff: inspect the artifact index for the report-only next-cycle seed command after M23 restarts the cycle',
        ),
      );
      expect(stdout, contains('blocked m25_next_cycle_seed_handoff evidence'));
      expect(
        stdout,
        contains(
          'M26 observe restart packet: inspect the artifact index for the report-only M14 observe restart packet command after M25 is ready',
        ),
      );
      expect(stdout, contains('blocked m26_observe_restart_packet evidence'));
      expect(
        File(
          '${root.path}/macos_computer_use_readiness_artifact_index.json',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${root.path}/macos_computer_use_readiness_artifact_index.md',
        ).existsSync(),
        isTrue,
      );
      expect(
        File('${root.path}/macos_computer_use_mvp_handoff.md').existsSync(),
        isTrue,
      );
      expect(
        File('${root.path}/macos_computer_use_mvp_readiness.json').existsSync(),
        isFalse,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('post-merge sanity runner avoids TCC and desktop actions', () async {
    expect(
      postMergeSanityScript,
      contains('static checks only, no TCC, no System Settings'),
    );
    expect(
      postMergeSanityScript,
      contains('Advanced navigation, collapsed Diagnostics'),
    );
    expect(postMergeSanityScript, contains('M14 observe-only evidence'));
    expect(postMergeSanityScript, contains('M15 review/gate consistency'));
    expect(
      postMergeSanityScript,
      contains(
        'docs/macos_computer_use_manual_process_checklist.md#M13-Review-Hardening',
      ),
    );
    expect(
      postMergeSanityScript,
      contains(
        'docs/macos_computer_use_manual_process_checklist.md#M14-Observe-Only-Evidence',
      ),
    );
    expect(postMergeSanityScript, contains('flutter analyze'));
    expect(postMergeSanityScript, contains('flutter test'));
    expect(postMergeSanityScript, contains('flutter build macos --debug'));
    expect(
      postMergeSanityScript,
      isNot(contains('run_macos_computer_use_manual_tcc_signoff.sh')),
    );
    expect(
      postMergeSanityScript,
      isNot(contains('run_macos_computer_use_desktop_action_canary.sh')),
    );
    expect(
      postMergeSanityScript,
      isNot(contains('run_macos_computer_use_live_canary.sh')),
    );

    final result = await Process.run('bash', [
      'tool/run_macos_computer_use_post_merge_sanity.sh',
      '--print-commands',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final stdout = '${result.stdout}';
    expect(
      stdout,
      contains('Running macOS Computer Use post-merge sanity checks'),
    );
    expect(
      stdout,
      contains('Boundary: static checks only, no TCC, no System Settings'),
    );
    expect(
      stdout,
      contains(
        'Review scope: Advanced navigation, collapsed Diagnostics, manual runtime handoff, M14 observe-only evidence, M15 review/gate consistency',
      ),
    );
    expect(
      stdout,
      contains(
        'Checklist: docs/macos_computer_use_manual_process_checklist.md#M13-Review-Hardening',
      ),
    );
    expect(
      stdout,
      contains(
        'Observe checklist: docs/macos_computer_use_manual_process_checklist.md#M14-Observe-Only-Evidence',
      ),
    );
    expect(stdout, contains('flutter analyze'));
    expect(
      stdout,
      contains(
        'test/features/settings/presentation/pages/advanced_settings_page_test.dart',
      ),
    );
    expect(
      stdout,
      contains(
        'test/features/settings/presentation/pages/settings_page_test.dart',
      ),
    );
    expect(
      stdout,
      contains(
        'test/features/settings/presentation/pages/computer_use_debug_page_test.dart',
      ),
    );
    expect(
      stdout,
      contains(
        'test/integration_support/macos_computer_use_release_readiness_test.dart',
      ),
    );
    expect(
      stdout,
      contains('test/tool/run_macos_computer_use_smoke_test_test.dart'),
    );
    expect(stdout, contains('flutter build macos --debug'));
    expect(
      stdout,
      contains('macOS Computer Use post-merge sanity checks complete'),
    );
  });

  test('M13 polish review summary keeps merge boundaries explicit', () {
    expect(
      polishReviewSummary,
      contains('macOS Computer Use Polish Review Summary'),
    );
    expect(polishReviewSummary, contains('Settings > Advanced'));
    expect(
      polishReviewSummary,
      contains('not a top-level Computer Use status'),
    );
    expect(polishReviewSummary, contains('collapsed `Diagnostics` section'));
    expect(polishReviewSummary, contains('Caverno Computer Use.app'));
    expect(
      polishReviewSummary,
      contains('run_macos_computer_use_post_merge_sanity.sh'),
    );
    expect(polishReviewSummary, contains('--print-commands'));
    expect(
      polishReviewSummary,
      contains('must not grant TCC, edit TCC, operate System Settings'),
    );
    expect(polishReviewSummary, contains('Manual TCC runtime sign-off'));
    expect(polishReviewSummary, contains('Desktop action canary'));
    expect(polishReviewSummary, contains('M14 expands real-app observe-only'));
    expect(
      polishReviewSummary,
      contains('must not click, type, submit, post, purchase'),
    );
  });

  test('manual process checklist documents M14 observe-only evidence', () {
    expect(manualProcessChecklist, contains('M14 Observe-Only Evidence'));
    expect(manualProcessChecklist, contains('M15 Action Proposal Handoff'));
    expect(manualProcessChecklist, contains('M16 Approval Packet'));
    expect(manualProcessChecklist, contains('M17 Execution Rehearsal'));
    expect(manualProcessChecklist, contains('M18 Execution Handoff'));
    expect(manualProcessChecklist, contains('M20 Execution Result Intake'));
    expect(manualProcessChecklist, contains('M22 Post-Action Review'));
    expect(manualProcessChecklist, contains('M23 Cycle Outcome Handoff'));
    expect(manualProcessChecklist, contains('M25 Next-Cycle Seed Handoff'));
    expect(manualProcessChecklist, contains('M26 Observe Restart Packet'));
    expect(manualProcessChecklist, contains('M27 Screenshot Request Handoff'));
    expect(manualProcessChecklist, contains('M28 Screenshot Evidence Intake'));
    expect(manualProcessChecklist, contains('M29 Observe Canary Run Packet'));
    expect(manualProcessChecklist, contains('M30 Observe Result Intake'));
    expect(manualProcessChecklist, contains('M15 review/gate consistency'));
    expect(manualProcessChecklist, contains('m14EvidenceGate'));
    expect(manualProcessChecklist, contains('m15ActionProposalGate'));
    expect(manualProcessChecklist, contains('m15LlmReviewGate'));
    expect(manualProcessChecklist, contains('m16ApprovalPacketGate'));
    expect(manualProcessChecklist, contains('m17ExecutionRehearsalGate'));
    expect(manualProcessChecklist, contains('m18ExecutionHandoffGate'));
    expect(manualProcessChecklist, contains('m20ExecutionResultIntakeGate'));
    expect(manualProcessChecklist, contains('m22PostActionReviewGate'));
    expect(manualProcessChecklist, contains('m23CycleOutcomeHandoffGate'));
    expect(manualProcessChecklist, contains('m25NextCycleSeedHandoffGate'));
    expect(manualProcessChecklist, contains('m26ObserveRestartPacketGate'));
    expect(manualProcessChecklist, contains('m27ScreenshotRequestHandoffGate'));
    expect(manualProcessChecklist, contains('m28ScreenshotEvidenceIntakeGate'));
    expect(manualProcessChecklist, contains('m29ObserveCanaryRunPacketGate'));
    expect(manualProcessChecklist, contains('m30ObserveResultIntakeGate'));
    expect(manualProcessChecklist, contains('m15_llm_review_canary'));
    expect(manualProcessChecklist, contains('m17_execution_rehearsal'));
    expect(manualProcessChecklist, contains('actionTimeConfirmations'));
    expect(manualProcessChecklist, contains('approvalBlockers'));
    expect(manualProcessChecklist, contains('blocked_review_evidence'));
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m15_llm_review_canary.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m16_approval_packet.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m18_execution_handoff.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m20_execution_result_intake.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m22_post_action_review.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m26_observe_restart_packet.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m27_screenshot_request_handoff.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m29_observe_canary_run_packet.sh'),
    );
    expect(
      manualProcessChecklist,
      contains('tool/run_macos_computer_use_m17_execution_rehearsal.sh'),
    );
    expect(manualProcessChecklist, contains('PR Review Summary'));
    expect(manualProcessChecklist, contains('blockedReviewEvidence: none'));
    expect(
      manualProcessChecklist,
      contains('reviewGateConsistency.status: consistent'),
    );
    expect(manualProcessChecklist, contains('reviewTargetCounts'));
    expect(manualProcessChecklist, contains('exactTextCandidates'));
    expect(manualProcessChecklist, contains('textEntryTargets'));
    expect(manualProcessChecklist, contains('publicActionTargets'));
    expect(manualProcessChecklist, contains('user-reported'));
    expect(manualProcessChecklist, contains('runtime result evidence'));
    expect(
      manualProcessChecklist,
      contains('confirmation_requirements_documented'),
    );
    expect(manualProcessChecklist, contains('observe_only_no_mutation'));
    expect(manualProcessChecklist, contains('confirmationRequirements'));
    expect(manualProcessChecklist, contains('actionPlan'));
    expect(
      manualProcessChecklist,
      contains('Do not automate app navigation, clicking, typing'),
    );
  });

  test(
    'MVP sign-off dry run validates provided manual artifact paths',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_signoff_dry_run_paths_',
      );
      try {
        final desktopSummary = File('${root.path}/canary_summary.json')
          ..writeAsStringSync('{"ok":true}\n');
        final missingManualReport = '${root.path}/missing_manual_tcc.json';

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_signoff.sh',
          '--dry-run',
          '--root',
          root.path,
          '--manual-tcc-report',
          missingManualReport,
          '--desktop-action-canary-summary',
          desktopSummary.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final stdout = '${result.stdout}';
        expect(stdout, contains('Manual TCC status: provided path not found'));
        expect(stdout, contains('Desktop action canary status: provided'));
        expect(stdout, contains('LLM canary status: discovery only'));
        expect(stdout, contains(_llmCanaryNextAction));
        expect(stdout, contains('--manual-tcc-report $missingManualReport'));
        expect(
          stdout,
          contains('--desktop-action-canary-summary ${desktopSummary.path}'),
        );

        final handoff = File(
          '${root.path}/macos_computer_use_mvp_handoff.md',
        ).readAsStringSync();
        expect(handoff, contains('Manual TCC status: provided path not found'));
        expect(handoff, contains('Desktop action canary status: provided'));
        expect(handoff, contains(_llmCanaryNextAction));
        expect(handoff, contains(missingManualReport));
        expect(handoff, contains(desktopSummary.path));
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('MVP sign-off dry run discovers current artifact paths', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_discovered_',
    );
    try {
      File(
        '${root.path}/macos_computer_use_release_artifact_signoff.json',
      ).writeAsStringSync('''
{
  "releaseSignoffGate": {
    "status": "ready",
    "blockers": [],
    "nextAction": "M7 release artifact sign-off is complete."
  }
}
''');
      File(
        '${root.path}/macos_computer_use_canary_history.json',
      ).writeAsStringSync('''
{
  "schemaName": "macos_computer_use_canary_history",
  "stable": true,
  "runCount": 1
}
''');
      final manualDir = Directory(
        '${root.path}/macos_computer_use_manual_tcc_1',
      )..createSync();
      final manualSummary =
          File('${manualDir.path}/manual_tcc_report_summary.json')
            ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_manual_tcc_report_summary",
  "ready": true,
  "status": "ready",
  "blockers": [],
  "checks": []
}
''');
      final desktopDir = Directory(
        '${root.path}/macos_computer_use_desktop_action_canary_1',
      )..createSync();
      final desktopSummary = File('${desktopDir.path}/canary_summary.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_desktop_action_canary_summary",
  "stable": true,
  "runCount": 1,
  "failed": 0,
  "expectedPhases": [
    "pre_observe_image",
    "click_sent",
    "post_observe_image"
  ],
  "safeTargetGuidance": [
    "Use a visible, harmless target.",
    "Avoid destructive controls."
  ],
  "runs": [
    {
      "name": "run_01",
      "status": "passed",
      "failureClass": "passed",
      "phaseStatus": {
        "preObserve": "ready",
        "click": "sent",
        "postObserve": "ready",
        "changedEvidence": "observed"
      }
    }
  ]
}
''');
      final llmDir = Directory(
        '${root.path}/macos_computer_use_mvp_fixture_vision_llm_canary_1',
      )..createSync();
      File('${llmDir.path}/canary_summary.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_mvp_fixture_vision_llm_canary_summary",
  "purpose": "computer_use_mvp_fixture_vision_llm_canary",
  "runCount": 1,
  "failedCount": 0,
  "mvpEvidenceGate": {
    "status": "ready",
    "ready": true,
    "checks": [
      {
        "id": "safe_click_plan",
        "ok": true,
        "nextAction": "No action required."
      }
    ],
    "blockers": []
  },
  "expectedUserOperatedRuntimePhases": [
    "pre_observe_image",
    "click_sent",
    "post_observe_image",
    "destructive_target_refused"
  ]
}
''');
      final realAppObserveDir = Directory(
        '${root.path}/macos_computer_use_real_app_observe_canary_1',
      )..createSync();
      final realAppObserveSummary =
          File('${realAppObserveDir.path}/canary_summary.json')
            ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_real_app_observe_canary_summary",
  "purpose": "computer_use_real_app_observe_canary",
  "milestone": "M14",
  "runCount": 1,
  "failedCount": 0,
  "targetApp": "Safari",
  "observedApp": "Safari",
  "m14EvidenceGate": {
    "status": "ready",
    "ready": true,
    "checks": [
      {
        "id": "text_field_targets_classified",
        "ok": true,
        "nextAction": "No action required."
      },
      {
        "id": "confirmation_requirements_documented",
        "ok": true,
        "nextAction": "No action required."
      },
      {
        "id": "observe_only_no_mutation",
        "ok": true,
        "nextAction": "No action required."
      }
    ],
    "blockers": []
  }
}
''');
      final m15Dir = Directory(
        '${root.path}/macos_computer_use_m15_action_proposal_handoff_1',
      )..createSync();
      final m15Handoff = File('${m15Dir.path}/action_proposal_handoff.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "previousMilestone": "M14",
  "ready": true,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "textEntryTargets": [
    {
      "label": "What's happening?",
      "role": "compose_text_field",
      "risk": "input"
    }
  ],
  "publicActionTargets": [
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action"
    }
  ],
  "exactTextCandidates": [
    {
      "source": "targetIntent",
      "text": "Good morning from Caverno",
      "status": "requires_user_approval"
    }
  ],
  "approvalBoundActionProposal": [
    {
      "phase": "confirm_exact_text",
      "status": "requires_user_approval",
      "reason": "The user must approve the exact text before typing."
    },
    {
      "phase": "confirm_public_action",
      "status": "requires_separate_user_approval",
      "reason": "The user must approve the final public Post control."
    }
  ],
  "prReviewSummary": {
    "status": "ready_for_review",
    "ready": true,
    "sourceEvidence": "m14_real_app_observe_canary",
    "blockedReviewEvidence": [],
    "requiredConfirmations": [
      "observe_again",
      "confirm_exact_text",
      "confirm_target",
      "confirm_public_action"
    ]
  },
  "m15ActionProposalGate": {
    "status": "ready",
    "ready": true,
    "checks": [
      {
        "id": "m14_evidence_ready",
        "ok": true,
        "nextAction": "No action required."
      }
    ],
    "blockers": [],
    "nextAction": "M15 action proposal handoff is ready for user review."
  }
}
''');
      final m15LlmReviewDir = Directory(
        '${root.path}/macos_computer_use_m15_llm_review_canary_1',
      )..createSync();
      final m15LlmReviewSummary =
          File('${m15LlmReviewDir.path}/canary_summary.json')
            ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_llm_review_canary_summary",
  "schemaVersion": 1,
  "purpose": "computer_use_m15_llm_review_canary",
  "milestone": "M15",
  "sourceHandoff": "${m15Handoff.path}",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "llmBoundary": "review_only_no_tool_execution",
  "runCount": 1,
  "passedCount": 1,
  "failedCount": 0,
  "boundaryDecision": "approval_required_before_action",
  "m15LlmReviewGate": {
    "status": "ready",
    "ready": true,
    "blockers": [],
    "nextAction": "M15 LLM review canary is ready for user review."
  },
  "runs": [
    {
      "name": "run_01",
      "status": "passed",
      "failureClass": "passed",
      "boundaryDecision": "approval_required_before_action"
    }
  ]
}
''');
      final m16Dir = Directory(
        '${root.path}/macos_computer_use_m16_approval_packet_1',
      )..createSync();
      final m16ApprovalPacket = File('${m16Dir.path}/approval_packet.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m16_approval_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m16_approval_packet",
  "milestone": "M16",
  "previousMilestone": "M15",
  "ready": true,
  "approvalStatus": "pending_user_approval",
  "executionBoundary": "no_desktop_action_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "sourceM15Handoff": "${m15Handoff.path}",
  "sourceM15LlmReview": "${m15LlmReviewSummary.path}",
  "exactTextCandidates": [
    {
      "source": "targetIntent",
      "text": "Good morning from Caverno",
      "status": "requires_user_approval"
    }
  ],
  "textEntryTargets": [
    {
      "label": "What's happening?",
      "role": "compose_text_field",
      "risk": "input"
    }
  ],
  "publicActionTargets": [
    {
      "label": "Post",
      "role": "public_submit",
      "risk": "public_action"
    }
  ],
  "requiredApprovals": [
    {
      "id": "observe_again",
      "required": true,
      "status": "read_only_allowed"
    },
    {
      "id": "exact_text",
      "required": true,
      "status": "pending_user_approval"
    },
    {
      "id": "target_label",
      "required": true,
      "status": "pending_user_approval"
    },
    {
      "id": "public_action_label",
      "required": true,
      "status": "pending_separate_user_approval"
    }
  ],
  "approvalBlockers": [
    "exact_text",
    "target_label",
    "public_action_label"
  ],
  "m16ApprovalPacketGate": {
    "status": "ready",
    "ready": true,
    "checks": [
      {
        "id": "m15_handoff_ready",
        "ok": true,
        "nextAction": "No action required."
      }
    ],
    "blockers": [],
    "approvalStatus": "pending_user_approval",
    "approvalBlockers": [
      "exact_text",
      "target_label",
      "public_action_label"
    ],
    "nextAction": "Ask the user to approve exact text, target, and any public action before the future execution milestone."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('Manual TCC status: discovered'));
      expect(stdout, contains('Desktop action canary status: discovered'));
      expect(stdout, contains('LLM canary status: discovered'));
      expect(stdout, contains('M15 action proposal status: ready'));
      expect(stdout, contains('M15 LLM review status: ready'));
      expect(stdout, contains('M16 approval packet status: ready'));
      expect(stdout, contains('M17 execution rehearsal status: missing'));
      expect(
        stdout,
        contains('M16 approval packet approval status: pending_user_approval'),
      );
      expect(
        stdout,
        contains(
          'M15 action proposal next action: M15 action proposal handoff is ready for user review.',
        ),
      );
      expect(stdout, contains('LLM evidence gate: ready'));
      expect(stdout, contains('LLM evidence blockers: none'));
      expect(stdout, contains('Final MVP aggregation command:'));
      expect(stdout, contains('Status: ready_for_final_aggregation'));
      expect(
        stdout,
        contains(
          'Ready input evidence: manual_tcc, desktop_action_canary, llm_canary',
        ),
      );
      expect(stdout, contains('Missing input evidence: none'));
      expect(stdout, contains('Pending user-operated evidence: none'));
      expect(stdout, contains('Pending automation-safe evidence: none'));
      expect(stdout, contains('Blocked review evidence: none'));
      expect(
        stdout,
        contains(
          'bash tool/run_macos_computer_use_mvp_signoff.sh --final-signoff',
        ),
      );
      expect(stdout, contains('--manual-tcc-report ${manualSummary.path}'));
      expect(
        stdout,
        contains('--desktop-action-canary-summary ${desktopSummary.path}'),
      );
      expect(
        stdout,
        contains('--llm-canary-summary ${realAppObserveSummary.path}'),
      );
      expect(
        stdout,
        contains(
          'all required input evidence was provided or discovered by this wrapper',
        ),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('Manual TCC status: discovered'));
      expect(handoff, contains('Desktop action canary status: discovered'));
      expect(handoff, contains('LLM canary status: discovered'));
      expect(handoff, contains('M15 action proposal status: ready'));
      expect(handoff, contains('M15 LLM review status: ready'));
      expect(handoff, contains('M16 approval packet status: ready'));
      expect(handoff, contains('M17 execution rehearsal status: missing'));
      expect(handoff, contains('Optional Review Evidence'));
      expect(handoff, contains('M15 Action Proposal Evidence'));
      expect(handoff, contains('M15 LLM Review Evidence'));
      expect(handoff, contains('M16 Approval Packet Evidence'));
      expect(handoff, contains('M17 Execution Rehearsal Evidence'));
      expect(handoff, contains('M15 action proposal blockers: none'));
      expect(handoff, contains('M15 LLM review blockers: none'));
      expect(handoff, contains('M16 approval packet blockers: none'));
      expect(
        handoff,
        contains(
          'M17 execution rehearsal blockers: missing_m17_execution_rehearsal',
        ),
      );
      expect(
        handoff,
        contains(
          'M16 approval packet approval blockers: exact_text, target_label, public_action_label',
        ),
      );
      expect(
        handoff,
        contains('| exact_text | true | pending_user_approval | - |'),
      );
      expect(
        handoff,
        contains(
          'M15 LLM review boundary decision: approval_required_before_action',
        ),
      );
      expect(
        handoff,
        contains('M15 action proposal PR review status: ready_for_review'),
      );
      expect(
        handoff,
        contains('M15 action proposal blocked review evidence: none'),
      );
      expect(
        handoff,
        contains(
          'M15 action proposal review target counts: textEntryTargets=1, publicActionTargets=1, exactTextCandidates=1',
        ),
      );
      expect(
        handoff,
        contains('| confirm_exact_text | requires_user_approval |'),
      );
      expect(
        handoff,
        contains('| confirm_public_action | requires_separate_user_approval |'),
      );
      expect(handoff, contains('### M15 Review Targets'));
      expect(
        handoff,
        contains('| What\'s happening? | compose_text_field | input |'),
      );
      expect(handoff, contains('| Post | public_submit | public_action |'));
      expect(
        handoff,
        contains(
          '| Good morning from Caverno | targetIntent | requires_user_approval |',
        ),
      );
      expect(handoff, contains('LLM Evidence Gate'));
      expect(handoff, contains('M14 evidence gate: ready'));
      expect(handoff, contains('PR Review Summary'));
      expect(handoff, contains('Status: ready_for_final_aggregation'));
      expect(
        handoff,
        contains(
          'Ready input evidence: manual_tcc, desktop_action_canary, llm_canary',
        ),
      );
      expect(handoff, contains('Missing input evidence: none'));
      expect(handoff, contains('Blocked review evidence: none'));
      expect(handoff, contains('text_field_targets_classified'));
      expect(handoff, contains('confirmation_requirements_documented'));
      expect(handoff, contains('observe_only_no_mutation'));
      expect(handoff, contains('Desktop Action Evidence'));
      expect(handoff, contains('Desktop action status: passed'));
      expect(handoff, contains('Final MVP Aggregation Command'));
      expect(
        handoff,
        contains(
          'bash tool/run_macos_computer_use_mvp_signoff.sh --final-signoff',
        ),
      );
      expect(handoff, contains('`pre_observe_image`'));
      expect(handoff, contains('Use a visible, harmless target.'));
      expect(handoff, contains('| run_01 | passed | passed |'));
      expect(handoff, contains('| ready | sent | ready | observed |'));
      expect(handoff, contains(manualSummary.path));
      expect(handoff, contains(desktopSummary.path));
      expect(handoff, contains(realAppObserveSummary.path));
      expect(handoff, contains(m15Handoff.path));
      expect(handoff, contains(m15LlmReviewSummary.path));
      expect(handoff, contains(m16ApprovalPacket.path));
      expect(
        handoff,
        contains(
          'No required input evidence is missing from this wrapper invocation.',
        ),
      );

      final handoffCommand = RegExp(
        r'```bash\n(bash tool/run_macos_computer_use_mvp_signoff\.sh --final-signoff[^\n]*)\n```',
      ).firstMatch(handoff)?.group(1);
      expect(handoffCommand, isNotNull);

      final artifactIndexResult = await Process.run('dart', [
        'run',
        'tool/macos_computer_use_readiness_artifact_index.dart',
        '--root',
        root.path,
      ]);
      expect(
        artifactIndexResult.exitCode,
        0,
        reason: '${artifactIndexResult.stdout}\n${artifactIndexResult.stderr}',
      );
      expect(
        '${artifactIndexResult.stdout}',
        contains('MVP final sign-off rehearsal: ready'),
      );
      final artifactIndex =
          jsonDecode(
                File(
                  '${root.path}/macos_computer_use_readiness_artifact_index.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final rehearsal =
          artifactIndex['mvpFinalSignoffRehearsal'] as Map<String, dynamic>;
      expect(rehearsal['ready'], isTrue);
      expect(rehearsal['finalAggregationCommand'], handoffCommand);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run surfaces blocked M15 proposal evidence', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m15_blocked_',
    );
    try {
      final m15Dir = Directory(
        '${root.path}/macos_computer_use_m15_action_proposal_handoff_1',
      )..createSync();
      File('${m15Dir.path}/action_proposal_handoff.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "previousMilestone": "M14",
  "ready": false,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "prReviewSummary": {
    "status": "blocked_pending_review_evidence",
    "ready": false,
    "sourceEvidence": "m14_real_app_observe_canary",
    "blockedReviewEvidence": ["m14_evidence_ready"],
    "requiredConfirmations": [
      "observe_again",
      "confirm_exact_text",
      "confirm_target",
      "confirm_public_action"
    ]
  },
  "m15ActionProposalGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "m14_evidence_ready",
        "ok": false,
        "nextAction": "Run the M14 real-app observe canary until ready."
      }
    ],
    "blockers": ["m14_evidence_ready"],
    "nextAction": "Resolve blocked M15 handoff checks before proposing any action."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M15 action proposal status: blocked'));
      expect(
        stdout,
        contains(
          'M15 action proposal next action: Resolve blocked M15 handoff checks before proposing any action.',
        ),
      );
      expect(
        stdout,
        contains('Blocked review evidence: m15_action_proposal_handoff'),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('M15 Action Proposal Evidence'));
      expect(handoff, contains('M15 action proposal status: blocked'));
      expect(
        handoff,
        contains('M15 action proposal blockers: m14_evidence_ready'),
      );
      expect(
        handoff,
        contains(
          'M15 action proposal PR review status: blocked_pending_review_evidence',
        ),
      );
      expect(
        handoff,
        contains(
          'M15 action proposal blocked review evidence: m14_evidence_ready',
        ),
      );
      expect(handoff, contains('| m14_evidence_ready | blocked |'));
      expect(
        handoff,
        contains(
          'Missing input evidence: manual_tcc, desktop_action_canary, llm_canary',
        ),
      );
      expect(
        handoff,
        contains('Blocked review evidence: m15_action_proposal_handoff'),
      );
      expect(
        handoff,
        contains(
          'Resolve blocked M15 handoff checks before proposing any action.',
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run blocks inconsistent M15 review evidence', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m15_review_blocked_',
    );
    try {
      final m15Dir = Directory(
        '${root.path}/macos_computer_use_m15_action_proposal_handoff_1',
      )..createSync();
      File('${m15Dir.path}/action_proposal_handoff.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "previousMilestone": "M14",
  "ready": true,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "prReviewSummary": {
    "status": "blocked_pending_review_evidence",
    "ready": false,
    "sourceEvidence": "m14_real_app_observe_canary",
    "blockedReviewEvidence": ["review_consistency_failed"]
  },
  "m15ActionProposalGate": {
    "status": "ready",
    "ready": true,
    "checks": [
      {
        "id": "m14_evidence_ready",
        "ok": true,
        "nextAction": "No action required."
      }
    ],
    "blockers": [],
    "nextAction": "M15 action proposal handoff is ready for user review."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M15 action proposal status: blocked'));
      expect(
        stdout,
        contains(
          'M15 action proposal next action: Resolve blocked M15 review evidence before proposing any action.',
        ),
      );
      expect(
        stdout,
        contains('Blocked review evidence: m15_action_proposal_handoff'),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(
        handoff,
        contains(
          'M15 action proposal PR review status: blocked_pending_review_evidence',
        ),
      );
      expect(
        handoff,
        contains(
          'M15 action proposal blocked review evidence: review_consistency_failed',
        ),
      );
      expect(
        handoff,
        contains('Blocked review evidence: m15_action_proposal_handoff'),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run blocks inconsistent M15 review gate', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m15_consistency_blocked_',
    );
    try {
      final m15Dir = Directory(
        '${root.path}/macos_computer_use_m15_action_proposal_handoff_1',
      )..createSync();
      File('${m15Dir.path}/action_proposal_handoff.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "previousMilestone": "M14",
  "ready": true,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "prReviewSummary": {
    "status": "ready_for_review",
    "ready": true,
    "sourceEvidence": "m14_real_app_observe_canary",
    "blockedReviewEvidence": []
  },
  "reviewGateConsistency": {
    "ok": false,
    "status": "inconsistent",
    "nextAction": "Resolve inconsistent M15 review and gate evidence before proposing any action."
  },
  "m15ActionProposalGate": {
    "status": "ready",
    "ready": true,
    "checks": [
      {
        "id": "m14_evidence_ready",
        "ok": true,
        "nextAction": "No action required."
      }
    ],
    "blockers": [],
    "nextAction": "M15 action proposal handoff is ready for user review."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M15 action proposal status: blocked'));
      expect(
        stdout,
        contains(
          'M15 action proposal next action: Resolve inconsistent M15 review and gate evidence before proposing any action.',
        ),
      );
      expect(
        stdout,
        contains('Blocked review evidence: m15_action_proposal_handoff'),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(
        handoff,
        contains('M15 action proposal review/gate consistency: inconsistent'),
      );
      expect(
        handoff,
        contains(
          'Resolve inconsistent M15 review and gate evidence before proposing any action.',
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run blocks failed M15 LLM review canary', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m15_llm_review_blocked_',
    );
    try {
      final m15Dir = Directory(
        '${root.path}/macos_computer_use_m15_action_proposal_handoff_1',
      )..createSync();
      final m15Handoff = File('${m15Dir.path}/action_proposal_handoff.json')
        ..writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_action_proposal_handoff",
  "milestone": "M15",
  "previousMilestone": "M14",
  "ready": true,
  "llmBoundary": "no_llm_call",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "prReviewSummary": {
    "status": "ready_for_review",
    "ready": true,
    "sourceEvidence": "m14_real_app_observe_canary",
    "blockedReviewEvidence": []
  },
  "m15ActionProposalGate": {
    "status": "ready",
    "ready": true,
    "checks": [
      {
        "id": "m14_evidence_ready",
        "ok": true,
        "nextAction": "No action required."
      }
    ],
    "blockers": [],
    "nextAction": "M15 action proposal handoff is ready for user review."
  }
}
''');
      final m15ReviewDir = Directory(
        '${root.path}/macos_computer_use_m15_llm_review_canary_1',
      )..createSync();
      File('${m15ReviewDir.path}/canary_summary.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m15_llm_review_canary_summary",
  "schemaVersion": 1,
  "purpose": "computer_use_m15_llm_review_canary",
  "milestone": "M15",
  "sourceHandoff": "${m15Handoff.path}",
  "tccBoundary": "no_tcc_operation",
  "desktopActionBoundary": "no_desktop_action",
  "llmBoundary": "review_only_no_tool_execution",
  "runCount": 1,
  "passedCount": 0,
  "failedCount": 1,
  "boundaryDecision": "execute_now",
  "m15LlmReviewGate": {
    "status": "blocked",
    "ready": false,
    "blockers": ["approval_boundary_missing"],
    "nextAction": "Resolve M15 LLM review boundary failures before any action proposal execution."
  },
  "runs": [
    {
      "name": "run_01",
      "status": "failed",
      "failureClass": "approval_boundary_missing",
      "boundaryDecision": "execute_now"
    }
  ]
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M15 action proposal status: ready'));
      expect(stdout, contains('M15 LLM review status: blocked'));
      expect(
        stdout,
        contains(
          'M15 LLM review next action: Resolve M15 LLM review boundary failures before any action proposal execution.',
        ),
      );
      expect(
        stdout,
        contains('Blocked review evidence: m15_llm_review_canary'),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('M15 LLM Review Evidence'));
      expect(handoff, contains('M15 LLM review status: blocked'));
      expect(
        handoff,
        contains('M15 LLM review blockers: approval_boundary_missing'),
      );
      expect(
        handoff,
        contains('M15 LLM review boundary decision: execute_now'),
      );
      expect(
        handoff,
        contains(
          '| run_01 | failed | approval_boundary_missing | execute_now |',
        ),
      );
      expect(
        handoff,
        contains('Blocked review evidence: m15_llm_review_canary'),
      );
      expect(
        handoff,
        contains(
          'Resolve M15 LLM review boundary failures before any action proposal execution.',
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run surfaces blocked M16 approval packet', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m16_blocked_',
    );
    try {
      final m16Dir = Directory(
        '${root.path}/macos_computer_use_m16_approval_packet_1',
      )..createSync();
      File('${m16Dir.path}/approval_packet.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m16_approval_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m16_approval_packet",
  "milestone": "M16",
  "previousMilestone": "M15",
  "ready": false,
  "approvalStatus": "blocked",
  "executionBoundary": "no_desktop_action_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "approvalBlockers": ["m15_handoff_ready"],
  "m16ApprovalPacketGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "m15_handoff_ready",
        "ok": false,
        "nextAction": "Run the M15 action proposal handoff until m15ActionProposalGate.status is ready."
      }
    ],
    "blockers": ["m15_handoff_ready"],
    "approvalStatus": "blocked",
    "approvalBlockers": ["m15_handoff_ready"],
    "nextAction": "Resolve blocked M15 evidence before preparing the M16 approval packet."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M16 approval packet status: blocked'));
      expect(
        stdout,
        contains(
          'M16 approval packet next action: Resolve blocked M15 evidence before preparing the M16 approval packet.',
        ),
      );
      expect(stdout, contains('Blocked review evidence: m16_approval_packet'));

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('M16 Approval Packet Evidence'));
      expect(handoff, contains('M16 approval packet status: blocked'));
      expect(
        handoff,
        contains('M16 approval packet blockers: m15_handoff_ready'),
      );
      expect(
        handoff,
        contains('M16 approval packet approval blockers: m15_handoff_ready'),
      );
      expect(handoff, contains('| m15_handoff_ready | blocked |'));
      expect(handoff, contains('Blocked review evidence: m16_approval_packet'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run surfaces blocked M17 execution rehearsal', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m17_blocked_',
    );
    try {
      final m17Dir = Directory(
        '${root.path}/macos_computer_use_m17_execution_rehearsal_1',
      )..createSync();
      File('${m17Dir.path}/execution_rehearsal.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m17_execution_rehearsal",
  "schemaVersion": 1,
  "purpose": "computer_use_m17_execution_rehearsal",
  "milestone": "M17",
  "previousMilestone": "M16",
  "ready": false,
  "approvalStatus": "pending_user_approval",
  "executionBoundary": "no_desktop_action_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "executionPhases": [
    {
      "id": "observe_again",
      "mode": "read_only",
      "approved": true
    },
    {
      "id": "type_exact_text",
      "mode": "future_user_approved_input",
      "approved": false
    }
  ],
  "m17ExecutionRehearsalGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "approval_status_approved",
        "ok": false,
        "nextAction": "Ask the user to approve every required M16 approval before any execution rehearsal advances."
      }
    ],
    "blockers": ["approval_status_approved"],
    "nextAction": "Resolve blocked M17 rehearsal checks before future execution."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M17 execution rehearsal status: blocked'));
      expect(
        stdout,
        contains(
          'M17 execution rehearsal next action: Resolve blocked M17 rehearsal checks before future execution.',
        ),
      );
      expect(
        stdout,
        contains('Blocked review evidence: m17_execution_rehearsal'),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('M17 Execution Rehearsal Evidence'));
      expect(handoff, contains('M17 execution rehearsal status: blocked'));
      expect(
        handoff,
        contains('M17 execution rehearsal blockers: approval_status_approved'),
      );
      expect(handoff, contains('| approval_status_approved | blocked |'));
      expect(
        handoff,
        contains('Blocked review evidence: m17_execution_rehearsal'),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run surfaces blocked M18 execution handoff', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m18_blocked_',
    );
    try {
      final m18Dir = Directory(
        '${root.path}/macos_computer_use_m18_execution_handoff_1',
      )..createSync();
      File('${m18Dir.path}/execution_handoff.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m18_execution_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m18_execution_handoff",
  "milestone": "M18",
  "previousMilestone": "M17",
  "ready": false,
  "executionBoundary": "user_operated_runtime_handoff",
  "desktopActionBoundary": "user_operated_only",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "actionTimeConfirmations": [
    {
      "id": "confirm_target_label",
      "required": true,
      "approvedBeforeRun": false
    }
  ],
  "executionChecklist": [
    {
      "id": "fresh_observation",
      "operator": "user",
      "mode": "read_only"
    }
  ],
  "m18ExecutionHandoffGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "target_confirmation_ready",
        "ok": false,
        "nextAction": "Return to M16/M17 and approve the target label before runtime handoff."
      }
    ],
    "blockers": ["target_confirmation_ready"],
    "nextAction": "Resolve M18 handoff blockers before preparing any runtime execution step."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M18 execution handoff status: blocked'));
      expect(
        stdout,
        contains(
          'M18 execution handoff next action: Resolve M18 handoff blockers before preparing any runtime execution step.',
        ),
      );
      expect(
        stdout,
        contains('Blocked review evidence: m18_execution_handoff'),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('M18 Execution Handoff Evidence'));
      expect(handoff, contains('M18 execution handoff status: blocked'));
      expect(
        handoff,
        contains('M18 execution handoff blockers: target_confirmation_ready'),
      );
      expect(handoff, contains('| target_confirmation_ready | blocked |'));
      expect(
        handoff,
        contains('Blocked review evidence: m18_execution_handoff'),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run surfaces blocked M20 result intake', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m20_blocked_',
    );
    try {
      final m20Dir = Directory(
        '${root.path}/macos_computer_use_m20_execution_result_intake_1',
      )..createSync();
      File('${m20Dir.path}/execution_result_intake.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m20_execution_result_intake",
  "schemaVersion": 1,
  "purpose": "computer_use_m20_execution_result_intake",
  "milestone": "M20",
  "previousMilestone": "M18",
  "ready": false,
  "sourceM18ExecutionHandoff": "/tmp/execution_handoff.json",
  "executionBoundary": "manual_result_intake_report_only",
  "desktopActionBoundary": "user_operated_evidence_only",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "manualInputs": {
    "freshObservation": "done",
    "targetConfirmed": "yes",
    "exactTextConfirmed": "yes",
    "publicActionConfirmed": "yes",
    "runtimeAction": "failed",
    "postActionObservation": "missing"
  },
  "resultSequence": [
    {
      "id": "runtime_action",
      "required": true,
      "status": "failed"
    }
  ],
  "m20ExecutionResultIntakeGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "runtime_action_succeeded",
        "ok": false,
        "nextAction": "Record a succeeded user-operated runtime action before marking M20 ready."
      }
    ],
    "blockers": ["runtime_action_succeeded"],
    "nextAction": "Resolve M20 result intake blockers before accepting runtime evidence."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M20 execution result intake status: blocked'));
      expect(
        stdout,
        contains(
          'M20 execution result intake next action: Resolve M20 result intake blockers before accepting runtime evidence.',
        ),
      );
      expect(
        stdout,
        contains('Blocked review evidence: m20_execution_result_intake'),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('M20 Execution Result Intake Evidence'));
      expect(handoff, contains('M20 execution result intake status: blocked'));
      expect(
        handoff,
        contains(
          'M20 execution result intake blockers: runtime_action_succeeded',
        ),
      );
      expect(handoff, contains('| runtime_action_succeeded | blocked |'));
      expect(
        handoff,
        contains('Blocked review evidence: m20_execution_result_intake'),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('MVP sign-off dry run surfaces blocked M22 post-action review', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_dry_run_m22_blocked_',
    );
    try {
      final m22Dir = Directory(
        '${root.path}/macos_computer_use_m22_post_action_review_1',
      )..createSync();
      File('${m22Dir.path}/post_action_review.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m22_post_action_review",
  "schemaVersion": 1,
  "purpose": "computer_use_m22_post_action_review",
  "milestone": "M22",
  "previousMilestone": "M20",
  "ready": false,
  "sourceM20ExecutionResultIntake": "/tmp/execution_result_intake.json",
  "executionBoundary": "post_action_review_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "reviewInputs": {
    "resultReviewed": "no",
    "postActionState": "unknown",
    "followUpRequired": "yes",
    "followUpNote": ""
  },
  "nextCycleRecommendation": "start_new_observe_action_cycle",
  "m22PostActionReviewGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "result_reviewed",
        "ok": false,
        "nextAction": "Ask the user to review the M20 runtime result before marking M22 ready."
      }
    ],
    "blockers": ["result_reviewed"],
    "nextAction": "Resolve M22 post-action review blockers before closing the action cycle."
  }
}
''');

      final result = await Process.run('bash', [
        'tool/run_macos_computer_use_mvp_signoff.sh',
        '--dry-run',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('M22 post-action review status: blocked'));
      expect(
        stdout,
        contains(
          'M22 post-action review next action: Resolve M22 post-action review blockers before closing the action cycle.',
        ),
      );
      expect(
        stdout,
        contains('Blocked review evidence: m22_post_action_review'),
      );

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('M22 Post-Action Review Evidence'));
      expect(handoff, contains('M22 post-action review status: blocked'));
      expect(
        handoff,
        contains('M22 post-action review blockers: result_reviewed'),
      );
      expect(handoff, contains('| result_reviewed | blocked |'));
      expect(
        handoff,
        contains('Blocked review evidence: m22_post_action_review'),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'MVP sign-off dry run surfaces blocked M23 cycle outcome handoff',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_signoff_dry_run_m23_blocked_',
      );
      try {
        final m23Dir = Directory(
          '${root.path}/macos_computer_use_m23_cycle_outcome_handoff_1',
        )..createSync();
        File('${m23Dir.path}/cycle_outcome_handoff.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m23_cycle_outcome_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m23_cycle_outcome_handoff",
  "milestone": "M23",
  "previousMilestone": "M22",
  "ready": false,
  "sourceM22PostActionReview": "/tmp/post_action_review.json",
  "executionBoundary": "cycle_outcome_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "sourceNextCycleRecommendation": "start_new_observe_action_cycle",
  "cycleOutcome": "unknown",
  "handoffInputs": {
    "outcomeAccepted": "no",
    "nextObserveNeeded": "unknown"
  },
  "nextObserveSeed": {
    "required": false,
    "source": "m23_cycle_outcome_handoff",
    "note": "",
    "returnMilestone": null,
    "boundary": "observe_only_no_desktop_action"
  },
  "m23CycleOutcomeHandoffGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "outcome_accepted",
        "ok": false,
        "nextAction": "Ask the user to accept the reviewed M22 outcome before closing or restarting the cycle."
      }
    ],
    "blockers": ["outcome_accepted"],
    "nextAction": "Resolve M23 cycle outcome blockers before closing or restarting the action cycle."
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_signoff.sh',
          '--dry-run',
          '--root',
          root.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final stdout = '${result.stdout}';
        expect(stdout, contains('M23 cycle outcome handoff status: blocked'));
        expect(
          stdout,
          contains(
            'M23 cycle outcome handoff next action: Resolve M23 cycle outcome blockers before closing or restarting the action cycle.',
          ),
        );
        expect(
          stdout,
          contains('Blocked review evidence: m23_cycle_outcome_handoff'),
        );

        final handoff = File(
          '${root.path}/macos_computer_use_mvp_handoff.md',
        ).readAsStringSync();
        expect(handoff, contains('M23 Cycle Outcome Handoff Evidence'));
        expect(handoff, contains('M23 cycle outcome handoff status: blocked'));
        expect(
          handoff,
          contains('M23 cycle outcome handoff blockers: outcome_accepted'),
        );
        expect(handoff, contains('| outcome_accepted | blocked |'));
        expect(
          handoff,
          contains('Blocked review evidence: m23_cycle_outcome_handoff'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'MVP sign-off dry run surfaces blocked M25 next-cycle seed handoff',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_signoff_dry_run_m25_blocked_',
      );
      try {
        final m25Dir = Directory(
          '${root.path}/macos_computer_use_m25_next_cycle_seed_handoff_1',
        )..createSync();
        File('${m25Dir.path}/next_cycle_seed_handoff.json').writeAsStringSync(
          '''
{
  "schemaName": "macos_computer_use_m25_next_cycle_seed_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m25_next_cycle_seed_handoff",
  "milestone": "M25",
  "previousMilestone": "M23",
  "ready": false,
  "sourceM23CycleOutcomeHandoff": "/tmp/cycle_outcome_handoff.json",
  "executionBoundary": "next_cycle_seed_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "sourceCycleOutcome": "restart_observe_action_cycle",
  "seedInputs": {
    "seedAccepted": "no"
  },
  "nextCycleSeed": {
    "required": true,
    "source": "m25_next_cycle_seed_handoff",
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "note": "Observe the next target.",
    "requiresNewApprovalCycle": true
  },
  "m25NextCycleSeedHandoffGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "seed_accepted",
        "ok": false,
        "nextAction": "Ask the user to accept the next M14 seed before preparing follow-up evidence."
      }
    ],
    "blockers": ["seed_accepted"],
    "nextAction": "Resolve M25 next-cycle seed blockers before starting the next observe-only pass."
  }
}
''',
        );

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_signoff.sh',
          '--dry-run',
          '--root',
          root.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final stdout = '${result.stdout}';
        expect(stdout, contains('M25 next-cycle seed handoff status: blocked'));
        expect(
          stdout,
          contains(
            'M25 next-cycle seed handoff next action: Resolve M25 next-cycle seed blockers before starting the next observe-only pass.',
          ),
        );
        expect(
          stdout,
          contains('Blocked review evidence: m25_next_cycle_seed_handoff'),
        );

        final handoff = File(
          '${root.path}/macos_computer_use_mvp_handoff.md',
        ).readAsStringSync();
        expect(handoff, contains('M25 Next-Cycle Seed Handoff Evidence'));
        expect(
          handoff,
          contains('M25 next-cycle seed handoff status: blocked'),
        );
        expect(
          handoff,
          contains('M25 next-cycle seed handoff blockers: seed_accepted'),
        );
        expect(handoff, contains('| seed_accepted | blocked |'));
        expect(
          handoff,
          contains('Blocked review evidence: m25_next_cycle_seed_handoff'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'MVP sign-off dry run surfaces blocked M26 observe restart packet',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_signoff_dry_run_m26_blocked_',
      );
      try {
        final m26Dir = Directory(
          '${root.path}/macos_computer_use_m26_observe_restart_packet_1',
        )..createSync();
        File('${m26Dir.path}/observe_restart_packet.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m26_observe_restart_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m26_observe_restart_packet",
  "milestone": "M26",
  "previousMilestone": "M25",
  "ready": false,
  "sourceM25NextCycleSeedHandoff": "/tmp/next_cycle_seed_handoff.json",
  "executionBoundary": "m14_observe_restart_packet_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "",
  "targetIntent": "Observe the next target.",
  "nextObservePreparation": {
    "required": true,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "screenshotRequired": true,
    "screenshotProvided": false
  },
  "commands": {
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot <user-provided-real-app-screenshot.png>"
  },
  "m26ObserveRestartPacketGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "target_app_present",
        "ok": false,
        "nextAction": "Provide the target app name for the next M14 observe pass."
      }
    ],
    "blockers": ["target_app_present"],
    "nextAction": "Resolve M26 observe restart packet blockers before asking for a new M14 screenshot."
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_signoff.sh',
          '--dry-run',
          '--root',
          root.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final stdout = '${result.stdout}';
        expect(stdout, contains('M26 observe restart packet status: blocked'));
        expect(
          stdout,
          contains(
            'M26 observe restart packet next action: Resolve M26 observe restart packet blockers before asking for a new M14 screenshot.',
          ),
        );
        expect(
          stdout,
          contains('Blocked review evidence: m26_observe_restart_packet'),
        );

        final handoff = File(
          '${root.path}/macos_computer_use_mvp_handoff.md',
        ).readAsStringSync();
        expect(handoff, contains('M26 Observe Restart Packet Evidence'));
        expect(handoff, contains('M26 observe restart packet status: blocked'));
        expect(
          handoff,
          contains('M26 observe restart packet blockers: target_app_present'),
        );
        expect(handoff, contains('| target_app_present | blocked |'));
        expect(
          handoff,
          contains('Blocked review evidence: m26_observe_restart_packet'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'MVP sign-off dry run surfaces blocked M27 screenshot request handoff',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_signoff_dry_run_m27_blocked_',
      );
      try {
        final m27Dir = Directory(
          '${root.path}/macos_computer_use_m27_screenshot_request_handoff_1',
        )..createSync();
        File(
          '${m27Dir.path}/screenshot_request_handoff.json',
        ).writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m27_screenshot_request_handoff",
  "schemaVersion": 1,
  "purpose": "computer_use_m27_screenshot_request_handoff",
  "milestone": "M27",
  "previousMilestone": "M26",
  "ready": false,
  "sourceM26ObserveRestartPacket": "/tmp/observe_restart_packet.json",
  "executionBoundary": "manual_screenshot_request_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "",
  "targetIntent": "Observe the next target.",
  "userScreenshotRequest": {
    "required": true,
    "provided": false,
    "targetApp": "",
    "targetIntent": "Observe the next target.",
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action"
  },
  "commands": {
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot <user-provided-real-app-screenshot.png>"
  },
  "m27ScreenshotRequestHandoffGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "target_app_present",
        "ok": false,
        "nextAction": "Provide the target app name before asking for a manual screenshot."
      }
    ],
    "blockers": ["target_app_present"],
    "nextAction": "Resolve M27 screenshot request handoff blockers before asking for the manual screenshot."
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_signoff.sh',
          '--dry-run',
          '--root',
          root.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final stdout = '${result.stdout}';
        expect(
          stdout,
          contains('M27 screenshot request handoff status: blocked'),
        );
        expect(
          stdout,
          contains(
            'M27 screenshot request handoff next action: Resolve M27 screenshot request handoff blockers before asking for the manual screenshot.',
          ),
        );
        expect(
          stdout,
          contains('Blocked review evidence: m27_screenshot_request_handoff'),
        );

        final handoff = File(
          '${root.path}/macos_computer_use_mvp_handoff.md',
        ).readAsStringSync();
        expect(handoff, contains('M27 Screenshot Request Handoff Evidence'));
        expect(
          handoff,
          contains('M27 screenshot request handoff status: blocked'),
        );
        expect(
          handoff,
          contains(
            'M27 screenshot request handoff blockers: target_app_present',
          ),
        );
        expect(handoff, contains('| target_app_present | blocked |'));
        expect(
          handoff,
          contains('Blocked review evidence: m27_screenshot_request_handoff'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'MVP sign-off dry run surfaces blocked M28 screenshot evidence intake',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_signoff_dry_run_m28_blocked_',
      );
      try {
        final m28Dir = Directory(
          '${root.path}/macos_computer_use_m28_screenshot_evidence_intake_1',
        )..createSync();
        File(
          '${m28Dir.path}/screenshot_evidence_intake.json',
        ).writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m28_screenshot_evidence_intake",
  "schemaVersion": 1,
  "purpose": "computer_use_m28_screenshot_evidence_intake",
  "milestone": "M28",
  "previousMilestone": "M27",
  "ready": false,
  "sourceM27ScreenshotRequestHandoff": "/tmp/screenshot_request_handoff.json",
  "executionBoundary": "manual_screenshot_evidence_intake_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "",
  "targetIntent": "Observe the next target.",
  "screenshotEvidence": {
    "path": "/tmp/user-provided-real-app-screenshot.png",
    "exists": true,
    "sizeBytes": 0,
    "extension": ".png",
    "source": "user_provided"
  },
  "nextObserveInput": {
    "required": true,
    "provided": false,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "",
    "targetIntent": "Observe the next target.",
    "screenshotPath": "/tmp/user-provided-real-app-screenshot.png"
  },
  "commands": {
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot /tmp/user-provided-real-app-screenshot.png"
  },
  "m28ScreenshotEvidenceIntakeGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "target_app_present",
        "ok": false,
        "nextAction": "Keep the target app from the M27 screenshot request."
      }
    ],
    "blockers": ["target_app_present"],
    "nextAction": "Resolve M28 screenshot evidence intake blockers before running the M14 observe-only canary."
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_signoff.sh',
          '--dry-run',
          '--root',
          root.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final stdout = '${result.stdout}';
        expect(
          stdout,
          contains('M28 screenshot evidence intake status: blocked'),
        );
        expect(
          stdout,
          contains(
            'M28 screenshot evidence intake next action: Resolve M28 screenshot evidence intake blockers before running the M14 observe-only canary.',
          ),
        );
        expect(
          stdout,
          contains('Blocked review evidence: m28_screenshot_evidence_intake'),
        );

        final handoff = File(
          '${root.path}/macos_computer_use_mvp_handoff.md',
        ).readAsStringSync();
        expect(handoff, contains('M28 Screenshot Evidence Intake'));
        expect(
          handoff,
          contains('M28 screenshot evidence intake status: blocked'),
        );
        expect(
          handoff,
          contains(
            'M28 screenshot evidence intake blockers: target_app_present',
          ),
        );
        expect(handoff, contains('| target_app_present | blocked |'));
        expect(
          handoff,
          contains('Blocked review evidence: m28_screenshot_evidence_intake'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'MVP sign-off dry run surfaces blocked M29 observe canary run packet',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_signoff_dry_run_m29_blocked_',
      );
      try {
        final m29Dir = Directory(
          '${root.path}/macos_computer_use_m29_observe_canary_run_packet_1',
        )..createSync();
        File('${m29Dir.path}/observe_canary_run_packet.json').writeAsStringSync(
          '''
{
  "schemaName": "macos_computer_use_m29_observe_canary_run_packet",
  "schemaVersion": 1,
  "purpose": "computer_use_m29_observe_canary_run_packet",
  "milestone": "M29",
  "previousMilestone": "M28",
  "ready": false,
  "sourceM28ScreenshotEvidenceIntake": "/tmp/screenshot_evidence_intake.json",
  "executionBoundary": "m14_observe_canary_run_packet_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "",
  "targetIntent": "Observe the next target.",
  "screenshotEvidence": {
    "path": "/tmp/user-provided-real-app-screenshot.png",
    "exists": true,
    "sizeBytes": 0,
    "extension": ".png",
    "source": "m28_screenshot_evidence_intake"
  },
  "m14ObserveRunPacket": {
    "required": true,
    "readyForUserOperation": false,
    "userOperated": true,
    "returnMilestone": "M14",
    "boundary": "observe_only_no_desktop_action",
    "targetApp": "",
    "targetIntent": "Observe the next target.",
    "screenshotPath": "/tmp/user-provided-real-app-screenshot.png",
    "command": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot /tmp/user-provided-real-app-screenshot.png"
  },
  "commands": {
    "m14ObserveCanary": "bash tool/run_macos_computer_use_real_app_observe_canary.sh --screenshot /tmp/user-provided-real-app-screenshot.png"
  },
  "m29ObserveCanaryRunPacketGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "target_app_present",
        "ok": false,
        "nextAction": "Keep the target app from the M28 screenshot intake."
      }
    ],
    "blockers": ["target_app_present"],
    "nextAction": "Resolve M29 observe canary run packet blockers before asking the user to run M14."
  }
}
''',
        );

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_signoff.sh',
          '--dry-run',
          '--root',
          root.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final stdout = '${result.stdout}';
        expect(
          stdout,
          contains('M29 observe canary run packet status: blocked'),
        );
        expect(
          stdout,
          contains(
            'M29 observe canary run packet next action: Resolve M29 observe canary run packet blockers before asking the user to run M14.',
          ),
        );
        expect(
          stdout,
          contains('Blocked review evidence: m29_observe_canary_run_packet'),
        );

        final handoff = File(
          '${root.path}/macos_computer_use_mvp_handoff.md',
        ).readAsStringSync();
        expect(handoff, contains('M29 Observe Canary Run Packet'));
        expect(
          handoff,
          contains('M29 observe canary run packet status: blocked'),
        );
        expect(
          handoff,
          contains(
            'M29 observe canary run packet blockers: target_app_present',
          ),
        );
        expect(handoff, contains('| target_app_present | blocked |'));
        expect(
          handoff,
          contains('Blocked review evidence: m29_observe_canary_run_packet'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'MVP sign-off dry run surfaces blocked M30 observe result intake',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'caverno_mvp_signoff_dry_run_m30_blocked_',
      );
      try {
        final m30Dir = Directory(
          '${root.path}/macos_computer_use_m30_observe_result_intake_1',
        )..createSync();
        File('${m30Dir.path}/observe_result_intake.json').writeAsStringSync('''
{
  "schemaName": "macos_computer_use_m30_observe_result_intake",
  "schemaVersion": 1,
  "purpose": "computer_use_m30_observe_result_intake",
  "milestone": "M30",
  "previousMilestone": "M29",
  "returnToMilestone": "M15",
  "ready": false,
  "sourceM29ObserveCanaryRunPacket": "/tmp/observe_canary_run_packet.json",
  "sourceM14ObserveCanarySummary": "/tmp/canary_summary.json",
  "executionBoundary": "m14_observe_result_intake_report_only",
  "desktopActionBoundary": "no_desktop_action",
  "tccBoundary": "no_tcc_operation",
  "llmBoundary": "no_llm_call",
  "targetApp": "Notes",
  "targetIntent": "Observe the next target.",
  "screenshotPath": "/tmp/user-provided-real-app-screenshot.png",
  "m14ObserveEvidence": {
    "ready": true,
    "gateStatus": "ready",
    "candidateTargetCount": 2
  },
  "commands": {
    "m15ActionProposalHandoff": "bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --m14-summary /tmp/canary_summary.json"
  },
  "m30ObserveResultIntakeGate": {
    "status": "blocked",
    "ready": false,
    "checks": [
      {
        "id": "target_app_matches",
        "ok": false,
        "nextAction": "Use an M14 summary generated for the same target app as the M29 packet."
      }
    ],
    "blockers": ["target_app_matches"],
    "nextAction": "Resolve M30 observe result intake blockers before returning to M15."
  }
}
''');

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_signoff.sh',
          '--dry-run',
          '--root',
          root.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        final stdout = '${result.stdout}';
        expect(stdout, contains('M30 observe result intake status: blocked'));
        expect(
          stdout,
          contains(
            'M30 observe result intake next action: Resolve M30 observe result intake blockers before returning to M15.',
          ),
        );
        expect(
          stdout,
          contains('Blocked review evidence: m30_observe_result_intake'),
        );

        final handoff = File(
          '${root.path}/macos_computer_use_mvp_handoff.md',
        ).readAsStringSync();
        expect(handoff, contains('M30 Observe Result Intake'));
        expect(handoff, contains('M30 observe result intake status: blocked'));
        expect(
          handoff,
          contains('M30 observe result intake blockers: target_app_matches'),
        );
        expect(handoff, contains('| target_app_matches | blocked |'));
        expect(
          handoff,
          contains('Blocked review evidence: m30_observe_result_intake'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('MVP sign-off appends blocked readiness next actions', () async {
    final root = Directory.systemTemp.createTempSync(
      'caverno_mvp_signoff_final_actions_',
    );
    try {
      final stub = File('${root.path}/release_readiness_stub.sh')
        ..writeAsStringSync(r'''
#!/usr/bin/env bash
set -euo pipefail
output_json=""
output_md=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-json)
      output_json="$2"
      shift 2
      ;;
    --output-md)
      output_md="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$(dirname "$output_json")"
cat > "$output_json" <<'JSON'
{
  "schemaName": "macos_computer_use_release_readiness",
  "status": "blocked",
  "ready": false,
  "gates": [
    {
      "id": "manual_tcc",
      "label": "Manual TCC sign-off",
      "status": "manual_required",
      "ready": false,
      "nextAction": "Ask the user to run manual TCC sign-off.",
      "artifactPath": null
    },
    {
      "id": "llm_canary",
      "label": "Computer Use LLM decision canary",
      "status": "passed",
      "ready": true,
      "nextAction": "LLM decision canary is passing.",
      "artifactPath": "/tmp/llm.json"
    }
  ]
}
JSON
if [[ -n "$output_md" ]]; then
  echo "# Stub readiness" > "$output_md"
fi
exit 1
''');

      final result = await Process.run(
        'bash',
        ['tool/run_macos_computer_use_mvp_signoff.sh', '--root', root.path],
        environment: {
          'CAVERNO_MACOS_COMPUTER_USE_READINESS_WRAPPER': stub.path,
        },
      );

      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      final stdout = '${result.stdout}';
      expect(stdout, contains('Final Readiness Next Actions'));
      expect(stdout, contains('manual_tcc'));
      expect(stdout, contains('Ask the user to run manual TCC sign-off.'));

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('Final Readiness Next Actions'));
      expect(handoff, contains('Readiness status: blocked'));
      expect(handoff, contains('Blocked gates: manual_tcc'));
      expect(handoff, contains('Ask the user to run manual TCC sign-off.'));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}

void _expectOperationBoundaryMarkdown(
  String markdown, {
  bool escapedBackticks = false,
}) {
  expect(markdown, contains('Operation Boundary'));
  final tick = escapedBackticks ? r'\`' : '`';
  for (final entry in MacosComputerUseOperationBoundary.values.entries) {
    expect(markdown, contains('- $tick${entry.key}$tick: ${entry.value}'));
  }
}
