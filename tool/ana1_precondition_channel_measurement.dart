// ANA1 PR 2b: which channel does the model actually write a precondition edge
// through?
//
// ANA0 answered the same question for its epistemic marker by measuring rather
// than by choosing: PR 3b kept the marker inside the item string because a
// growing JSON schema costs weak local models their structured-output
// fidelity, and PRs 3c-3e then moved the model twice by rewording. This is
// that question one level up, for task preconditions.
//
// Three arms, identical but for the instruction appended to the production
// proposal prompt:
//
//   none    the production prompt, unchanged. The control: an edge here would
//           mean something other than the instruction produced it.
//   title   the edge rides in the task title, `[requires: <kind>: <ref>]`,
//           which is ANA0 PR 3b's shape and leaves the JSON schema alone.
//   schema  each task carries a `preconditions` array. What this costs in
//           parse rate is the direct test of PR 3b's stated reason.
//
// Scope, stated rather than implied: this measures whether a channel *works*
// -- edges written, references that resolve, proposals still parseable. It
// does not score over- or under-generation against a ground-truth graph,
// because how the model splits work into tasks is not controlled here. The
// production proposal parser is unchanged; each arm's extractor is what a
// producer would have to add, which is why they live beside the scoring rather
// than in lib/.
//
// Raw responses are test-process data. Do not write them to repository files.

import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_planning_prompt_service.dart';
import 'package:caverno/features/chat/domain/services/task_precondition_parsing.dart';

