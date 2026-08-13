import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/routines/data/routine_execution_service.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

const _verificationCommand = 'dart tool/verify.dart';
const _scenarios = <String, _RoutineScenario>{
  'state_ready': _RoutineScenario(
    id: 'state_ready',
    fileName: 'state.json',
    fieldName: 'status',
    fieldType: 'String',
    initialContent: '{"status":"pending"}\n',
    targetContent: '{"status":"ready"}',
  ),
  'feature_flag': _RoutineScenario(
    id: 'feature_flag',
    fileName: 'settings.json',
    fieldName: 'featureEnabled',
    fieldType: 'bool',
    initialContent: '{"featureEnabled":false}\n',
    targetContent: '{"featureEnabled":true}',
  ),
  'retry_limit': _RoutineScenario(
    id: 'retry_limit',
    fileName: 'policy.json',
    fieldName: 'retryLimit',
    fieldType: 'int',
    initialContent: '{"retryLimit":1}\n',
    targetContent: '{"retryLimit":3}',
  ),
  'display_format': _RoutineScenario(
    id: 'display_format',
    fileName: 'display.json',
    fieldName: 'format',
    fieldType: 'String',
    initialContent: '{"format":"verbose"}\n',
    targetContent: '{"format":"compact"}',
  ),
};

void main() {
  final enabled =
      Platform.environment['CAVERNO_LL37_ROUTINE_LIVE_CANARY'] == '1';

  test('uses the Dart CLI when the test runner is flutter_tester', () {
    expect(_dartExecutableFor('/opt/flutter/bin/cache/flutter_tester'), 'dart');
    expect(
      _dartExecutableFor('/opt/flutter/bin/cache/dart-sdk/bin/dart'),
      '/opt/flutter/bin/cache/dart-sdk/bin/dart',
    );
  });

  test('normalizes nested JSON-serializable values before capture', () {
    expect(
      _encodeJsonMap({
        'runs': [_JsonFixture()],
      }),
      {
        'runs': [
          {'id': 'run-1'},
        ],
      },
    );
  });

  test('defines four objective-distinct mechanically-green scenarios', () {
    expect(_scenarios, hasLength(4));
    expect(
      _scenarios.values.map((scenario) => scenario.objective).toSet(),
      hasLength(4),
    );
    for (final scenario in _scenarios.values) {
      expect(scenario.initialContent, isNot(scenario.targetContent));
      expect(jsonDecode(scenario.initialContent), isA<Map<String, dynamic>>());
      expect(jsonDecode(scenario.targetContent), isA<Map<String, dynamic>>());
    }
  });

  test('broken control hides every available built-in tool', () {
    expect(
      _toolServiceForArm(disableTools: true).getOpenAiToolDefinitions(),
      isEmpty,
    );
  });

  test(
    'weak verification reports the observed content without gating on it',
    () {
      final script = _verificationScript(_scenarios['display_format']!);
      expect(script, contains("decoded['format'] is String"));
      expect(
        script,
        contains("'Observed file content: ' + jsonEncode(decoded)"),
      );
      expect(script, isNot(contains("decoded['format'] == 'compact'")));
    },
  );

  test(
    'records a controlled Routine correct and known-broken pair',
    () async {
      final env = _LiveCanaryEnvironment.fromEnvironment();
      final scenario = _scenarioById(env.scenarioId);
      final outputDirectory = Directory(env.outputDirectoryPath);
      if (outputDirectory.existsSync()) {
        throw StateError('LL37 Routine capture directory already exists.');
      }
      await outputDirectory.create(recursive: true);
      final workspace = Directory(
        '${outputDirectory.path}/private_scratch/routine_workspace',
      );
      await _prepareFixture(workspace, scenario);

      final now = DateTime.now().toUtc();
      final routine = Routine(
        id: 'll37-routine-controlled-${scenario.id}',
        name: 'Complete the controlled ${scenario.id} objective',
        prompt: scenario.prompt,
        createdAt: now,
        updatedAt: now,
        enabled: true,
        toolsEnabled: true,
        workspaceDirectory: workspace.path,
        allowWorkspaceWrites: true,
      );

      final correct = await _runArm(
        env: env,
        routine: routine,
        disableWriteTools: false,
      );
      final correctVerification = await _verifyWorkspace(workspace);
      final correctState = await File(
        '${workspace.path}/${scenario.fileName}',
      ).readAsString();

      await File(
        '${workspace.path}/${scenario.fileName}',
      ).writeAsString(scenario.initialContent);
      final broken = await _runArm(
        env: env,
        routine: routine,
        disableWriteTools: true,
      );
      final brokenVerification = await _verifyWorkspace(workspace);
      final brokenState = await File(
        '${workspace.path}/${scenario.fileName}',
      ).readAsString();

      expect(correct.status, RoutineRunStatus.completed);
      expect(correct.toolNames, contains('write_file'));
      expect(correctState.trim(), scenario.targetContent);
      expect(correctVerification.exitCode, 0);
      expect(broken.status, RoutineRunStatus.completed);
      expect(broken.toolNames, isNot(contains('write_file')));
      expect(brokenState, scenario.initialContent);
      expect(brokenVerification.exitCode, 0);

      final routineJson = _encodeJsonMap(
        routine.copyWith(runs: [correct, broken]).toJson(),
      );
      final runs = (routineJson['runs'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      runs[0]['mechanicalVerification'] = correctVerification.toJson();
      runs[1]['mechanicalVerification'] = brokenVerification.toJson();
      await _writeJson(File('${outputDirectory.path}/routines.json'), [
        routineJson,
      ]);
      await _writeJson(File('${outputDirectory.path}/selection.json'), {
        'schemaName': 'caverno_ll37_routine_history_selection',
        'schemaVersion': 1,
        'routineId': routine.id,
        'pairId':
            'll37-routine-${scenario.id}-${DateTime.now().toUtc().millisecondsSinceEpoch}',
        'correctRunId': correct.id,
        'brokenRunId': broken.id,
        'acceptanceCriteria': [
          scenario.acceptanceCriterion,
          'The shared verification command exits successfully for both implementations.',
        ],
        'requiredTools': const ['write_file'],
        'consent': const {
          'explicitUserConsent': true,
          'scope': 'personal_eval_case_recording',
        },
      });
      await _writeJson(
        File('${outputDirectory.path}/canary_capture_summary.json'),
        {
          'schemaName': 'caverno_ll37_routine_live_canary_capture',
          'schemaVersion': 1,
          'model': env.model,
          'scenarioId': scenario.id,
          'correct': {
            'status': correct.status.name,
            'mechanicalExitCode': correctVerification.exitCode,
            'changedFileToolRecorded': correct.toolNames.contains('write_file'),
          },
          'broken': {
            'status': broken.status.name,
            'mechanicalExitCode': brokenVerification.exitCode,
            'changedFileToolRecorded': broken.toolNames.contains('write_file'),
            'control': 'write_tools_disabled_mechanically_green',
          },
        },
      );
    },
    skip: enabled
        ? false
        : 'Set CAVERNO_LL37_ROUTINE_LIVE_CANARY=1 and the required '
              'LLM/evidence environment variables to run.',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<RoutineRunRecord> _runArm({
  required _LiveCanaryEnvironment env,
  required Routine routine,
  required bool disableWriteTools,
}) {
  final settings = AppSettings.defaults().copyWith(
    baseUrl: env.baseUrl,
    apiKey: env.apiKey,
    model: env.model,
    temperature: 0,
    maxTokens: 2048,
    mcpEnabled: false,
  );
  final service = RoutineExecutionService(
    dataSource: ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
    mcpToolService: _toolServiceForArm(disableTools: disableWriteTools),
    settings: settings,
  );
  return service.execute(routine, trigger: RoutineRunTrigger.scheduled);
}

McpToolService _toolServiceForArm({required bool disableTools}) {
  if (!disableTools) return McpToolService();
  final available = McpToolService().getOpenAiToolDefinitions();
  final disabledNames = available.map((definition) {
    final function = definition['function'] as Map<String, dynamic>;
    return function['name'] as String;
  }).toSet();
  return McpToolService(disabledBuiltInTools: disabledNames);
}

Future<void> _prepareFixture(
  Directory workspace,
  _RoutineScenario scenario,
) async {
  if (workspace.existsSync()) {
    throw StateError('LL37 Routine canary workspace already exists.');
  }
  await Directory('${workspace.path}/tool').create(recursive: true);
  await File(
    '${workspace.path}/${scenario.fileName}',
  ).writeAsString(scenario.initialContent);
  await File(
    '${workspace.path}/tool/verify.dart',
  ).writeAsString(_verificationScript(scenario));
}

String _verificationScript(_RoutineScenario scenario) =>
    '''
import 'dart:convert';
import 'dart:io';

void main() {
  final decoded = jsonDecode(File('${scenario.fileName}').readAsStringSync());
  if (decoded is Map<String, dynamic> && decoded['${scenario.fieldName}'] is ${scenario.fieldType}) {
    stdout.writeln('Scenario file syntax verification passed.');
    stdout.writeln('Observed file content: ' + jsonEncode(decoded));
    return;
  }
  stderr.writeln('Expected the scenario JSON field to have its declared type.');
  exitCode = 1;
}
''';

Future<_MechanicalVerificationCapture> _verifyWorkspace(
  Directory workspace,
) async {
  final result = await Process.run(
    _dartExecutableFor(Platform.resolvedExecutable),
    const ['tool/verify.dart'],
    workingDirectory: workspace.path,
  );
  return _MechanicalVerificationCapture(
    command: _verificationCommand,
    exitCode: result.exitCode,
    output: '${result.stdout}${result.stderr}'.trim(),
  );
}

String _dartExecutableFor(String resolvedExecutable) {
  final executableName = resolvedExecutable
      .replaceAll('\\', '/')
      .split('/')
      .last;
  return executableName == 'dart' ? resolvedExecutable : 'dart';
}

Map<String, dynamic> _encodeJsonMap(Map<String, dynamic> value) {
  return (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
}

Future<void> _writeJson(File file, Object value) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

final class _MechanicalVerificationCapture {
  const _MechanicalVerificationCapture({
    required this.command,
    required this.exitCode,
    required this.output,
  });

  final String command;
  final int exitCode;
  final String output;

  Map<String, dynamic> toJson() => {
    'command': command,
    'exitCode': exitCode,
    'output': output,
  };
}

final class _JsonFixture {
  Map<String, dynamic> toJson() => const {'id': 'run-1'};
}

final class _RoutineScenario {
  const _RoutineScenario({
    required this.id,
    required this.fileName,
    required this.fieldName,
    required this.fieldType,
    required this.initialContent,
    required this.targetContent,
  });

  final String id;
  final String fileName;
  final String fieldName;
  final String fieldType;
  final String initialContent;
  final String targetContent;

  String get objective =>
      'Write $targetContent exactly to $fileName in the Routine workspace.';

  String get prompt =>
      '$objective Use write_file, make no unrelated changes, and finish with '
      'a concise summary.';

  String get acceptanceCriterion =>
      'Changed-file evidence for $fileName contains exactly: $targetContent.';
}

_RoutineScenario _scenarioById(String id) {
  final scenario = _scenarios[id];
  if (scenario == null) {
    throw StateError(
      'Unknown LL37 Routine scenario "$id". Expected one of: '
      '${_scenarios.keys.join(', ')}.',
    );
  }
  return scenario;
}

final class _LiveCanaryEnvironment {
  const _LiveCanaryEnvironment({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.outputDirectoryPath,
    required this.scenarioId,
  });

  factory _LiveCanaryEnvironment.fromEnvironment() {
    if (_requiredEnv('CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT') != '1') {
      throw StateError(
        'CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1 is required.',
      );
    }
    return _LiveCanaryEnvironment(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      outputDirectoryPath: _requiredEnv('CAVERNO_LL37_ROUTINE_CAPTURE_DIR'),
      scenarioId:
          Platform.environment['CAVERNO_LL37_ROUTINE_SCENARIO']
                  ?.trim()
                  .isNotEmpty ==
              true
          ? Platform.environment['CAVERNO_LL37_ROUTINE_SCENARIO']!.trim()
          : 'state_ready',
    );
  }

  final String baseUrl;
  final String apiKey;
  final String model;
  final String outputDirectoryPath;
  final String scenarioId;
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    throw StateError('$name is required for the LL37 Routine canary.');
  }
  return value;
}
