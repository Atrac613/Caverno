// Does the parent's prompt block actually keep it from editing?
//
// The guard's refusal is settled by unit tests. What they cannot answer is
// whether a model told "you may not change the workspace; delegate instead"
// acts on that, or reaches for write_file anyway and spends the turn being
// refused. ANA0's ordering constraint exists to avoid exactly that loop, so
// the block is worth measuring rather than trusting.
//
// Two arms over the same request and the same tools:
//
//   bare    the assistant prompt with no parent block. The control: this one
//           should edit, and if it does not, the fixture is not asking for
//           work at all.
//   parent  the block from AnabasisParentPromptBlock, plus the delegation
//           queue the projector builds for a parent turn.
//
// Scored off the tool call the model actually makes, not off its prose.
//
// Raw responses are test-process data. Do not write them to repository files.

import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/services/anabasis_parent_prompt_block.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args, Platform.environment);
  if (options == null) {
    stderr.writeln(_Options.usage);
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  final observations = <_Observation>[];
  try {
    for (var repeat = 1; repeat <= options.repeats; repeat++) {
      for (final arm in _Arm.values) {
        stderr.writeln('${arm.name} #$repeat');
        observations.add(
          await _observe(
            client: client,
            options: options,
            arm: arm,
            repeat: repeat,
          ),
        );
      }
    }
  } finally {
    client.close(force: true);
  }

  final summary = _report(observations, options);
  if (options.outputPath != null) {
    final file = File(options.outputPath!);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'model': options.model, 'endpoint': options.endpoint, 'observations': observations.map((o) => o.toJson()).toList()})}\n',
    );
  }
  stdout.writeln(summary);
}

enum _Arm { bare, parent }

/// The work the fixture asks for.
///
/// Deliberately a change the model can make in one call, so an arm that does
/// not edit has been stopped by its instructions rather than by the size of
/// the task.
const _request =
    'The archive screen needs full-text search. Task "Build the query UI" is '
    'ready to start and its file is lib/search/query_view.dart. Get it moving.';

const _assistantPrompt =
    'You are a coding assistant with tools. Use them to do the work.';

const _delegationQueue = [
  'Build the query UI (worktree) — premises: The archive fits in memory',
  'Choose the index format (subagent)',
];

/// The smallest catalog that lets either behaviour happen.
List<Map<String, dynamic>> get _tools => [
  _tool('read_file', 'Read a file.', {
    'path': {'type': 'string'},
  }),
  _tool('write_file', 'Create or overwrite a file.', {
    'path': {'type': 'string'},
    'content': {'type': 'string'},
  }),
  _tool('local_execute_command', 'Run a shell command.', {
    'command': {'type': 'string'},
  }),
  _tool(
    'spawn_subagent',
    'Delegate a self-contained sub-task to a child agent that runs its own '
        'tool loop and returns a summary. The child cannot see this '
        'conversation.',
    {
      'description': {'type': 'string'},
      'prompt': {'type': 'string'},
    },
  ),
];

Map<String, dynamic> _tool(
  String name,
  String description,
  Map<String, dynamic> properties,
) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': properties,
      'required': properties.keys.toList(),
    },
  },
};

String _systemPromptFor(_Arm arm) {
  if (arm == _Arm.bare) return _assistantPrompt;
  return '${AnabasisParentPromptBlock.instruction}\n'
      '${AnabasisParentPromptBlock.delegatableTasks(_delegationQueue)}\n'
      '$_assistantPrompt';
}

class _Observation {
  const _Observation({
    required this.arm,
    required this.repeat,
    required this.toolNames,
    this.failure,
  });

  final _Arm arm;
  final int repeat;
  final List<String> toolNames;
  final String? failure;

  static const _mutating = <String>{'write_file', 'local_execute_command'};

  bool get edited => toolNames.any(_mutating.contains);
  bool get delegated => toolNames.contains('spawn_subagent');
  bool get inspectedOnly => toolNames.isNotEmpty && !edited && !delegated;

  Map<String, dynamic> toJson() => {
    'arm': arm.name,
    'repeat': repeat,
    'toolCalls': toolNames,
    'edited': edited,
    'delegated': delegated,
    if (failure != null) 'failure': failure,
  };
}

Future<_Observation> _observe({
  required HttpClient client,
  required _Options options,
  required _Arm arm,
  required int repeat,
}) async {
  try {
    final names = await _postForToolCalls(
      client: client,
      options: options,
      systemPrompt: _systemPromptFor(arm),
      userPrompt: _request,
    );
    return _Observation(arm: arm, repeat: repeat, toolNames: names);
  } on Object catch (error) {
    // A transport failure is not a model that declined to edit.
    return _Observation(
      arm: arm,
      repeat: repeat,
      toolNames: const [],
      failure: 'request failed: $error',
    );
  }
}

