import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _schemaName = 'caverno_chat_search_grounding_eval';
const _schemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = SearchGroundingEvalOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/chat_search_grounding_eval.dart '
      '--base-url URL --api-key KEY --model MODEL [--model MODEL ...] '
      '--out-dir PATH [--temperature VALUE] [--max-tokens VALUE] '
      '[--timeout-seconds VALUE]',
    );
    exitCode = 64;
    return;
  }

  final report = await runSearchGroundingEval(options);
  final outDir = Directory(options.outDir);
  await outDir.create(recursive: true);
  final jsonFile = File('${outDir.path}/chat_search_grounding_eval.json');
  await jsonFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdownFile = File('${outDir.path}/chat_search_grounding_eval.md');
  await markdownFile.writeAsString(report.toMarkdown());

  stdout.writeln('Chat search grounding eval written to ${jsonFile.path}');
  stdout.writeln(report.toMarkdown());

  if (!report.passed) {
    exitCode = 1;
  }
}

Future<SearchGroundingEvalReport> runSearchGroundingEval(
  SearchGroundingEvalOptions options, {
  DateTime? generatedAt,
}) async {
  final client = OpenAiCompatibleChatClient(
    baseUrl: options.baseUrl,
    apiKey: options.apiKey,
    timeout: Duration(seconds: options.timeoutSeconds),
  );
  final caseDefinition = SearchGroundingCaseDefinition.projectHailMaryCatShirt;
  final modelResults = <SearchGroundingModelResult>[];

  for (final model in options.models) {
    final cases = <SearchGroundingCaseResult>[];
    try {
      cases.add(
        await runSearchGroundingCase(
          client: client,
          model: model,
          caseDefinition: caseDefinition,
          temperature: options.temperature,
          maxTokens: options.maxTokens,
        ),
      );
    } catch (error, stackTrace) {
      cases.add(
        SearchGroundingCaseResult.error(
          model: model,
          caseId: caseDefinition.id,
          title: caseDefinition.title,
          error: '$error',
          stackTrace: '$stackTrace',
        ),
      );
    }
    modelResults.add(SearchGroundingModelResult(model: model, cases: cases));
  }

  return SearchGroundingEvalReport(
    schemaName: _schemaName,
    schemaVersion: _schemaVersion,
    generatedAt: generatedAt ?? DateTime.now(),
    baseUrl: options.baseUrl,
    temperature: options.temperature,
    maxTokens: options.maxTokens,
    models: modelResults,
  );
}

Future<SearchGroundingCaseResult> runSearchGroundingCase({
  required OpenAiCompatibleChatClient client,
  required String model,
  required SearchGroundingCaseDefinition caseDefinition,
  required double temperature,
  required int maxTokens,
}) async {
  final messages = [
    ChatMessagePayload.system(caseDefinition.systemPrompt),
    ChatMessagePayload.user(caseDefinition.prompt),
  ];
  final initial = await client.createChatCompletion(
    model: model,
    messages: messages,
    tools: [searchWebToolDefinition],
    temperature: temperature,
    maxTokens: maxTokens,
  );

  final searchCalls = initial.toolCalls
      .where((call) => call.name == 'search_web')
      .toList(growable: false);
  if (searchCalls.isEmpty) {
    return scoreSearchGroundingResult(
      model: model,
      caseDefinition: caseDefinition,
      initialResponse: initial,
      finalResponse: initial,
      toolResults: const [],
    );
  }

  final toolResults = [
    for (final call in searchCalls)
      ToolResultPayload(
        call: call,
        result: buildMockSearchResult(call.arguments),
      ),
  ];
  final finalMessages = [
    ...messages,
    ChatMessagePayload.user(
      buildToolResultGroundingPrompt(
        userPrompt: caseDefinition.prompt,
        toolResults: toolResults,
      ),
    ),
  ];
  final finalResponse = await client.createChatCompletion(
    model: model,
    messages: finalMessages,
    temperature: temperature,
    maxTokens: maxTokens,
  );

  return scoreSearchGroundingResult(
    model: model,
    caseDefinition: caseDefinition,
    initialResponse: initial,
    finalResponse: finalResponse,
    toolResults: toolResults,
  );
}

