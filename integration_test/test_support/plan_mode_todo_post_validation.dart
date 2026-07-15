import 'dart:io';

import '../../tool/canaries/support/dart_cli_entrypoint_resolver.dart';
import '../../tool/canaries/support/todo_app_behavior_verifier.dart';

Future<Map<String, Object?>> validatePlanModeTodoScenario(
  Directory scenarioDir,
) async {
  final result = await TodoAppBehaviorVerifier(
    root: scenarioDir,
    entrypointPolicy: DartCliEntrypointPolicy.singleConventional,
  ).verify();
  return <String, Object?>{
    'validator': 'todo_app_behavior',
    'passed': result.passed,
    'diagnostics': result.diagnostics,
    'transcript': result.transcript,
  };
}