Future<void> main(List<String> args) async {
  final options = ChannelMeasurementOptions.parse(args, Platform.environment);
  if (options == null) {
    stderr.writeln(ChannelMeasurementOptions.usage);
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  try {
    final summary = await runPreconditionChannelMeasurement(
      options: options,
      send: (system, user) => _postChatCompletion(
        client: client,
        options: options,
        systemPrompt: system,
        userPrompt: user,
      ),
      onProgress: (line) => stderr.writeln(line),
    );
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(summary.toJson());
    if (options.outputPath != null) {
      final file = File(options.outputPath!);
      await file.parent.create(recursive: true);
      await file.writeAsString('$encoded\n');
    }
    stdout.writeln(options.json ? encoded : summary.report());
  } finally {
    client.close(force: true);
  }
}

typedef ChatCompletionSender =
    Future<String> Function(String systemPrompt, String userPrompt);

const _systemPrompt =
    'You are a planning assistant inside a coding agent. Follow the '
    'instructions in the user message exactly and return only JSON.';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A request whose work has an ordering the request itself states.
///
/// The dependency is in the prose, not in the instructions: a plan for this
/// request has somewhere obvious to put an edge, so an arm that produces none
/// has failed to reach a signal that was there rather than been denied one.
class ChannelScenario {
  const ChannelScenario({
    required this.id,
    required this.request,
    this.goal = '',
    this.constraints = const <String>[],
    this.openQuestions = const <String>[],
  });

  final String id;
  final String request;

  /// The approved contract the task phase runs against.
  ///
  /// Found by reading the first run's raw responses: the *proposal* prompt
  /// returns `kind: decision` and no tasks at all — tasks are drafted in a
  /// second phase, against an approved contract. Measuring the proposal prompt
  /// scored 12 of 12 unparseable and would have read as a model that refuses
  /// to write edges.
  final String goal;
  final List<String> constraints;
  final List<String> openQuestions;

  /// What an edge may point at besides another task.
  Set<String> get contractReferences => {...constraints, ...openQuestions};
}

const channelScenarios = <ChannelScenario>[
  ChannelScenario(
    id: 'sync-after-audit',
    request: 'Add iCloud sync to the notes app. Plan the work.',
    goal: 'Add iCloud sync to the notes app',
    constraints: [
      'The sync engine cannot be written until the local data model audit is done',
      'Record ids are stable across devices',
    ],
    openQuestions: ['Should conflicts use last-write-wins or a merge policy?'],
  ),
  ChannelScenario(
    id: 'migrate-after-backup',
    request: 'Move the local store from SharedPreferences to a database.',
    goal: 'Move the local store to a database',
    constraints: [
      'Nothing may be migrated before a verified backup path exists',
      'Every install is on a single legacy on-disk layout',
    ],
    openQuestions: ['Which database engine should the store use?'],
  ),
  ChannelScenario(
    id: 'push-after-entitlement',
    request: 'Add push notifications for shared-document comments.',
    goal: 'Add push notifications for document comments',
    constraints: [
      'Client work depends on the APNs entitlement being provisioned first',
      'The device token registration path already works',
    ],
    openQuestions: ['Do comments notify the whole document or only mentions?'],
  ),
  ChannelScenario(
    id: 'search-after-index',
    request: 'Add full-text search to the archive screen.',
    goal: 'Add full-text search to the archive',
    constraints: [
      'The query UI cannot be built before the index format is chosen',
      'The archive fits in memory',
    ],
    openQuestions: ['Should search cover attachments as well as note bodies?'],
  ),
];

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

enum ChannelArm { none, title, schema }

/// The instruction each arm appends to the production proposal prompt.
///
/// The prompt itself is unchanged production code: this is a measurement of
/// what to *put* there, so putting it there first would settle the question by
/// assumption.
String armInstruction(ChannelArm arm) {
  return switch (arm) {
    ChannelArm.none => '',
    ChannelArm.title =>
      '- When a task cannot start until something else holds, end its title '
          'with an edge in square brackets, in English, exactly like '
          '"[requires: task: <the other task\'s title>]", '
          '"[requires: assumption: <the constraint text>]", or '
          '"[requires: question: <the open question text>]". Write one bracket '
          'group per edge and leave tasks that can start immediately unmarked.',
    ChannelArm.schema =>
      '- Give each task an additional "preconditions" field: an array of '
          'objects with "kind" (one of "task", "assumption", "question") and '
          '"ref" (the other task\'s title, the constraint text, or the open '
          'question text). Use an empty array for a task that can start '
          'immediately.',
  };
}

/// One request's outcome.
class ChannelObservation {
  const ChannelObservation({
    required this.scenarioId,
    required this.arm,
    required this.repeat,
    required this.parsed,
    required this.taskCount,
    required this.edgeCount,
    required this.resolvedEdgeCount,
    required this.mentionsWithoutEdge,
    this.failure,
  });

  final String scenarioId;
  final ChannelArm arm;
  final int repeat;

  /// Whether a proposal object could be read out of the response at all.
  final bool parsed;
  final int taskCount;

  /// Edges the arm's own extractor could read.
  final int edgeCount;

  /// Of those, how many name something in the same plan.
  final int resolvedEdgeCount;

  /// Whether the response talks about ordering without producing an edge the
  /// extractor reads. A high number here means the channel is the problem, not
  /// the model's willingness.
  final bool mentionsWithoutEdge;
  final String? failure;

  Map<String, dynamic> toJson() => {
    'scenario': scenarioId,
    'arm': arm.name,
    'repeat': repeat,
    'parsed': parsed,
    'taskCount': taskCount,
    'edgeCount': edgeCount,
    'resolvedEdgeCount': resolvedEdgeCount,
    'mentionsWithoutEdge': mentionsWithoutEdge,
    if (failure != null) 'failure': failure,
  };
}

class ChannelMeasurementSummary {
  const ChannelMeasurementSummary({
    required this.model,
    required this.endpoint,
    required this.observations,
  });

  final String model;
  final String endpoint;
  final List<ChannelObservation> observations;

  Iterable<ChannelObservation> _arm(ChannelArm arm) =>
      observations.where((item) => item.arm == arm);

  Map<String, dynamic> toJson() => {
    'model': model,
    'endpoint': endpoint,
    'observations': observations.map((item) => item.toJson()).toList(),
  };

  String report() {
    final buffer = StringBuffer()
      ..writeln('ANA1 precondition channel measurement')
      ..writeln('model: $model')
      ..writeln('endpoint: $endpoint')
      ..writeln('requests: ${observations.length}')
      ..writeln();
    buffer.writeln(
      'arm     | parsed | tasks | edges | resolved | plans with an edge | '
      'ordering named, no edge',
    );
    for (final arm in ChannelArm.values) {
      final rows = _arm(arm).toList(growable: false);
      if (rows.isEmpty) continue;
      final parsed = rows.where((row) => row.parsed).toList(growable: false);
      final edges = parsed.fold<int>(0, (sum, row) => sum + row.edgeCount);
      final resolved = parsed.fold<int>(
        0,
        (sum, row) => sum + row.resolvedEdgeCount,
      );
      final withEdge = parsed.where((row) => row.edgeCount > 0).length;
      final mentioned = parsed.where((row) => row.mentionsWithoutEdge).length;
      final tasks = parsed.fold<int>(0, (sum, row) => sum + row.taskCount);
      buffer.writeln(
        <String>[
          arm.name.padRight(7),
          '${parsed.length}/${rows.length}'.padRight(6),
          tasks.toString().padRight(5),
          edges.toString().padRight(5),
          resolved.toString().padRight(8),
          '$withEdge/${parsed.length}'.padRight(18),
          '$mentioned/${parsed.length}',
        ].join(' | '),
      );
    }
    final failures = observations
        .where((row) => row.failure != null)
        .toList(growable: false);
    if (failures.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('unscored (${failures.length}):');
      for (final row in failures) {
        buffer.writeln(
          '  ${row.scenarioId} ${row.arm.name} #${row.repeat}: ${row.failure}',
        );
      }
    }
    return buffer.toString();
  }
}

Future<ChannelMeasurementSummary> runPreconditionChannelMeasurement({
  required ChannelMeasurementOptions options,
  required ChatCompletionSender send,
  void Function(String line)? onProgress,
  List<ChannelScenario> scenarios = channelScenarios,
}) async {
  final observations = <ChannelObservation>[];
  for (final scenario in scenarios) {
    for (var repeat = 1; repeat <= options.repeats; repeat++) {
      for (final arm in ChannelArm.values) {
        onProgress?.call('${scenario.id} ${arm.name} #$repeat');
        observations.add(
          await _observe(
            scenario: scenario,
            arm: arm,
            repeat: repeat,
            send: send,
            dumpDir: options.dumpDir,
          ),
        );
      }
    }
  }
  return ChannelMeasurementSummary(
    model: options.model,
    endpoint: options.endpoint,
    observations: observations,
  );
}

Future<ChannelObservation> _observe({
  required ChannelScenario scenario,
  required ChannelArm arm,
  required int repeat,
  required ChatCompletionSender send,
  String? dumpDir,
}) async {
  final prompt = buildChannelPrompt(scenario: scenario, arm: arm);
  String raw;
  try {
    raw = await send(_systemPrompt, prompt);
  } on Object catch (error) {
    // A transport failure is not a model that wrote no edges.
    return ChannelObservation(
      scenarioId: scenario.id,
      arm: arm,
      repeat: repeat,
      parsed: false,
      taskCount: 0,
      edgeCount: 0,
      resolvedEdgeCount: 0,
      mentionsWithoutEdge: false,
      failure: 'request failed: $error',
    );
  }
  if (dumpDir != null) {
    final file = File('$dumpDir/${scenario.id}.${arm.name}.$repeat.txt');
    await file.parent.create(recursive: true);
    await file.writeAsString(raw);
  }
  return scoreChannelResponse(
    scenarioId: scenario.id,
    arm: arm,
    repeat: repeat,
    rawContent: raw,
    contractReferences: scenario.contractReferences,
  );
}

/// The production **task** prompt, plus the arm's instruction.
///
/// `buildTaskProposalRequest`, not `buildWorkflowProposalRequest`: the proposal
/// phase returns a contract and no tasks, so an edge has nowhere to live there.
String buildChannelPrompt({
  required ChannelScenario scenario,
  required ChannelArm arm,
}) {
  final start = DateTime(2026, 9, 4, 10);
  final messages = <Message>[
    Message(
      id: '${scenario.id}-request',
      role: MessageRole.user,
      timestamp: start,
      content: scenario.request,
    ),
  ];
  final spec = ConversationWorkflowSpec(
    goal: scenario.goal,
    constraints: scenario.constraints,
    openQuestions: scenario.openQuestions,
  );
  final conversation = Conversation(
    id: scenario.id,
    title: scenario.id,
    messages: messages,
    createdAt: start,
    updatedAt: start,
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: spec,
  );
  final base = ConversationPlanningPromptService.buildTaskProposalRequest(
    currentConversation: conversation,
    messages: messages,
    languageCode: 'en',
    workflowSpecOverride: spec,
    workflowStageOverride: ConversationWorkflowStage.implement,
  );
  final instruction = armInstruction(arm);
  return instruction.isEmpty ? base : '$base\n$instruction';
}

/// Scores one raw response for [arm].
ChannelObservation scoreChannelResponse({
  required String scenarioId,
  required ChannelArm arm,
  required int repeat,
  required String rawContent,
  Set<String> contractReferences = const <String>{},
}) {
  ChannelObservation unscored(String failure) => ChannelObservation(
    scenarioId: scenarioId,
    arm: arm,
    repeat: repeat,
    parsed: false,
    taskCount: 0,
    edgeCount: 0,
    resolvedEdgeCount: 0,
    mentionsWithoutEdge: false,
    failure: failure,
  );

  final decoded = _decodeProposal(rawContent);
  if (decoded == null) {
    return unscored('no JSON proposal object in the response');
  }
  final tasks = _tasksOf(decoded);
  if (tasks.isEmpty) {
    return unscored('proposal carried no tasks');
  }

  final titles = <String>[
    for (final task in tasks) _titleOf(task).trim(),
  ].where((title) => title.isNotEmpty).toList(growable: false);
  // The contract comes from the scenario, not from the response: an edge that
  // resolves only against text the same response invented has pointed at
  // nothing the plan is actually bound by.
  final references = <String>{
    ...titles.map(_normalizeRef),
    ...contractReferences.map(_normalizeRef),
  };

  final edges = <ConversationTaskPrecondition>[];
  for (final task in tasks) {
    edges.addAll(switch (arm) {
      ChannelArm.none => const <ConversationTaskPrecondition>[],
      ChannelArm.title => extractTitleEdges(_titleOf(task)),
      ChannelArm.schema => extractSchemaEdges(task),
    });
  }

  final resolved = edges
      .where((edge) => _resolves(edge, references, titles))
      .length;
  return ChannelObservation(
    scenarioId: scenarioId,
    arm: arm,
    repeat: repeat,
    parsed: true,
    taskCount: tasks.length,
    edgeCount: edges.length,
    resolvedEdgeCount: resolved,
    mentionsWithoutEdge: edges.isEmpty && _namesOrdering(rawContent),
  );
}

final _titleEdgePattern = RegExp(
  r'\[\s*requires\s*:\s*([^\]]+)\]',
  caseSensitive: false,
);

/// Reads `[requires: <kind>: <ref>]` groups out of a task title.
List<ConversationTaskPrecondition> extractTitleEdges(String title) {
  final edges = <ConversationTaskPrecondition>[];
  for (final match in _titleEdgePattern.allMatches(title)) {
    final edge = _edgeFrom(match.group(1) ?? '');
    if (edge != null) edges.add(edge);
  }
  return edges;
}

/// Reads a task's `preconditions` array through the production extractor.
///
/// Delegating rather than duplicating: the extractor that chose the channel is
/// the one that ships, so a later change to it cannot quietly make this
/// measurement unreproducible.
List<ConversationTaskPrecondition> extractSchemaEdges(
  Map<String, dynamic> task,
) => TaskPreconditionParsing.fromProposalTask(task);

ConversationTaskPrecondition? _edgeFrom(String body) =>
    TaskPreconditionParsing.parseInline(body);

/// Whether an edge names something the same plan contains.
///
/// Matching is deliberately loose — prefix, containment either way — because
/// the question is whether the model pointed at its own plan, not whether it
/// reproduced a string exactly.
bool _resolves(
  ConversationTaskPrecondition edge,
  Set<String> references,
  List<String> titles,
) {
  final ref = _normalizeRef(edge.ref);
  if (ref.isEmpty) return false;
  if (references.contains(ref)) return true;
  return references.any(
    (candidate) =>
        candidate.isNotEmpty &&
        (candidate.contains(ref) || ref.contains(candidate)),
  );
}

String _normalizeRef(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\[\s*requires\s*:[^\]]*\]', caseSensitive: false), '')
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _orderingPattern = RegExp(
  r'\b(depends on|dependency|dependencies|precondition|prerequisite|blocked by|requires|after we|once we)\b',
  caseSensitive: false,
);

bool _namesOrdering(String raw) => _orderingPattern.hasMatch(raw);

Map<String, dynamic>? _decodeProposal(String rawContent) {
  final trimmed = _stripCodeFence(rawContent);
  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(trimmed.substring(start, end + 1));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

List<Map<String, dynamic>> _tasksOf(Map<String, dynamic> proposal) {
  final raw = proposal['tasks'] ?? proposal['taskDraft'] ?? proposal['steps'];
  final list = raw is Map ? raw['tasks'] : raw;
  if (list is! List) return const [];
  return list.whereType<Map<String, dynamic>>().toList(growable: false);
}

String _titleOf(Map<String, dynamic> task) =>
    '${task['title'] ?? task['name'] ?? task['task'] ?? ''}';

String _stripCodeFence(String content) {
  final trimmed = content.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  final firstBreak = trimmed.indexOf('\n');
  if (firstBreak < 0) return trimmed;
  final withoutOpening = trimmed.substring(firstBreak + 1);
  final closing = withoutOpening.lastIndexOf('```');
  return closing < 0
      ? withoutOpening.trim()
      : withoutOpening.substring(0, closing).trim();
}

Future<String> _postChatCompletion({
  required HttpClient client,
  required ChannelMeasurementOptions options,
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
  // Content-Length, not chunked: llama.cpp answers a chunked request body with
  // HTTP 500 "attempting to parse an empty input".
  final payload = utf8.encode(
    jsonEncode({
      'model': options.model,
      'temperature': options.temperature,
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
  final message = (choices.first as Map<String, dynamic>)['message'];
  return ((message as Map<String, dynamic>)['content'] as String?) ?? '';
}

String? _chatCompletionsFrom(String? baseUrl) {
  final trimmed = baseUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final withoutSlash = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  return withoutSlash.endsWith('/chat/completions')
      ? withoutSlash
      : '$withoutSlash/chat/completions';
}

class ChannelMeasurementOptions {
  const ChannelMeasurementOptions({
    required this.endpoint,
    required this.model,
    required this.apiKey,
    required this.repeats,
    required this.temperature,
    required this.timeout,
    required this.json,
    required this.outputPath,
    required this.dumpDir,
  });

  static const usage =
      'Usage: dart run tool/ana1_precondition_channel_measurement.dart \\\n'
      '  --endpoint http://host:1234/v1/chat/completions --model <id> \\\n'
      '  [--repeats 1] [--temperature 0.7] [--timeout 180] \\\n'
      '  [--json] [--out build/ana1/channel.json] [--dump-dir build/ana1/raw]\n'
      'Falls back to CAVERNO_LLM_ENDPOINT / CAVERNO_LLM_MODEL / '
      'CAVERNO_LLM_API_KEY, then to CAVERNO_LLM_BASE_URL.';

  final String endpoint;
  final String model;
  final String apiKey;
  final int repeats;
  final double temperature;
  final Duration timeout;
  final bool json;
  final String? outputPath;

  /// Where to write each raw response.
  ///
  /// Zero edges has two very different causes -- the model wrote none, or it
  /// wrote them in a form the extractor does not read -- and the counts cannot
  /// tell those apart.
  final String? dumpDir;

  static ChannelMeasurementOptions? parse(
    List<String> args,
    Map<String, String> environment,
  ) {
    var endpoint =
        environment['CAVERNO_LLM_ENDPOINT'] ??
        _chatCompletionsFrom(environment['CAVERNO_LLM_BASE_URL']) ??
        '';
    var model = environment['CAVERNO_LLM_MODEL'] ?? '';
    var apiKey = environment['CAVERNO_LLM_API_KEY'] ?? '';
    var repeats = 1;
    var temperature = 0.7;
    var timeoutSeconds = 180;
    var json = false;
    String? outputPath;
    String? dumpDir;

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
        case '--dump-dir':
          dumpDir = value(i);
          i++;
        case '--json':
          json = true;
        case '--help':
          return null;
      }
    }
    if (endpoint.isEmpty || model.isEmpty || repeats < 1) return null;
    return ChannelMeasurementOptions(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      repeats: repeats,
      temperature: temperature,
      timeout: Duration(seconds: timeoutSeconds),
      json: json,
      outputPath: outputPath,
      dumpDir: dumpDir,
    );
  }
}