SearchGroundingCaseResult scoreSearchGroundingResult({
  required String model,
  required SearchGroundingCaseDefinition caseDefinition,
  required ChatCompletionResponse initialResponse,
  required ChatCompletionResponse finalResponse,
  required List<ToolResultPayload> toolResults,
}) {
  final firstSearchCall = initialResponse.toolCalls
      .where((call) => call.name == 'search_web')
      .firstOrNull;
  final query = firstSearchCall?.arguments['query']?.toString() ?? '';
  final answer = finalResponse.content;
  final queryAndAnswer = '$query\n$answer';
  final answerLower = answer.toLowerCase();
  final answerCompact = _compactForMatch(answerLower);
  final queryAndAnswerLower = queryAndAnswer.toLowerCase();

  final signals = <String, bool>{
    'search_tool_called': firstSearchCall != null,
    'finish_reason_not_length': finalResponse.finishReason != 'length',
    'mentions_ryland_grace_actor':
        _containsAny(answerLower, const ['ryan gosling', 'ryland grace']) ||
        (_containsAny(answer, const ['ライアン', 'ゴズリング']) &&
            _containsAny(answer, const ['ライランド', 'グレース博士'])),
    'mentions_b_kliban':
        _containsAny(answerLower, const ['kliban']) ||
        _containsAny(answer, const ['クリバン']),
    'mentions_bridge_location':
        (_containsAny(answerLower, const ['golden gate']) ||
            _containsAny(answerCompact, const ['goldengate', 'ゴールデンゲート'])) &&
        (_containsAny(answerLower, const ['san francisco']) ||
            _containsAny(answerCompact, const ['sanfrancisco']) ||
            _containsAny(answer, const ['サンフランシスコ'])),
    'mentions_costume_designer':
        _containsAny(answerLower, const [
          'david crossman',
          'dave crossman',
          'glyn dillon',
        ]) ||
        _containsAny(answer, const ['デヴィッド', 'デイヴ', 'クロスマン', 'グリン', 'ディロン']),
    'avoids_wrong_astrid_entity':
        !_containsAny(queryAndAnswerLower, const ['astrid', 'fernandez']) &&
        !_containsAny(queryAndAnswer, const ['アストリッド', 'フェルナンデス']),
    'does_not_claim_unverified_or_missing': !_containsAny(answer, const [
      '確認できません',
      '見つかりません',
      '情報はありません',
    ]),
  };

  final failedSignals = signals.entries
      .where((entry) => !entry.value)
      .map((entry) => entry.key)
      .toList(growable: false);
  final score = signals.isEmpty
      ? 0.0
      : (signals.length - failedSignals.length) / signals.length;
  return SearchGroundingCaseResult(
    model: model,
    caseId: caseDefinition.id,
    title: caseDefinition.title,
    passed: failedSignals.isEmpty,
    score: score,
    signals: Map.unmodifiable(signals),
    failedSignals: failedSignals,
    initialFinishReason: initialResponse.finishReason,
    finalFinishReason: finalResponse.finishReason,
    initialUsage: initialResponse.usage,
    finalUsage: finalResponse.usage,
    toolCalls: initialResponse.toolCalls,
    toolResults: toolResults,
    finalAnswerPreview: _preview(answer, 1200),
    error: null,
    stackTrace: null,
  );
}

bool _containsAny(String source, List<String> needles) {
  return needles.any(source.contains);
}

String _compactForMatch(String source) {
  return source.replaceAll(RegExp(r'[\s・_\-]'), '');
}

