import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_compaction_service.dart';
import 'package:caverno/features/chat/domain/services/model_switch_handoff_brief_service.dart';

Future<void> main(List<String> args) async {
  final options = Ll14ModelSwitchMeasurementOptions.parse(
    args,
    environment: Platform.environment,
  );
  if (options == null) {
    stderr.writeln(Ll14ModelSwitchMeasurementOptions.usage);
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  try {
    final summary = await runLl14ModelSwitchHandoffMeasurement(
      options: options,
      sender: (body) => postLl14OpenAiChatCompletion(
        client: client,
        endpoint: options.chatCompletionsEndpoint,
        apiKey: options.apiKey,
        body: body,
        timeout: options.timeout,
      ),
    );

    if (options.outputPath != null) {
      final output = File(options.outputPath!);
      await output.parent.create(recursive: true);
      await output.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(summary.toJson())}\n',
      );
    }

    switch (options.format) {
      case Ll14MeasurementOutputFormat.json:
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(summary.toJson()),
        );
      case Ll14MeasurementOutputFormat.markdown:
        stdout.write(summary.toMarkdown());
    }
  } finally {
    client.close(force: true);
  }
}

typedef Ll14ChatCompletionSender =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

enum Ll14MeasurementMode {
  fullHistoryReplay('full_history_replay'),
  modelSwitchHandoff('model_switch_handoff');

  const Ll14MeasurementMode(this.id);

  final String id;
}

enum Ll14MeasurementOutputFormat { markdown, json }

class Ll14ModelSwitchMeasurementOptions {
  const Ll14ModelSwitchMeasurementOptions({
    required this.baseUrl,
    required this.model,
    required this.previousModel,
    required this.apiKey,
    required this.turnCount,
    required this.turnDetailChars,
    required this.maxTokens,
    required this.timeout,
    required this.outputPath,
    required this.format,
  });

  final String baseUrl;
  final String model;
  final String previousModel;
  final String apiKey;
  final int turnCount;
  final int turnDetailChars;
  final int maxTokens;
  final Duration timeout;
  final String? outputPath;
  final Ll14MeasurementOutputFormat format;

  Uri get chatCompletionsEndpoint {
    final normalized = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized/chat/completions');
  }

  static const usage =
      'Usage: dart run tool/ll14_model_switch_handoff_measurement.dart '
      '[--base-url URL] [--model MODEL] [--previous-model MODEL] '
      '[--api-key KEY] [--turn-count N] [--turn-detail-chars N] '
      '[--max-tokens N] [--timeout-seconds N] [--output PATH] '
      '[--format markdown|json]\n\n'
      'Defaults: CAVERNO_LLM_BASE_URL or http://localhost:1234/v1, '
      'CAVERNO_LLM_MODEL or local-model, CAVERNO_LLM_PREVIOUS_MODEL or '
      'previous-local-model, CAVERNO_LLM_API_KEY or no-key.';

  static Ll14ModelSwitchMeasurementOptions? parse(
    List<String> args, {
    Map<String, String> environment = const {},
  }) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') return null;
      if (!arg.startsWith('--')) return null;
      final equalsIndex = arg.indexOf('=');
      if (equalsIndex > 0) {
        values[arg.substring(2, equalsIndex)] = arg.substring(equalsIndex + 1);
        continue;
      }
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        return null;
      }
      values[arg.substring(2)] = args[index + 1];
      index += 1;
    }

    final format = switch (values['format']?.trim().toLowerCase()) {
      null || '' || 'markdown' => Ll14MeasurementOutputFormat.markdown,
      'json' => Ll14MeasurementOutputFormat.json,
      _ => null,
    };
    if (format == null) return null;

    final turnCount = _parsePositiveInt(values['turn-count'], fallback: 48);
    final turnDetailChars = _parsePositiveInt(
      values['turn-detail-chars'],
      fallback: 260,
    );
    final maxTokens = _parsePositiveInt(values['max-tokens'], fallback: 16);
    final timeoutSeconds = _parsePositiveInt(
      values['timeout-seconds'],
      fallback: 120,
    );
    if (turnCount == null ||
        turnDetailChars == null ||
        maxTokens == null ||
        timeoutSeconds == null) {
      return null;
    }

    return Ll14ModelSwitchMeasurementOptions(
      baseUrl:
          values['base-url'] ??
          environment['CAVERNO_LLM_BASE_URL'] ??
          'http://localhost:1234/v1',
      model:
          values['model'] ?? environment['CAVERNO_LLM_MODEL'] ?? 'local-model',
      previousModel:
          values['previous-model'] ??
          environment['CAVERNO_LLM_PREVIOUS_MODEL'] ??
          'previous-local-model',
      apiKey:
          values['api-key'] ?? environment['CAVERNO_LLM_API_KEY'] ?? 'no-key',
      turnCount: turnCount,
      turnDetailChars: turnDetailChars,
      maxTokens: maxTokens,
      timeout: Duration(seconds: timeoutSeconds),
      outputPath: values['output'],
      format: format,
    );
  }

  static int? _parsePositiveInt(String? value, {required int fallback}) {
    if (value == null || value.trim().isEmpty) return fallback;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}