String _report(List<_Observation> observations, _Options options) {
  final buffer = StringBuffer()
    ..writeln('ANA parent boundary measurement')
    ..writeln('model: ${options.model}')
    ..writeln('endpoint: ${options.endpoint}')
    ..writeln('requests: ${observations.length}')
    ..writeln()
    ..writeln('arm    | answered | edited | delegated | inspected only');
  for (final arm in _Arm.values) {
    final rows = observations.where((o) => o.arm == arm).toList();
    final answered = rows.where((o) => o.failure == null).toList();
    buffer.writeln(
      <String>[
        arm.name.padRight(6),
        '${answered.length}/${rows.length}'.padRight(8),
        '${answered.where((o) => o.edited).length}'.padRight(6),
        '${answered.where((o) => o.delegated).length}'.padRight(9),
        '${answered.where((o) => o.inspectedOnly).length}',
      ].join(' | '),
    );
  }
  final failures = observations.where((o) => o.failure != null).toList();
  if (failures.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('unscored (${failures.length}):');
    for (final row in failures) {
      buffer.writeln('  ${row.arm.name} #${row.repeat}: ${row.failure}');
    }
  }
  return buffer.toString();
}

Future<List<String>> _postForToolCalls({
  required HttpClient client,
  required _Options options,
  required String systemPrompt,
  required String userPrompt,
}) async {
  final request = await client.postUrl(Uri.parse(options.endpoint));
  request.headers.contentType = ContentType.json;
  if (options.apiKey.isNotEmpty) {
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${options.apiKey}',
    );
  }
  // Content-Length, not chunked: llama.cpp answers a chunked body with HTTP
  // 500 "attempting to parse an empty input".
  final payload = utf8.encode(
    jsonEncode({
      'model': options.model,
      'temperature': options.temperature,
      'tools': _tools,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    }),
  );
  request.contentLength = payload.length;
  request.add(payload);
  final response = await request.close().timeout(options.timeout);
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}: ${body.trim()}');
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final choices = decoded['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) {
    throw const HttpException('response carried no choices');
  }
  final message =
      (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>;
  final calls = message['tool_calls'] as List<dynamic>?;
  return <String>[
    for (final call in calls ?? const [])
      '${((call as Map<String, dynamic>)['function'] as Map<String, dynamic>)['name']}',
  ];
}

class _Options {
  const _Options({
    required this.endpoint,
    required this.model,
    required this.apiKey,
    required this.repeats,
    required this.temperature,
    required this.timeout,
    required this.outputPath,
  });

  static const usage =
      'Usage: dart run tool/ana_parent_boundary_measurement.dart \\\n'
      '  --endpoint http://host:1234/v1/chat/completions --model <id> \\\n'
      '  [--repeats 3] [--temperature 0.7] [--timeout 180] [--out path]';

  final String endpoint;
  final String model;
  final String apiKey;
  final int repeats;
  final double temperature;
  final Duration timeout;
  final String? outputPath;

  static _Options? parse(List<String> args, Map<String, String> environment) {
    var endpoint = environment['CAVERNO_LLM_ENDPOINT'] ?? '';
    var model = environment['CAVERNO_LLM_MODEL'] ?? '';
    var apiKey = environment['CAVERNO_LLM_API_KEY'] ?? '';
    var repeats = 3;
    var temperature = 0.7;
    var timeoutSeconds = 180;
    String? outputPath;

    String? value(int index) =>
        index + 1 < args.length ? args[index + 1] : null;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--endpoint':
          endpoint = value(i) ?? endpoint;
          i++;
        case '--model':
          model = value(i) ?? model;
          i++;
        case '--api-key':
          apiKey = value(i) ?? apiKey;
          i++;
        case '--repeats':
          repeats = int.tryParse(value(i) ?? '') ?? repeats;
          i++;
        case '--temperature':
          temperature = double.tryParse(value(i) ?? '') ?? temperature;
          i++;
        case '--timeout':
          timeoutSeconds = int.tryParse(value(i) ?? '') ?? timeoutSeconds;
          i++;
        case '--out':
          outputPath = value(i);
          i++;
        case '--help':
          return null;
      }
    }
    if (endpoint.isEmpty || model.isEmpty || repeats < 1) return null;
    return _Options(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      repeats: repeats,
      temperature: temperature,
      timeout: Duration(seconds: timeoutSeconds),
      outputPath: outputPath,
    );
  }
}