String buildToolResultGroundingPrompt({
  required String userPrompt,
  required List<ToolResultPayload> toolResults,
}) {
  final buffer = StringBuffer()
    ..writeln(
      'Answer the original user question using only these tool results.',
    )
    ..writeln('Original user question:')
    ..writeln(userPrompt)
    ..writeln()
    ..writeln('Rules:')
    ..writeln('- Preserve entity roles exactly as supported by the results.')
    ..writeln('- Do not introduce people or facts that are not in the results.')
    ..writeln('- Answer in Japanese.')
    ..writeln('- Keep the answer under 900 Japanese characters.')
    ..writeln()
    ..writeln('Tool results:');
  for (final result in toolResults) {
    buffer
      ..writeln('Tool: ${result.call.name}')
      ..writeln('Arguments: ${jsonEncode(result.call.arguments)}')
      ..writeln('Result: ${result.result}')
      ..writeln();
  }
  return buffer.toString();
}

String buildMockSearchResult(Map<String, dynamic> arguments) {
  final query = arguments['query']?.toString() ?? '';
  return jsonEncode({
    'query': query,
    'total_results': 4,
    'results': [
      {
        'title':
            'Project Hail Mary costume designers explain Ryland Grace shirts',
        'url':
            'https://example.test/project-hail-mary-costume-design-ryland-grace-shirts',
        'content':
            'Costume designers Glyn Dillon and David Crossman describe the graphic T-shirts worn by Ryan Gosling as Ryland Grace in Project Hail Mary. One favorite was the B. Kliban bridge cat shirt.',
      },
      {
        'title': 'San Francisco Cat Golden Gate shirt seen on Ryland Grace',
        'url':
            'https://example.test/san-francisco-cat-golden-gate-shirt-project-hail-mary',
        'content':
            'A white graphic T-shirt worn by Ryan Gosling as Ryland Grace features a striped B. Kliban-style cat on the Golden Gate Bridge above the words San Francisco.',
      },
      {
        'title': 'Dr Grace San Francisco Cat Shirt product listing',
        'url': 'https://example.test/dr-grace-san-francisco-cat-shirt',
        'content':
            'Fan listings describe the shirt as Dr Grace San Francisco Cat Shirt, inspired by Project Hail Mary, with the Golden Gate Bridge cat artwork.',
      },
      {
        'title': 'Cats musical shirt was a separate Ryland Grace graphic tee',
        'url': 'https://example.test/ryland-grace-cats-musical-shirt',
        'content':
            'A separate Cats musical T-shirt also appears among Ryland Grace graphic tees, but the San Francisco bridge cat shirt is the B. Kliban-style cat design.',
      },
    ],
  });
}

const searchWebToolDefinition = {
  'type': 'function',
  'function': {
    'name': 'search_web',
    'description':
        'Search the web for current factual evidence. Use this before answering questions about recent media details, products, or public claims.',
    'parameters': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'query': {'type': 'string', 'description': 'Search query string.'},
        'max_results': {
          'type': 'integer',
          'description': 'Maximum number of results to return.',
        },
        'language': {
          'type': ['string', 'null'],
          'description': 'Optional language code.',
        },
      },
      'required': ['query'],
    },
  },
};

final class SearchGroundingEvalOptions {
  const SearchGroundingEvalOptions({
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    required this.outDir,
    required this.temperature,
    required this.maxTokens,
    required this.timeoutSeconds,
  });

  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final String outDir;
  final double temperature;
  final int maxTokens;
  final int timeoutSeconds;

