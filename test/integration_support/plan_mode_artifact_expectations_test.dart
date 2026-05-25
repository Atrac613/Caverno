import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_artifact_expectations.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_artifact_expectations_test_',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('asserts exact content and snippet constraints', () {
    File('${tempDir.path}/README.md').writeAsStringSync(
      '# Host Health Check\n\nUses standard library ping checks.\n',
    );

    assertPlanModeArtifactExpectations(
      tempDir,
      const <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'README.md',
          exactContent:
              '# Host Health Check\n\nUses standard library ping checks.\n',
          contains: <String>['Host Health Check', 'standard library'],
          absentSnippets: <String>['ping3'],
        ),
      ],
    );
  });

  test('asserts absent artifacts', () {
    assertPlanModeArtifactExpectations(
      tempDir,
      const <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(path: 'main.py', shouldExist: false),
      ],
    );
  });

  test('fails when an expected artifact is missing', () {
    expect(
      () => assertPlanModeArtifactExpectations(
        tempDir,
        const <PlanModeArtifactExpectation>[
          PlanModeArtifactExpectation(path: 'README.md'),
        ],
      ),
      throwsA(anything),
    );
  });

  test('allows any required artifact mode', () {
    File(
      '${tempDir.path}/requirements.txt',
    ).writeAsStringSync('# No external dependencies required.\n');

    assertPlanModeArtifactExpectations(
      tempDir,
      const <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'requirements.txt',
          contains: <String>['No external dependencies'],
        ),
        PlanModeArtifactExpectation(path: 'README.md'),
      ],
      mode: PlanModeArtifactExpectationMode.anyRequired,
    );
  });

  test('fails any required artifact mode when no candidate exists', () {
    expect(
      () => assertPlanModeArtifactExpectations(
        tempDir,
        const <PlanModeArtifactExpectation>[
          PlanModeArtifactExpectation(path: 'requirements.txt'),
          PlanModeArtifactExpectation(path: 'README.md'),
        ],
        mode: PlanModeArtifactExpectationMode.anyRequired,
      ),
      throwsA(anything),
    );
  });

  test('waits until required artifacts appear without frame pumping', () async {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 20), () {
        File('${tempDir.path}/README.md').writeAsStringSync('# Project\n');
      }),
    );

    await waitForPlanModeArtifactExpectations(
      tempDir,
      const <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(path: 'README.md'),
      ],
      timeout: const Duration(seconds: 1),
      pollInterval: const Duration(milliseconds: 10),
      useFramePump: false,
    );

    expect(File('${tempDir.path}/README.md').existsSync(), isTrue);
  });

  test(
    'waits until any required artifact appears without frame pumping',
    () async {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 20), () {
          File(
            '${tempDir.path}/requirements.txt',
          ).writeAsStringSync('# Deps\n');
        }),
      );

      await waitForPlanModeArtifactExpectations(
        tempDir,
        const <PlanModeArtifactExpectation>[
          PlanModeArtifactExpectation(path: 'requirements.txt'),
          PlanModeArtifactExpectation(path: 'README.md'),
        ],
        mode: PlanModeArtifactExpectationMode.anyRequired,
        timeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 10),
        useFramePump: false,
      );

      expect(File('${tempDir.path}/requirements.txt').existsSync(), isTrue);
    },
  );

  test('does not wait for artifacts expected to be absent', () async {
    final startedAt = DateTime.now();

    await waitForPlanModeArtifactExpectations(
      tempDir,
      const <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(path: 'main.py', shouldExist: false),
      ],
      timeout: const Duration(seconds: 1),
      pollInterval: const Duration(milliseconds: 10),
      useFramePump: false,
    );

    expect(DateTime.now().difference(startedAt).inMilliseconds, lessThan(200));
  });

  test('requires a tester when frame pumping is enabled', () {
    expect(
      () => waitForPlanModeArtifactExpectations(
        tempDir,
        const <PlanModeArtifactExpectation>[
          PlanModeArtifactExpectation(path: 'README.md'),
        ],
      ),
      throwsA(isA<StateError>()),
    );
  });
}
