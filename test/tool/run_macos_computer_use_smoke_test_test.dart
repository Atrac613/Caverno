import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String script;
  late String liveCanaryScript;
  late String existingHelperProbe;
  late String architectureDoc;

  setUpAll(() {
    script = File(
      'tool/run_macos_computer_use_smoke_test.sh',
    ).readAsStringSync();
    liveCanaryScript = File(
      'tool/run_macos_computer_use_live_canary.sh',
    ).readAsStringSync();
    existingHelperProbe = File(
      'tool/macos_computer_use_existing_helper_probe.swift',
    ).readAsStringSync();
    architectureDoc = File(
      'docs/macos_computer_use_helper_architecture.md',
    ).readAsStringSync();
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
    expect(liveCanaryScript, isNot(contains('--m8-runtime-signoff')));
    expect(liveCanaryScript, isNot(contains('--require-capture')));
    expect(liveCanaryScript, isNot(contains('--require-vision-observe')));
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
    expect(liveCanaryScript, contains('--manual|--local'));
    expect(liveCanaryScript, contains('--repeat'));
    expect(liveCanaryScript, contains('Manual TCC follow-up'));
    expect(liveCanaryScript, contains('classify_failure'));
    expect(liveCanaryScript, contains('helper_status_failed'));
    expect(liveCanaryScript, contains('ipc_not_ready'));
    expect(liveCanaryScript, contains('helper_ping_failed'));
    expect(liveCanaryScript, contains('permission_status_failed'));
    expect(liveCanaryScript, contains('cleanup_failed'));
    expect(liveCanaryScript, contains('"failureClasses": failure_classes'));
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
      contains('Passing either canary does not replace the other.'),
    );
  });
}