  static SearchGroundingEvalOptions? parse(List<String> args) {
    String? baseUrl;
    String? apiKey;
    String? outDir;
    var temperature = 0.2;
    var maxTokens = 8192;
    var timeoutSeconds = 180;
    final models = <String>[];

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--base-url':
          baseUrl = _nextValue(args, ++index);
        case '--api-key':
          apiKey = _nextValue(args, ++index);
        case '--model':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          models.add(value);
        case '--out-dir':
          outDir = _nextValue(args, ++index);
        case '--temperature':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = double.tryParse(value);
          if (parsed == null) return null;
          temperature = parsed;
        case '--max-tokens':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = int.tryParse(value);
          if (parsed == null || parsed <= 0) return null;
          maxTokens = parsed;
        case '--timeout-seconds':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = int.tryParse(value);
          if (parsed == null || parsed <= 0) return null;
          timeoutSeconds = parsed;
        default:
          return null;
      }
    }

    if (baseUrl == null || apiKey == null || outDir == null || models.isEmpty) {
      return null;
    }

    return SearchGroundingEvalOptions(
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: List.unmodifiable(models),
      outDir: outDir,
      temperature: temperature,
      maxTokens: maxTokens,
      timeoutSeconds: timeoutSeconds,
    );
  }

  static String? _nextValue(List<String> args, int index) {
    if (index >= args.length) {
      return null;
    }
    final value = args[index];
    return value.startsWith('--') ? null : value;
  }
}

final class SearchGroundingCaseDefinition {
  const SearchGroundingCaseDefinition({
    required this.id,
    required this.title,
    required this.prompt,
    required this.systemPrompt,
  });

  final String id;
  final String title;
  final String prompt;
  final String systemPrompt;

  static const projectHailMaryCatShirt = SearchGroundingCaseDefinition(
    id: 'project_hail_mary_cat_shirt',
    title: 'Project Hail Mary cat shirt grounding',
    prompt: 'プロジェクトヘイルメアリーでグレースが着てた猫のtシャツの詳細を知りたい',
    systemPrompt:
        'You are evaluating factual web-search grounding. Use search_web before answering. Do not use browser tools. Preserve the role of Ryland Grace exactly if search results mention him. Answer the user in Japanese after the tool result is provided.',
  );
}

final class SearchGroundingEvalReport {
  const SearchGroundingEvalReport({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.baseUrl,
    required this.temperature,
    required this.maxTokens,
    required this.models,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String baseUrl;
  final double temperature;
  final int maxTokens;
  final List<SearchGroundingModelResult> models;

  bool get passed => models.every((model) => model.passed);

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'result': passed ? 'passed' : 'failed',
      'baseUrl': baseUrl,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'models': models.map((model) => model.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Chat Search Grounding Eval')
      ..writeln()
      ..writeln('- Result: `${passed ? 'passed' : 'failed'}`')
      ..writeln('- Base URL: `$baseUrl`')
      ..writeln('- Temperature: `$temperature`')
      ..writeln('- Max tokens: `$maxTokens`')
      ..writeln()
      ..writeln(
        '| Model | Case | Result | Score | First query | Failed signals | Finish |',
      )
      ..writeln(
        '|-------|------|--------|-------|-------------|----------------|--------|',
      );
    for (final model in models) {
      for (final evalCase in model.cases) {
        buffer.writeln(
          '| ${_tableCell(model.model)} '
          '| ${_tableCell(evalCase.title)} '
          '| `${evalCase.passed ? 'passed' : 'failed'}` '
          '| `${(evalCase.score * 100).round()}%` '
          '| ${_tableCell(evalCase.firstSearchQuery ?? '')} '
          '| ${_tableCell(evalCase.failedSignals.join(', '))} '
          '| `${evalCase.initialFinishReason}/${evalCase.finalFinishReason}` |',
        );
      }
    }
    buffer.writeln();
    for (final model in models) {
      for (final evalCase in model.cases) {
        buffer
          ..writeln('## ${model.model} - ${evalCase.title}')
          ..writeln()
          ..writeln('- Result: `${evalCase.passed ? 'passed' : 'failed'}`')
          ..writeln('- Score: `${(evalCase.score * 100).round()}%`')
          ..writeln(
            '- Tool calls: `${evalCase.toolCalls.map((call) => call.name).join(', ')}`',
          )
          ..writeln('- Failed signals: `${evalCase.failedSignals.join(', ')}`')
          ..writeln()
          ..writeln('Final answer preview:')
          ..writeln()
          ..writeln('```text')
          ..writeln(evalCase.finalAnswerPreview)
          ..writeln('```')
          ..writeln();
        if (evalCase.error != null) {
          buffer
            ..writeln('Error:')
            ..writeln()
            ..writeln('```text')
            ..writeln(evalCase.error)
            ..writeln('```')
            ..writeln();
        }
      }
    }
    return buffer.toString();
  }
}

final class SearchGroundingModelResult {
  const SearchGroundingModelResult({required this.model, required this.cases});

  final String model;
  final List<SearchGroundingCaseResult> cases;

  bool get passed => cases.every((evalCase) => evalCase.passed);

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'result': passed ? 'passed' : 'failed',
      'cases': cases
          .map((evalCase) => evalCase.toJson())
          .toList(growable: false),
    };
  }
}

