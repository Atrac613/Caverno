import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_scenario_seed_files.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

void main() {
  test('seeds and protects an immutable scenario input', () async {
    final sourceDir = Directory.systemTemp.createTempSync(
      'plan_mode_seed_source_',
    );
    final scenarioDir = Directory.systemTemp.createTempSync(
      'plan_mode_seed_scenario_',
    );
    addTearDown(() {
      sourceDir.deleteSync(recursive: true);
      scenarioDir.deleteSync(recursive: true);
    });
    final source = File('${sourceDir.path}/spec.md')
      ..writeAsStringSync('# Contract\n');
    final seeds = <PlanModeScenarioSeedFile>[
      PlanModeScenarioSeedFile(
        sourcePath: source.path,
        destinationPath: 'docs/spec.md',
      ),
    ];

    await seedPlanModeScenarioFiles(scenarioDir: scenarioDir, seedFiles: seeds);

    final destination = File('${scenarioDir.path}/docs/spec.md');
    expect(destination.readAsStringSync(), '# Contract\n');
    expect(
      () => assertPlanModeScenarioSeedFilesUnchanged(
        scenarioDir: scenarioDir,
        seedFiles: seeds,
      ),
      returnsNormally,
    );
    expect(planModeScenarioTaskDriftExcludedSeedPaths(seeds), <String>[
      'docs/spec.md',
    ]);

    destination.writeAsStringSync('# Modified\n');
    expect(
      () => assertPlanModeScenarioSeedFilesUnchanged(
        scenarioDir: scenarioDir,
        seedFiles: seeds,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a seed destination outside the scenario workspace', () async {
    final sourceDir = Directory.systemTemp.createTempSync(
      'plan_mode_seed_escape_source_',
    );
    final scenarioDir = Directory.systemTemp.createTempSync(
      'plan_mode_seed_escape_scenario_',
    );
    addTearDown(() {
      sourceDir.deleteSync(recursive: true);
      scenarioDir.deleteSync(recursive: true);
    });
    final source = File('${sourceDir.path}/spec.md')
      ..writeAsStringSync('# Contract\n');

    await expectLater(
      seedPlanModeScenarioFiles(
        scenarioDir: scenarioDir,
        seedFiles: <PlanModeScenarioSeedFile>[
          PlanModeScenarioSeedFile(
            sourcePath: source.path,
            destinationPath: '../spec.md',
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );
  });
}
