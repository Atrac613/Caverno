import 'dart:io';

import 'plan_mode_scenario_spec.dart';

Future<void> seedPlanModeScenarioFiles({
  required Directory scenarioDir,
  required List<PlanModeScenarioSeedFile> seedFiles,
}) async {
  for (final seed in seedFiles) {
    final destination = _resolveSeedDestination(scenarioDir, seed);
    final source = File(seed.sourcePath).absolute;
    if (!source.existsSync()) {
      throw StateError('Scenario seed source does not exist: ${source.path}');
    }
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
  }
}

void assertPlanModeScenarioSeedFilesUnchanged({
  required Directory scenarioDir,
  required List<PlanModeScenarioSeedFile> seedFiles,
}) {
  for (final seed in seedFiles.where((item) => item.immutable)) {
    final source = File(seed.sourcePath).absolute;
    final destination = _resolveSeedDestination(scenarioDir, seed);
    if (!destination.existsSync()) {
      throw StateError(
        'Immutable scenario seed was deleted: ${seed.destinationPath}',
      );
    }
    final sourceBytes = source.readAsBytesSync();
    final destinationBytes = destination.readAsBytesSync();
    if (!_bytesEqual(sourceBytes, destinationBytes)) {
      throw StateError(
        'Immutable scenario seed was modified: ${seed.destinationPath}',
      );
    }
  }
}

List<String> planModeScenarioTaskDriftExcludedSeedPaths(
  List<PlanModeScenarioSeedFile> seedFiles,
) {
  return seedFiles
      .where((item) => item.immutable)
      .map((item) => item.destinationPath)
      .toList(growable: false);
}

File _resolveSeedDestination(
  Directory scenarioDir,
  PlanModeScenarioSeedFile seed,
) {
  final normalized = seed.destinationPath.trim().replaceAll('\\', '/');
  final segments = normalized
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (normalized.startsWith('/') ||
      segments.isEmpty ||
      segments.contains('..')) {
    throw StateError(
      'Scenario seed destination must stay inside the workspace: '
      '${seed.destinationPath}',
    );
  }
  final destination = File('${scenarioDir.path}/${segments.join('/')}');
  final rootPath = scenarioDir.absolute.path;
  final destinationPath = destination.absolute.path;
  if (!destinationPath.startsWith('$rootPath${Platform.pathSeparator}')) {
    throw StateError(
      'Scenario seed destination escaped the workspace: '
      '${seed.destinationPath}',
    );
  }
  return destination;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