class Ll14TimingSample {
  const Ll14TimingSample({
    this.cacheN,
    this.promptN,
    this.promptMs,
    this.predictedN,
    this.predictedMs,
    this.promptPerSecond,
    this.predictedPerSecond,
  });

  final int? cacheN;
  final int? promptN;
  final double? promptMs;
  final int? predictedN;
  final double? predictedMs;
  final double? promptPerSecond;
  final double? predictedPerSecond;

  bool get hasPromptTiming => promptMs != null || promptN != null;

  factory Ll14TimingSample.fromResponseJson(Map<String, dynamic> response) {
    final timings = _asStringMap(response['timings']);
    if (timings == null) return const Ll14TimingSample();
    return Ll14TimingSample(
      cacheN: _asInt(timings['cache_n']),
      promptN: _asInt(timings['prompt_n']),
      promptMs: _asDouble(timings['prompt_ms']),
      predictedN: _asInt(timings['predicted_n']),
      predictedMs: _asDouble(timings['predicted_ms']),
      promptPerSecond: _asDouble(timings['prompt_per_second']),
      predictedPerSecond: _asDouble(timings['predicted_per_second']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (cacheN != null) 'cacheN': cacheN,
      if (promptN != null) 'promptN': promptN,
      if (promptMs != null) 'promptMs': promptMs,
      if (predictedN != null) 'predictedN': predictedN,
      if (predictedMs != null) 'predictedMs': predictedMs,
      if (promptPerSecond != null) 'promptPerSecond': promptPerSecond,
      if (predictedPerSecond != null) 'predictedPerSecond': predictedPerSecond,
    };
  }
}

class Ll14RequestStats {
  const Ll14RequestStats({
    required this.messageCount,
    required this.characterCount,
    required this.estimatedPromptTokens,
  });

  final int messageCount;
  final int characterCount;
  final int estimatedPromptTokens;

  Map<String, dynamic> toJson() {
    return {
      'messageCount': messageCount,
      'characterCount': characterCount,
      'estimatedPromptTokens': estimatedPromptTokens,
    };
  }
}

class Ll14MeasurementRun {
  const Ll14MeasurementRun({
    required this.mode,
    required this.stats,
    required this.timing,
    required this.warnings,
  });

  final Ll14MeasurementMode mode;
  final Ll14RequestStats stats;
  final Ll14TimingSample timing;
  final List<String> warnings;

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.id,
      'request': stats.toJson(),
      'timing': timing.toJson(),
      if (warnings.isNotEmpty) 'warnings': warnings,
    };
  }
}

class Ll14ModelSwitchHandoffMeasurementSummary {
  const Ll14ModelSwitchHandoffMeasurementSummary({
    required this.generatedAt,
    required this.baseUrl,
    required this.model,
    required this.previousModel,
    required this.turnCount,
    required this.fullHistoryRun,
    required this.handoffRun,
  });

  final DateTime generatedAt;
  final String baseUrl;
  final String model;
  final String previousModel;
  final int turnCount;
  final Ll14MeasurementRun fullHistoryRun;
  final Ll14MeasurementRun handoffRun;

  int get estimatedPromptTokenReduction {
    return fullHistoryRun.stats.estimatedPromptTokens -
        handoffRun.stats.estimatedPromptTokens;
  }

  double? get estimatedPromptTokenReductionRatio {
    final baseline = fullHistoryRun.stats.estimatedPromptTokens;
    if (baseline <= 0) return null;
    return estimatedPromptTokenReduction / baseline;
  }

  double? get promptMsReduction {
    final baseline = fullHistoryRun.timing.promptMs;
    final candidate = handoffRun.timing.promptMs;
    if (baseline == null || candidate == null) return null;
    return baseline - candidate;
  }

