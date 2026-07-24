import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_temp_storage.dart';

void main() {
  test('uses the Caverno tmp directory by default', () {
    final root = resolvePlanModeTemporaryRoot(
      environment: const <String, String>{'HOME': '/Users/tester'},
    );

    expect(root.path, '/Users/tester/.caverno/tmp');
  });

  test('honors CAVERNO_HOME as the temporary root', () {
    final root = resolvePlanModeTemporaryRoot(
      environment: const <String, String>{
        'HOME': '/Users/tester',
        'CAVERNO_HOME': '/tmp/caverno-test',
      },
    );

    expect(root.path, '/tmp/caverno-test/tmp');
  });

  test('creates a unique directory below the resolved root', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'plan_mode_temp_storage_test_',
    );
    addTearDown(() async {
      if (sandbox.existsSync()) {
        await sandbox.delete(recursive: true);
      }
    });

    final directory = await createPlanModeTemporaryDirectory(
      'plan_mode_hive_',
      environment: <String, String>{'CAVERNO_HOME': sandbox.path},
    );

    expect(directory.parent.path, '${sandbox.path}/tmp');
    expect(directory.path, startsWith('${sandbox.path}/tmp/plan_mode_hive_'));
  });

  test('requires HOME without a CAVERNO_HOME override', () {
    expect(
      () => resolvePlanModeTemporaryRoot(environment: const <String, String>{}),
      throwsStateError,
    );
  });
}
