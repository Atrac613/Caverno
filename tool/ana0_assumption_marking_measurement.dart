import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/workflow_proposal_draft.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_planning_prompt_service.dart';
import 'package:caverno/features/chat/domain/services/workflow_proposal_parser.dart';
import 'package:caverno/features/chat/domain/services/workflow_task_proposal_quality_service.dart';

/// Anabasis ANA0 PR 3c — how often does the model mark what it is assuming?
///
/// PR 3b taught the planning prompt to end an assumed item with `(assumed)` or
/// `(assumed, material)`. Two numbers decide PR 4's confirm surface, and
/// neither can be guessed:
///
/// - **material assumptions per plan**, which decides whether the surface is a
///   per-assumption approval or a batch review;
/// - **the over-assertion rate**, how often a plan states as settled fact
///   something the conversation never established.
///
/// Ground truth comes from pairing, not from judging prose. Every scenario runs
/// twice over the same request: an `ungrounded` arm where one load-bearing fact
/// is absent from the transcript, and a `grounded` arm identical but for one
/// message that states it. A constraint restating that fact is an assumption in
/// the first arm and a fact in the second, by construction — so an unmarked
/// ungrounded plan is an over-assertion and a marked grounded plan is an
/// over-mark, and nothing has to read what the model wrote to decide which.
///
/// Scoring counts marks off the projected provenance, through the production
/// path: real prompt, real proposal parser, real plan document, real
/// projection. Nothing here re-implements the thing being measured.
///
/// Two deliberate limits, so the numbers are read as what they are. The system
/// message is short rather than the full Caverno system prompt, which needs
/// settings, a project and memory: a rule the model cannot follow with a clean
/// system prompt will not survive a crowded one, so this is a floor. And no
/// tools are attached, because planning does not call them.
Future<void> main(List<String> args) async {
  final options = MeasurementOptions.parse(args, Platform.environment);
  if (options == null) {
    stderr.writeln(MeasurementOptions.usage);
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  try {
    final summary = await runAssumptionMarkingMeasurement(
      options: options,
      send: (system, user) => _postChatCompletion(
        client: client,
        options: options,
        systemPrompt: system,
        userPrompt: user,
      ),
      onProgress: (line) => stderr.writeln(line),
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(summary.toJson());
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

/// Sends one proposal request and returns the raw assistant content.
typedef ChatCompletionSender =
    Future<String> Function(String systemPrompt, String userPrompt);

const _systemPrompt =
    'You are a planning assistant inside a coding agent. Follow the '
    'instructions in the user message exactly and return only JSON.';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// One paired scenario.
///
/// [request] never mentions [groundingMessage]'s fact; the grounded arm adds it
/// as a prior turn. Everything else about the two arms is identical, so the
/// difference in marking is attributable to the fact's presence and to nothing
/// about how the request is worded.
class AssumptionScenario {
  const AssumptionScenario({
    required this.id,
    required this.request,
    required this.groundingMessage,
    required this.assumedFact,
  });

  final String id;
  final String request;

  /// The assistant turn that establishes [assumedFact] in the grounded arm.
  final String groundingMessage;

  /// What the ungrounded arm cannot know. Recorded for the report only; no
  /// scoring reads it.
  final String assumedFact;
}

const assumptionScenarios = <AssumptionScenario>[
  AssumptionScenario(
    id: 'incremental-sync',
    request:
        'Add iCloud sync to the notes app so records converge within one sync '
        'cycle. Plan it.',
    groundingMessage:
        'I checked the API docs: the backend already exposes an incremental '
        'sync endpoint, GET /v1/notes/changes?since=<cursor>.',
    assumedFact: 'the backend supports incremental (cursor-based) sync',
  ),
  AssumptionScenario(
    id: 'stable-ids',
    request:
        'Add offline conflict resolution to the task list. Plan the work.',
    groundingMessage:
        'For context: every task row has carried a server-assigned UUID since '
        'the v2 migration, and those ids never change.',
    assumedFact: 'existing rows have stable unique ids',
  ),
  AssumptionScenario(
    id: 'auth-refresh',
    request:
        'Make the mobile client keep the user signed in across app restarts. '
        'Plan it.',
    groundingMessage:
        'Confirmed with the backend team: the auth service issues refresh '
        'tokens with a 30-day lifetime and supports silent refresh.',
    assumedFact: 'the auth service issues long-lived refresh tokens',
  ),
  AssumptionScenario(
    id: 'push-entitlement',
    request:
        'Add push notifications for shared-document comments. Plan the work.',
    groundingMessage:
        'We already ship push for chat, so the APNs entitlement and the device '
        'token registration path are both in place.',
    assumedFact: 'the app already holds a push entitlement',
  ),
  AssumptionScenario(
    id: 'migration-window',
    request:
        'Move the local store from SharedPreferences to a database. Plan it.',
    groundingMessage:
        'Note that every existing install is on build 42 or later, so there is '
        'exactly one legacy layout to migrate from.',
    assumedFact: 'there is a single legacy on-disk layout',
  ),
  AssumptionScenario(
    id: 'rate-limit',
    request:
        'Add a background sync that mirrors the inbox every few minutes. Plan '
        'the work.',
    groundingMessage:
        'The provider documents a 600 requests/minute quota per account, and '
        'we are nowhere near it today.',
    assumedFact: 'the upstream API tolerates frequent polling',
  ),
];

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

enum ScenarioArm { grounded, ungrounded }

/// One request's outcome, scored off the projected contract.
class ArmObservation {
  const ArmObservation({
    required this.scenarioId,
    required this.arm,
    required this.repeat,
    required this.parsed,
    required this.itemCount,
    required this.assumedCount,
    required this.materialCount,
    required this.openQuestionCount,
    required this.markedOpenQuestionCount,
    this.failure,
  });

  final String scenarioId;
  final ScenarioArm arm;
  final int repeat;

  /// Whether the response became a workflow spec at all. An unparsed response
  /// is reported, never scored as an unmarked plan: a model that returned prose
  /// did not assert anything about what it assumed.
  final bool parsed;
  final int itemCount;
  final int assumedCount;
  final int materialCount;

  /// Open questions the plan raised.
  ///
  /// The other honest way to dispose of something the conversation never
  /// established, and the planning prompt asks for it by name. A plan that
  /// raises the unknown as a question has not asserted it, so counting that
  /// plan as an over-assertion would measure the prompt's own instruction.
  final int openQuestionCount;

  /// Open questions the model tried to mark.
  ///
  /// Reported because the aggregate hid it for a whole run: PR 3c's summary
  /// counted marks without their kind, and four of its five material marks
  /// turned out to be on questions rather than on anything the plan asserted.
  /// A number that cannot express the distinction it is asked about will be
  /// read as though it had.
  ///
  /// After PR 3d these are dropped in `ConversationContractProvenanceService`,
  /// so this counts what the model attempted, not what survived.
  final int markedOpenQuestionCount;
  final String? failure;

  Map<String, dynamic> toJson() => {
    'scenario': scenarioId,
    'arm': arm.name,
    'repeat': repeat,
    'parsed': parsed,
    'items': itemCount,
    'assumed': assumedCount,
    'material': materialCount,
    'openQuestions': openQuestionCount,
    'markedOpenQuestions': markedOpenQuestionCount,
    if (failure != null) 'failure': failure,
  };
}

class MeasurementSummary {
  const MeasurementSummary({
    required this.model,
    required this.endpoint,
    required this.compact,
    required this.observations,
  });

  final String model;
  final String endpoint;
  final bool compact;
  final List<ArmObservation> observations;

  Iterable<ArmObservation> _scored(ScenarioArm arm) =>
      observations.where((o) => o.arm == arm && o.parsed);

  int parsedCount(ScenarioArm arm) => _scored(arm).length;

  double materialPerPlan(ScenarioArm arm) {
    final scored = _scored(arm).toList(growable: false);
    if (scored.isEmpty) return 0;
    final total = scored.fold<int>(0, (sum, o) => sum + o.materialCount);
    return total / scored.length;
  }

  /// Ungrounded plans that disposed of the unknown in neither honest way:
  /// no epistemic mark and no open question, so the plan simply asserted.
  ///
  /// The first version of this counted every unmarked ungrounded plan, and the
  /// first live run scored 6/6 on it. Reading the responses showed that number
  /// was measuring the prompt: the same prompt says "if important information
  /// is missing, use openQuestions", and the model was routing the unknown
  /// there — correctly — on all six. A plan that asks about a fact has not
  /// asserted it. The rule and the marker compete for the same content, so a
  /// metric blind to one of them scores obedience to the prompt as a failure.
  ///
  /// Corrected twice, both times by reading the responses. The second version
  /// still required a *material* mark, and the 36-request run then flagged a
  /// plan that had marked three items as assumptions without calling any of
  /// them material. Marking something non-material is a claim about
  /// consequence, not about knowledge; the plan said plainly that it did not
  /// know. Any mark counts as disposal here, and materiality is reported
  /// separately because that is what decides blocking.
  int overAssertions() => _scored(ScenarioArm.ungrounded)
      .where((o) => o.assumedCount == 0 && o.openQuestionCount == 0)
      .length;

  /// Ungrounded plans that used the marker rather than an open question.
  ///
  /// The split matters to PR 4 and the count alone hides it: a mark blocks
  /// execution until someone confirms it, and an open question does not.
  int markedRatherThanAsked() => _scored(ScenarioArm.ungrounded)
      .where((o) => o.materialCount > 0)
      .length;

  double openQuestionsPerPlan(ScenarioArm arm) {
    final scored = _scored(arm).toList(growable: false);
    if (scored.isEmpty) return 0;
    final total = scored.fold<int>(0, (sum, o) => sum + o.openQuestionCount);
    return total / scored.length;
  }

  /// Grounded plans that marked something material anyway.
  int overMarks() =>
      _scored(ScenarioArm.grounded).where((o) => o.materialCount > 0).length;

  int unparsed() => observations.where((o) => !o.parsed).length;

  /// Plans that tried to mark an open question, in either arm.
  ///
  /// Not a rate on its own: it says how much of the model's marking effort goes
  /// somewhere the mark cannot mean anything.
  int plansMarkingOpenQuestions() =>
      observations.where((o) => o.parsed && o.markedOpenQuestionCount > 0).length;

  Map<String, dynamic> toJson() => {
    'schema': 'caverno_ana0_assumption_marking',
    'schemaVersion': 1,
    'model': model,
    'endpoint': endpoint,
    'compact': compact,
    'requests': observations.length,
    'unparsed': unparsed(),
    'grounded': {
      'scored': parsedCount(ScenarioArm.grounded),
      'materialPerPlan': materialPerPlan(ScenarioArm.grounded),
      'openQuestionsPerPlan': openQuestionsPerPlan(ScenarioArm.grounded),
      'overMarks': overMarks(),
      'markedOpenQuestions': _scored(
        ScenarioArm.grounded,
      ).fold<int>(0, (sum, o) => sum + o.markedOpenQuestionCount),
    },
    'ungrounded': {
      'scored': parsedCount(ScenarioArm.ungrounded),
      'materialPerPlan': materialPerPlan(ScenarioArm.ungrounded),
      'openQuestionsPerPlan': openQuestionsPerPlan(ScenarioArm.ungrounded),
      'overAssertions': overAssertions(),
      'markedRatherThanAsked': markedRatherThanAsked(),
      'markedOpenQuestions': _scored(
        ScenarioArm.ungrounded,
      ).fold<int>(0, (sum, o) => sum + o.markedOpenQuestionCount),
    },
    'discrimination':
        materialPerPlan(ScenarioArm.ungrounded) -
        materialPerPlan(ScenarioArm.grounded),
    'observations': observations.map((o) => o.toJson()).toList(growable: false),
  };

  String report() {
    final ungroundedScored = parsedCount(ScenarioArm.ungrounded);
    final groundedScored = parsedCount(ScenarioArm.grounded);
    final buffer = StringBuffer()
      ..writeln('ANA0 — assumption marking')
      ..writeln('model: $model  endpoint: $endpoint  compact: $compact')
      ..writeln('requests: ${observations.length}  unparsed: ${unparsed()}')
      ..writeln()
      ..writeln('material assumptions per plan')
      ..writeln(
        '  ungrounded: ${materialPerPlan(ScenarioArm.ungrounded).toStringAsFixed(2)} '
        '($ungroundedScored scored)',
      )
      ..writeln(
        '  grounded:   ${materialPerPlan(ScenarioArm.grounded).toStringAsFixed(2)} '
        '($groundedScored scored)',
      )
      ..writeln(
        '  discrimination: '
        '${(materialPerPlan(ScenarioArm.ungrounded) - materialPerPlan(ScenarioArm.grounded)).toStringAsFixed(2)}',
      )
      ..writeln()
      ..writeln('open questions per plan')
      ..writeln(
        '  ungrounded: ${openQuestionsPerPlan(ScenarioArm.ungrounded).toStringAsFixed(2)}',
      )
      ..writeln(
        '  grounded:   ${openQuestionsPerPlan(ScenarioArm.grounded).toStringAsFixed(2)}',
      )
      ..writeln()
      ..writeln(
        'over-assertion: ${overAssertions()}/$ungroundedScored '
        'ungrounded plans neither marked nor asked',
      )
      ..writeln(
        'marked not asked: ${markedRatherThanAsked()}/$ungroundedScored '
        'ungrounded plans used the marker',
      )
      ..writeln(
        'over-mark:      ${overMarks()}/$groundedScored '
        'grounded plans marked something material',
      )
      ..writeln(
        'marked a question: ${plansMarkingOpenQuestions()}/'
        '${ungroundedScored + groundedScored} plans put a marker on an open '
        'question, where it cannot mean anything (dropped since PR 3d)',
      );
    return buffer.toString();
  }
}

Future<MeasurementSummary> runAssumptionMarkingMeasurement({
  required MeasurementOptions options,
  required ChatCompletionSender send,
  void Function(String line)? onProgress,
  List<AssumptionScenario> scenarios = assumptionScenarios,
}) async {
  final observations = <ArmObservation>[];
  for (final scenario in scenarios) {
    for (var repeat = 1; repeat <= options.repeats; repeat++) {
      for (final arm in ScenarioArm.values) {
        onProgress?.call('${scenario.id} ${arm.name} #$repeat');
        observations.add(
          await _observe(
            scenario: scenario,
            arm: arm,
            repeat: repeat,
            compact: options.compact,
            send: send,
            dumpDir: options.dumpDir,
          ),
        );
      }
    }
  }
  return MeasurementSummary(
    model: options.model,
    endpoint: options.endpoint,
    compact: options.compact,
    observations: observations,
  );
}

Future<ArmObservation> _observe({
  required AssumptionScenario scenario,
  required ScenarioArm arm,
  required int repeat,
  required bool compact,
  required ChatCompletionSender send,
  String? dumpDir,
}) async {
  final prompt = buildScenarioPrompt(
    scenario: scenario,
    arm: arm,
    compact: compact,
  );
  String raw;
  try {
    raw = await send(_systemPrompt, prompt);
  } on Object catch (error) {
    return ArmObservation(
      scenarioId: scenario.id,
      arm: arm,
      repeat: repeat,
      parsed: false,
      itemCount: 0,
      assumedCount: 0,
      materialCount: 0,
      openQuestionCount: 0,
      markedOpenQuestionCount: 0,
      failure: 'request failed: $error',
    );
  }
  if (dumpDir != null) {
    final file = File('$dumpDir/${scenario.id}.${arm.name}.$repeat.txt');
    await file.parent.create(recursive: true);
    await file.writeAsString(raw);
  }
  return scoreResponse(
    scenarioId: scenario.id,
    arm: arm,
    repeat: repeat,
    rawContent: raw,
  );
}

/// The production proposal prompt for one arm of one scenario.
String buildScenarioPrompt({
  required AssumptionScenario scenario,
  required ScenarioArm arm,
  required bool compact,
}) {
  final start = DateTime(2026, 9, 3, 10);
  final messages = <Message>[
    if (arm == ScenarioArm.grounded)
      Message(
        id: '${scenario.id}-grounding',
        role: MessageRole.user,
        timestamp: start,
        content: scenario.groundingMessage,
      ),
    Message(
      id: '${scenario.id}-request',
      role: MessageRole.user,
      timestamp: start.add(const Duration(minutes: 1)),
      content: scenario.request,
    ),
  ];
  final conversation = Conversation(
    id: scenario.id,
    title: scenario.id,
    messages: messages,
    createdAt: start,
    updatedAt: start.add(const Duration(minutes: 1)),
    workflowStage: ConversationWorkflowStage.plan,
  );
  return ConversationPlanningPromptService.buildWorkflowProposalRequest(
    currentConversation: conversation,
    messages: messages,
    languageCode: 'en',
    compact: compact,
  );
}

/// Scores one raw assistant response through the production path.
ArmObservation scoreResponse({
  required String scenarioId,
  required ScenarioArm arm,
  required int repeat,
  required String rawContent,
}) {
  ArmObservation unscored(String failure) => ArmObservation(
    scenarioId: scenarioId,
    arm: arm,
    repeat: repeat,
    parsed: false,
    itemCount: 0,
    assumedCount: 0,
    materialCount: 0,
    openQuestionCount: 0,
    markedOpenQuestionCount: 0,
    failure: failure,
  );

  final parser = WorkflowProposalParser(
    qualityService: WorkflowTaskProposalQualityService(),
  );
  final draft = _parseDraft(parser, rawContent);
  if (draft == null) {
    return unscored('no workflow proposal in the response');
  }

  // Through the document, because the document is where a marker becomes a
  // mark. Scoring the JSON directly would measure a path production never runs.
  final markdown = ConversationPlanDocumentBuilder.build(
    workflowStage: draft.workflowStage,
    workflowSpec: draft.workflowSpec,
  );
  final ConversationWorkflowSpec spec;
  try {
    spec = ConversationPlanProjectionService.deriveExecutionProjection(
      approvedMarkdown: markdown,
      requireTasks: false,
    ).workflowSpec;
  } on FormatException catch (error) {
    return unscored('projection rejected the document: ${error.message}');
  }

  // Counted off the draft, not the projection: PR 3d drops a mark on an open
  // question, so by the time provenance exists the attempt is gone. What the
  // model tried to do is the number this instrument exists to expose.
  final markedOpenQuestions = draft.workflowSpec.openQuestions
      .where((value) => ContractItemMarks.parseBullet(value).marks.assumption)
      .length;

  final itemCount =
      spec.constraints.length +
      spec.acceptanceCriteria.length +
      spec.openQuestions.length;
  final assumed = spec.provenance.where((item) => item.assumption);
  return ArmObservation(
    scenarioId: scenarioId,
    arm: arm,
    repeat: repeat,
    parsed: true,
    itemCount: itemCount,
    assumedCount: assumed.length,
    materialCount: assumed.where((item) => item.material).length,
    openQuestionCount: spec.openQuestions.length,
    markedOpenQuestionCount: markedOpenQuestions,
  );
}

WorkflowProposalDraft? _parseDraft(
  WorkflowProposalParser parser,
  String rawContent,
) {
  final trimmed = _stripCodeFence(rawContent);
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) {
      final draft = parser.parseWorkflowProposalMap(decoded);
      if (draft != null) return draft;
    }
  } on FormatException {
    // Fall through to the loose parsers production also falls through to.
  }
  return parser.parseWorkflowProposalFromLooseJson(trimmed) ??
      parser.parseWorkflowProposalFromSections(trimmed);
}

String _stripCodeFence(String content) {
  final trimmed = content.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  final firstBreak = trimmed.indexOf('\n');
  if (firstBreak < 0) return trimmed;
  final withoutOpen = trimmed.substring(firstBreak + 1);
  final closing = withoutOpen.lastIndexOf('```');
  return (closing < 0 ? withoutOpen : withoutOpen.substring(0, closing)).trim();
}

// ---------------------------------------------------------------------------
// Transport and options
// ---------------------------------------------------------------------------

Future<String> _postChatCompletion({
  required HttpClient client,
  required MeasurementOptions options,
  required String systemPrompt,
  required String userPrompt,
}) async {
  final request = await client.postUrl(Uri.parse(options.endpoint));
  request.headers.contentType = ContentType.json;
  if (options.apiKey.isNotEmpty) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${options.apiKey}');
  }
  // Content-Length, not chunked. Dart's HttpClient chunks a body written with
  // `write`, and llama.cpp's server (b10523) answers a chunked request body
  // with HTTP 500 "attempting to parse an empty input" -- reproduced with curl
  // against the same endpoint, so it is the transfer encoding and not the JSON.
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

/// `<base>/chat/completions` for a base URL such as `http://host:1234/v1`.
///
/// `tool/with_live_llm_loopback.sh` hands its child a rewritten
/// `CAVERNO_LLM_BASE_URL`, and that wrapper is the only supported way to reach
/// a LAN endpoint from a spawned process on macOS.
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

class MeasurementOptions {
  const MeasurementOptions({
    required this.endpoint,
    required this.model,
    required this.apiKey,
    required this.repeats,
    required this.compact,
    required this.temperature,
    required this.timeout,
    required this.json,
    required this.outputPath,
    required this.dumpDir,
  });

  static const usage =
      'Usage: dart run tool/ana0_assumption_marking_measurement.dart \\\n'
      '  --endpoint http://host:1234/v1/chat/completions --model <id> \\\n'
      '  [--repeats 1] [--compact] [--temperature 0.7] [--timeout 180] \\\n'
      '  [--json] [--out build/ana0/marking.json] [--dump-dir build/ana0/raw]\n'
      'Falls back to CAVERNO_LLM_ENDPOINT / CAVERNO_LLM_MODEL / '
      'CAVERNO_LLM_API_KEY, then to CAVERNO_LLM_BASE_URL so the run composes '
      'with tool/with_live_llm_loopback.sh. A LAN address is unreachable from '
      'a spawned process under macOS Local Network Privacy even while curl '
      'reaches it, so route through that wrapper rather than the raw IP.';

  final String endpoint;
  final String model;
  final String apiKey;
  final int repeats;
  final bool compact;
  final double temperature;
  final Duration timeout;
  final bool json;
  final String? outputPath;

  /// Where to write each raw response, when asked.
  ///
  /// A zero marking rate has two very different causes: the model did not mark,
  /// or it marked in a form `ContractItemMarks.parseBullet` does not read. The
  /// counts cannot tell those apart, so the responses have to be inspectable.
  final String? dumpDir;

  static MeasurementOptions? parse(
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
    var compact = false;
    var temperature = 0.7;
    var timeoutSeconds = 180;
    var json = false;
    String? outputPath;
    String? dumpDir;

    String? value(int index) => index + 1 < args.length ? args[index + 1] : null;
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
        case '--compact':
          compact = true;
        case '--json':
          json = true;
        case '--help':
          return null;
      }
    }
    if (endpoint.isEmpty || model.isEmpty || repeats < 1) return null;
    return MeasurementOptions(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      repeats: repeats,
      compact: compact,
      temperature: temperature,
      timeout: Duration(seconds: timeoutSeconds),
      json: json,
      outputPath: outputPath,
      dumpDir: dumpDir,
    );
  }
}
