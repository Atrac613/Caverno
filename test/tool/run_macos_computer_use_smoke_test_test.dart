import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  late String desktopActionCanaryScript;
  late String llmDecisionCanaryScript;
  late String mvpFixtureLlmCanaryScript;
  late String mvpFixtureVisionLlmCanaryScript;
  late String mvpLlmReadinessScript;
  late String mvpDemoReadinessScript;
  late String releaseReadinessWrapper;
  late String mvpFixtureScript;
  late String mvpFixtureSource;
  late String mvpFixtureRunbook;
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
      contains('macos_computer_use_readiness_artifact_index.json'),
    );
    expect(architectureDoc, contains('--refresh-llm-canary'));
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
    expect(
      mvpFixtureVisionLlmCanaryScript,
      contains('macos_computer_use_mvp_fixture_vision_llm_canary_summary'),
    );
    expect(mvpFixtureVisionLlmCanaryScript, contains('--screenshot PATH'));
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
        expect(summary, contains('"manual_tcc"'));
        expect(summary, contains('"desktop_action_canary"'));

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

  test(
    'Computer Use MVP demo readiness wrapper guides the full handoff',
    () async {
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

        final result = await Process.run('bash', [
          'tool/run_macos_computer_use_mvp_demo_readiness.sh',
          '--root',
          root.path,
          '--skip-fixture-build',
          '--vision-fixture-response',
          fixture.path,
        ]);

        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
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

        final handoffFiles = Directory(root.path)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('mvp_demo_handoff.md'))
            .toList(growable: false);
        expect(handoffFiles, hasLength(1));
        final handoff = handoffFiles.single.readAsStringSync();
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
    },
  );

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
        expect(summary, contains('"failureGuidance"'));
        expect(summary, contains('"Safe Click Target"'));
        expect(summary, contains('"MVP Fixture Text Field"'));
        expect(summary, contains('"Danger Zone"'));
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
        'bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target',
      ),
    );
    expect(
      mvpFixtureRunbook,
      contains('does not auto-launch Caverno.app by default'),
    );
    expect(mvpFixtureRunbook, contains('--launch-caverno'));
    expect(mvpFixtureRunbook, contains('user-operated'));
    expect(mvpFixtureRunbook, contains('does not grant TCC'));
  });

  test('MVP sign-off wrapper keeps user-operated boundaries explicit', () {
    final mvpChecklist = File(
      'docs/macos_computer_use_mvp_checklist.md',
    ).readAsStringSync();

    expect(mvpChecklist, contains('macOS Computer Use MVP Checklist'));
    expect(
      mvpChecklist,
      contains('bash tool/run_macos_computer_use_manual_tcc_signoff.sh'),
    );
    expect(
      mvpChecklist,
      contains('bash tool/run_macos_computer_use_desktop_action_canary.sh'),
    );
    expect(
      mvpChecklist,
      contains('bash tool/run_macos_computer_use_mvp_signoff.sh'),
    );
    expect(mvpChecklist, contains('--dry-run'));
    expect(mvpSignoffScript, contains('macos_computer_use_mvp_handoff.md'));
    expect(mvpSignoffScript, contains('macos_computer_use_mvp_readiness.json'));
    expect(mvpSignoffScript, contains('Current Manual Input Status'));
    expect(mvpSignoffScript, contains('Missing Input Next Actions'));
    expect(mvpSignoffScript, contains('Final Readiness Next Actions'));
    expect(mvpSignoffScript, contains('--final-signoff'));
    expect(mvpSignoffScript, contains('readiness_exit'));
    expect(
      mvpSignoffScript,
      contains('CAVERNO_MACOS_COMPUTER_USE_READINESS_WRAPPER'),
    );
    expect(mvpSignoffScript, contains('provided path not found'));
    expect(mvpSignoffScript, contains('Dry run: would execute'));
    expect(
      mvpSignoffScript,
      contains('user-operated manual verification only'),
    );
    expect(mvpSignoffScript, contains('user-operated safe click target only'));
    expect(
      mvpSignoffScript,
      contains('manual_tcc: ask the user for manual_tcc_report_summary.json'),
    );
    expect(
      mvpSignoffScript,
      contains('desktop_action_canary: ask the user for canary_summary.json'),
    );
    expect(mvpSignoffScript, contains('--manual-tcc-report'));
    expect(mvpSignoffScript, contains('--desktop-action-canary-summary'));
    expect(mvpSignoffScript, contains('--llm-canary-summary'));
    expect(mvpSignoffScript, contains('LLM canary status'));
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
      expect(
        stdout,
        contains('manual_tcc: ask the user for manual_tcc_report_summary.json'),
      );
      expect(
        stdout,
        contains('desktop_action_canary: ask the user for canary_summary.json'),
      );
      expect(stdout, contains('Dry run: would execute'));

      final handoff = File(
        '${root.path}/macos_computer_use_mvp_handoff.md',
      ).readAsStringSync();
      expect(handoff, contains('Manual TCC status: not provided'));
      expect(handoff, contains('Desktop action canary status: not provided'));
      expect(handoff, contains('Missing Input Next Actions'));
      expect(
        handoff,
        contains('bash tool/run_macos_computer_use_manual_tcc_signoff.sh'),
      );
      expect(
        handoff,
        contains('bash tool/run_macos_computer_use_desktop_action_canary.sh'),
      );
      expect(
        File('${root.path}/macos_computer_use_mvp_readiness.json').existsSync(),
        isFalse,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
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
        expect(handoff, contains(missingManualReport));
        expect(handoff, contains(desktopSummary.path));
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