  double? get promptMsReductionRatio {
    final baseline = fullHistoryRun.timing.promptMs;
    final reduction = promptMsReduction;
    if (baseline == null || baseline <= 0 || reduction == null) return null;
    return reduction / baseline;
  }

  bool get estimatedPromptReduced => estimatedPromptTokenReduction > 0;

  bool? get promptMsImproved {
    final reduction = promptMsReduction;
    if (reduction == null) return null;
    return reduction > 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaName': 'caverno_ll14_model_switch_handoff_measurement',
      'schemaVersion': 1,
      'generatedAt': generatedAt.toIso8601String(),
      'baseUrl': baseUrl,
      'model': model,
      'previousModel': previousModel,
      'turnCount': turnCount,
      'fullHistoryRun': fullHistoryRun.toJson(),
      'handoffRun': handoffRun.toJson(),
      'comparison': {
        'estimatedPromptTokenReduction': estimatedPromptTokenReduction,
        if (estimatedPromptTokenReductionRatio != null)
          'estimatedPromptTokenReductionRatio':
              estimatedPromptTokenReductionRatio,
        'estimatedPromptReduced': estimatedPromptReduced,
        if (promptMsReduction != null) 'promptMsReduction': promptMsReduction,
        if (promptMsReductionRatio != null)
          'promptMsReductionRatio': promptMsReductionRatio,
        if (promptMsImproved != null) 'promptMsImproved': promptMsImproved,
      },
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL14 Model-Switch Handoff Measurement')
      ..writeln()
      ..writeln('- Generated: `${generatedAt.toIso8601String()}`')
      ..writeln('- Base URL: `$baseUrl`')
      ..writeln('- Previous model: `$previousModel`')
      ..writeln('- Model: `$model`')
      ..writeln('- Fixture turns: `$turnCount`')
      ..writeln()
      ..writeln(
        '| Mode | Messages | Estimated prompt tokens | prompt_n | prompt_ms |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: |');
    for (final run in [fullHistoryRun, handoffRun]) {
      buffer.writeln(
        '| `${run.mode.id}` | ${run.stats.messageCount} | '
        '${run.stats.estimatedPromptTokens} | '
        '${run.timing.promptN ?? '-'} | '
        '${_formatDouble(run.timing.promptMs)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Comparison')
      ..writeln()
      ..writeln(
        '- Estimated prompt-token reduction: '
        '`$estimatedPromptTokenReduction` '
        '(${_formatPercent(estimatedPromptTokenReductionRatio)})',
      )
      ..writeln('- Estimated prompt reduced: `$estimatedPromptReduced`')
      ..writeln(
        '- prompt_ms reduction: `${_formatDouble(promptMsReduction)}` '
        '(${_formatPercent(promptMsReductionRatio)})',
      )
      ..writeln('- prompt_ms improved: `${promptMsImproved ?? 'unknown'}`');

    final warnings = [
      ...fullHistoryRun.warnings.map((warning) => 'full_history: $warning'),
      ...handoffRun.warnings.map((warning) => 'handoff: $warning'),
    ];
    if (warnings.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Warnings')
        ..writeln();
      for (final warning in warnings) {
        buffer.writeln('- $warning');
      }
    }

    return buffer.toString();
  }
}

class Ll14MeasurementFixture {
  const Ll14MeasurementFixture({
    required this.conversation,
    required this.messages,
  });