final class SearchGroundingCaseResult {
  const SearchGroundingCaseResult({
    required this.model,
    required this.caseId,
    required this.title,
    required this.passed,
    required this.score,
    required this.signals,
    required this.failedSignals,
    required this.initialFinishReason,
    required this.finalFinishReason,
    required this.initialUsage,
    required this.finalUsage,
    required this.toolCalls,
    required this.toolResults,
    required this.finalAnswerPreview,
    required this.error,
    required this.stackTrace,
  });

  factory SearchGroundingCaseResult.error({
    required String model,
    required String caseId,
    required String title,
    required String error,
    required String stackTrace,
  }) {
    return SearchGroundingCaseResult(
      model: model,
      caseId: caseId,
      title: title,
      passed: false,
      score: 0,
      signals: const {},
      failedSignals: const ['runtime_error'],
      initialFinishReason: 'error',
      finalFinishReason: 'error',
      initialUsage: TokenUsage.empty,
      finalUsage: TokenUsage.empty,
      toolCalls: const [],
      toolResults: const [],
      finalAnswerPreview: '',
      error: error,
      stackTrace: stackTrace,
    );
  }

  final String model;
  final String caseId;
  final String title;
  final bool passed;
  final double score;
  final Map<String, bool> signals;
  final List<String> failedSignals;
  final String initialFinishReason;
  final String finalFinishReason;
  final TokenUsage initialUsage;
  final TokenUsage finalUsage;
  final List<ChatToolCall> toolCalls;
  final List<ToolResultPayload> toolResults;
  final String finalAnswerPreview;
  final String? error;
  final String? stackTrace;

  String? get firstSearchQuery {
    for (final call in toolCalls) {
      if (call.name == 'search_web') {
        return call.arguments['query']?.toString();
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'caseId': caseId,
      'title': title,
      'result': passed ? 'passed' : 'failed',
      'score': score,
      'signals': signals,
      'failedSignals': failedSignals,
      'initialFinishReason': initialFinishReason,
      'finalFinishReason': finalFinishReason,
      'initialUsage': initialUsage.toJson(),
      'finalUsage': finalUsage.toJson(),
      'toolCalls': toolCalls
          .map((call) => call.toJson())
          .toList(growable: false),
      'toolResults': toolResults
          .map((result) => result.toJson())
          .toList(growable: false),
      'finalAnswerPreview': finalAnswerPreview,
      if (error != null) 'error': error,
      if (stackTrace != null) 'stackTrace': stackTrace,
    };
  }
}

final class ToolResultPayload {
  const ToolResultPayload({required this.call, required this.result});

  final ChatToolCall call;
  final String result;

  Map<String, dynamic> toJson() {
    return {'call': call.toJson(), 'result': result};
  }
}

final class ChatMessagePayload {
  const ChatMessagePayload({required this.role, required this.content});

  factory ChatMessagePayload.system(String content) {
    return ChatMessagePayload(role: 'system', content: content);
  }

  factory ChatMessagePayload.user(String content) {
    return ChatMessagePayload(role: 'user', content: content);
  }

  final String role;
  final String content;

  Map<String, dynamic> toJson() {
    return {'role': role, 'content': content};
  }
}

final class ChatCompletionResponse {
  const ChatCompletionResponse({
    required this.content,
    required this.finishReason,
    required this.toolCalls,
    required this.usage,
  });

