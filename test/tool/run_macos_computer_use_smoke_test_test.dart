import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String script;

  setUpAll(() {
    script = File(
      'tool/run_macos_computer_use_smoke_test.sh',
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

  test('release diagnostics write a report before required sign-off failure', () {
    expect(script, isNot(contains('test -d "\${RELEASE_APP}"')));
    expect(script, isNot(contains('test -d "\${RELEASE_HELPER}"')));
    expect(script, isNot(contains('test -f "\${RELEASE_AGENT}"')));
    expect(
      script,
      contains(
        'if os.environ["REQUIRE_RELEASE_SIGNOFF_DART"] == "true" and blockers:',
      ),
    );
    expect(script, contains('raise SystemExit(1)'));
  });
}