  final Conversation conversation;
  final List<Message> messages;
}

Future<Ll14ModelSwitchHandoffMeasurementSummary>
runLl14ModelSwitchHandoffMeasurement({
  required Ll14ModelSwitchMeasurementOptions options,
  required Ll14ChatCompletionSender sender,
  DateTime? generatedAt,
}) async {
  final fixture = buildLl14MeasurementFixture(
    turnCount: options.turnCount,
    turnDetailChars: options.turnDetailChars,
  );
  final fullHistoryBody = buildLl14MeasurementRequestBody(
    mode: Ll14MeasurementMode.fullHistoryReplay,
    fixture: fixture,
    model: options.model,
    previousModel: options.previousModel,
    maxTokens: options.maxTokens,
  );
  final handoffBody = buildLl14MeasurementRequestBody(
    mode: Ll14MeasurementMode.modelSwitchHandoff,
    fixture: fixture,
    model: options.model,
    previousModel: options.previousModel,
    maxTokens: options.maxTokens,
  );

  final fullHistoryResponse = await sender(fullHistoryBody);
  final handoffResponse = await sender(handoffBody);
  final fullHistoryTiming = Ll14TimingSample.fromResponseJson(
    fullHistoryResponse,
  );
  final handoffTiming = Ll14TimingSample.fromResponseJson(handoffResponse);

  return Ll14ModelSwitchHandoffMeasurementSummary(
    generatedAt: generatedAt ?? DateTime.now(),
    baseUrl: options.baseUrl,
    model: options.model,
    previousModel: options.previousModel,
    turnCount: options.turnCount,
    fullHistoryRun: Ll14MeasurementRun(
      mode: Ll14MeasurementMode.fullHistoryReplay,
      stats: summarizeLl14RequestBody(fullHistoryBody),
      timing: fullHistoryTiming,
      warnings: [
        if (!fullHistoryTiming.hasPromptTiming)
          'Response did not include prompt timing fields.',
      ],
    ),
    handoffRun: Ll14MeasurementRun(
      mode: Ll14MeasurementMode.modelSwitchHandoff,
      stats: summarizeLl14RequestBody(handoffBody),
      timing: handoffTiming,
      warnings: [
        if (!handoffTiming.hasPromptTiming)
          'Response did not include prompt timing fields.',
      ],
    ),
  );
}

Ll14MeasurementFixture buildLl14MeasurementFixture({
  int turnCount = 48,
  int turnDetailChars = 260,
}) {
  final now = DateTime.utc(2026, 6, 14, 0);
  final messages = List<Message>.generate(turnCount, (index) {
    final role = index.isEven ? MessageRole.user : MessageRole.assistant;
    final subject = index.isEven
        ? 'User asks to continue LL14 context surgery slice $index.'
        : 'Assistant summarizes completed LL14 context surgery work $index.';
    return Message(
      id: 'll14-measure-message-$index',
      content: '$subject ${_detailText(index, turnDetailChars)}',
      role: role,
      timestamp: now.add(Duration(minutes: index)),
    );
  });
  final conversation = Conversation(
    id: 'll14-model-switch-measurement',
    title: 'LL14 model switch measurement',
    messages: messages,
    createdAt: now,
    updatedAt: now.add(Duration(minutes: turnCount)),
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: const ConversationWorkflowSpec(
      goal: 'Complete LL14 context surgery measurement',
      tasks: [
        ConversationWorkflowTask(
          id: 'll14-measurement',
          title: 'Measure model switch handoff prompt reduction',
          status: ConversationWorkflowTaskStatus.inProgress,
          targetFiles: [
            'tool/ll14_model_switch_handoff_measurement.dart',
            'docs/local_llm_agent_roadmap.md',
          ],
          validationCommand:
              'dart test test/tool/ll14_model_switch_handoff_measurement_test.dart',
        ),
      ],
    ),
    goal: ConversationGoal(
      id: 'll14-goal',
      objective: 'Close LL14 with a measurable model-switch handoff gate.',
      createdAt: now,
      updatedAt: now,
    ),
  );
  return Ll14MeasurementFixture(conversation: conversation, messages: messages);
}

Map<String, dynamic> buildLl14MeasurementRequestBody({
  required Ll14MeasurementMode mode,
  required Ll14MeasurementFixture fixture,
  required String model,
  required String previousModel,
  required int maxTokens,
}) {
  final messages = switch (mode) {
    Ll14MeasurementMode.fullHistoryReplay => _fullHistoryMessages(fixture),
    Ll14MeasurementMode.modelSwitchHandoff => _handoffMessages(
      fixture: fixture,
      previousModel: previousModel,
      nextModel: model,
    ),
  };
  return {
    'model': model,
    'messages': messages,
    'temperature': 0.1,
    'max_tokens': maxTokens,
    'stream': false,
    'cache_prompt': false,
  };
}

Ll14RequestStats summarizeLl14RequestBody(Map<String, dynamic> body) {
  final rawMessages = _asList(body['messages']);
  final messages = rawMessages
      .map((value) => _messageFromBodyMap(_asStringMap(value)))
      .whereType<Message>()
      .toList(growable: false);
  final characterCount = rawMessages.fold<int>(0, (count, value) {
    final map = _asStringMap(value);
    return count + ((map?['content'] as String?) ?? '').length;
  });
  return Ll14RequestStats(
    messageCount: rawMessages.length,
    characterCount: characterCount,
    estimatedPromptTokens: ConversationCompactionService.estimatePromptTokens(
      messages,
    ),
  );
}

Future<Map<String, dynamic>> postLl14OpenAiChatCompletion({
  required HttpClient client,
  required Uri endpoint,
  required String apiKey,
  required Map<String, dynamic> body,
  required Duration timeout,
}) async {
  final request = await client.postUrl(endpoint).timeout(timeout);
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
  request.write(jsonEncode(body));

  final response = await request.close().timeout(timeout);
  final responseText = await utf8.decoder
      .bind(response)
      .join()
      .timeout(timeout);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Ll14MeasurementHttpException(
      statusCode: response.statusCode,
      responseBody: responseText,
    );
  }
  final decoded = jsonDecode(responseText);
  if (decoded is! Map) {
    throw const FormatException('Expected a JSON object response.');
  }
  return Map<String, dynamic>.from(decoded);
}