  final String content;
  final String finishReason;
  final List<ChatToolCall> toolCalls;
  final TokenUsage usage;
}

final class ChatToolCall {
  const ChatToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    required this.rawArguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String rawArguments;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'arguments': arguments,
      'rawArguments': rawArguments,
    };
  }
}

final class TokenUsage {
  const TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  static const empty = TokenUsage(
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
  );

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  Map<String, dynamic> toJson() {
    return {
      'promptTokens': promptTokens,
      'completionTokens': completionTokens,
      'totalTokens': totalTokens,
    };
  }
}

final class OpenAiCompatibleChatClient {
  OpenAiCompatibleChatClient({
    required this.baseUrl,
    required this.apiKey,
    required this.timeout,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final Duration timeout;
  final http.Client _httpClient;

  Future<ChatCompletionResponse> createChatCompletion({
    required String model,
    required List<ChatMessagePayload> messages,
    List<Map<String, dynamic>> tools = const [],
    required double temperature,
    required int maxTokens,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages
          .map((message) => message.toJson())
          .toList(growable: false),
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (tools.isNotEmpty) 'tools': tools,
    };
    final response = await _httpClient
        .post(
          _chatCompletionsUri(baseUrl),
          headers: {
            'content-type': 'application/json',
            if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Chat completion failed with HTTP ${response.statusCode}: '
        '${_preview(response.body, 1000)}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Chat completion response is not an object.');
    }
    return _parseChatCompletionResponse(decoded);
  }
}

Uri _chatCompletionsUri(String baseUrl) {
  final normalized = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  return Uri.parse(normalized).resolve('chat/completions');
}

ChatCompletionResponse _parseChatCompletionResponse(
  Map<String, dynamic> decoded,
) {
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    throw const FormatException('Chat completion response has no choices.');
  }
  final choice = Map<String, dynamic>.from(choices.first as Map);
  final rawMessage = choice['message'];
  if (rawMessage is! Map) {
    throw const FormatException('Chat completion choice has no message.');
  }
  final message = Map<String, dynamic>.from(rawMessage);
  final content = message['content']?.toString() ?? '';
  final finishReason = choice['finish_reason']?.toString() ?? 'unknown';
  final toolCalls = _parseToolCalls(message['tool_calls']);
  final usage = _parseUsage(decoded['usage']);
  return ChatCompletionResponse(
    content: content,
    finishReason: finishReason,
    toolCalls: toolCalls,
    usage: usage,
  );
}

List<ChatToolCall> _parseToolCalls(Object? rawToolCalls) {
  if (rawToolCalls is! List) {
    return const [];
  }
  return rawToolCalls
      .whereType<Map>()
      .map((rawCall) {
        final call = Map<String, dynamic>.from(rawCall);
        final rawFunction = call['function'];
        final function = rawFunction is Map
            ? Map<String, dynamic>.from(rawFunction)
            : const <String, dynamic>{};
        final rawArguments = function['arguments']?.toString() ?? '{}';
        return ChatToolCall(
          id: call['id']?.toString() ?? '',
          name: function['name']?.toString() ?? '',
          arguments: _decodeArguments(rawArguments),
          rawArguments: rawArguments,
        );
      })
      .toList(growable: false);
}

Map<String, dynamic> _decodeArguments(String rawArguments) {
  try {
    final decoded = jsonDecode(rawArguments);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } on FormatException {
    return {'_raw': rawArguments};
  }
  return {'_raw': rawArguments};
}

TokenUsage _parseUsage(Object? rawUsage) {
  if (rawUsage is! Map) {
    return TokenUsage.empty;
  }
  final usage = Map<String, dynamic>.from(rawUsage);
  return TokenUsage(
    promptTokens: _asInt(usage['prompt_tokens']),
    completionTokens: _asInt(usage['completion_tokens']),
    totalTokens: _asInt(usage['total_tokens']),
  );
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', '<br>').trim();
}

String _preview(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...';
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