class Ll14MeasurementHttpException implements Exception {
  const Ll14MeasurementHttpException({
    required this.statusCode,
    required this.responseBody,
  });

  final int statusCode;
  final String responseBody;

  @override
  String toString() {
    return 'LL14 measurement HTTP $statusCode: $responseBody';
  }
}

List<Map<String, dynamic>> _fullHistoryMessages(
  Ll14MeasurementFixture fixture,
) {
  return [
    _systemMessage(
      'You are the Caverno LL14 model-switch measurement assistant. '
      'Answer with one concise sentence.',
    ),
    ...fixture.messages.map(_messageToBodyMap),
    _userMessage('Continue the active LL14 task after the model switch.'),
  ];
}

List<Map<String, dynamic>> _handoffMessages({
  required Ll14MeasurementFixture fixture,
  required String previousModel,
  required String nextModel,
}) {
  final handoffBrief = ModelSwitchHandoffBriefService.build(
    conversation: fixture.conversation,
    messages: fixture.messages,
    previousModel: previousModel,
    nextModel: nextModel,
  );
  final compactionArtifact = ConversationCompactionService.buildArtifact(
    messages: fixture.messages,
    planDocument: fixture.conversation.displayPlanDocument(
      isPlanning: fixture.conversation.isPlanningSession,
    ),
    force: true,
  );
  final retainedMessages = ConversationCompactionService.retainMessages(
    messages: fixture.messages,
    artifact: compactionArtifact,
  );

  return [
    _systemMessage(
      'You are the Caverno LL14 model-switch measurement assistant. '
      'Answer with one concise sentence.',
    ),
    if (handoffBrief != null) _systemMessage(handoffBrief),
    if (compactionArtifact?.hasContent ?? false)
      _systemMessage(
        'Earlier conversation summary for omitted turns:\n'
        '${compactionArtifact!.normalizedSummary!}\n\n'
        'Treat this summary as context for the trimmed transcript that follows.',
      ),
    ...retainedMessages.map(_messageToBodyMap),
    _userMessage('Continue the active LL14 task after the model switch.'),
  ];
}

Map<String, dynamic> _systemMessage(String content) {
  return {'role': 'system', 'content': content};
}

Map<String, dynamic> _userMessage(String content) {
  return {'role': 'user', 'content': content};
}

Map<String, dynamic> _messageToBodyMap(Message message) {
  return {'role': _roleName(message.role), 'content': message.content};
}

Message? _messageFromBodyMap(Map<String, dynamic>? value) {
  if (value == null) return null;
  final role = switch ((value['role'] as String?)?.trim()) {
    'system' => MessageRole.system,
    'assistant' => MessageRole.assistant,
    'user' || _ => MessageRole.user,
  };
  final content = value['content'];
  if (content is! String) return null;
  return Message(
    id: 'request-${value.hashCode}',
    content: content,
    role: role,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

String _roleName(MessageRole role) {
  return switch (role) {
    MessageRole.system => 'system',
    MessageRole.assistant => 'assistant',
    MessageRole.user => 'user',
  };
}

String _detailText(int seed, int minChars) {
  final fragments = [
    'The task keeps a protected current focus file and references retained evidence.',
    'Earlier duplicate reads should be summarized only when compact context is active.',
    'The measurement must avoid treating assistant side-effect claims as proof.',
    'The prompt should remain model agnostic after switching from the previous model.',
  ];
  final buffer = StringBuffer();
  var index = 0;
  while (buffer.length < minChars) {
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(fragments[(seed + index) % fragments.length]);
    index += 1;
  }
  return buffer.toString();
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String _formatDouble(double? value) {
  if (value == null) return '-';
  return value.toStringAsFixed(3);
}

String _formatPercent(double? value) {
  if (value == null) return '-';
  return '${(value * 100).toStringAsFixed(1)}%';
}
