import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = Ll6MeasurementOptions.parse(
    args,
    environment: Platform.environment,
  );
  if (options == null) {
    stderr.writeln(Ll6MeasurementOptions.usage);
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  try {
    final summary = await runLl6PrefixStabilityMeasurement(
      options: options,
      sender: (body) => postOpenAiChatCompletion(
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
      case Ll6MeasurementOutputFormat.json:
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(summary.toJson()),
        );
        return;
      case Ll6MeasurementOutputFormat.markdown:
        stdout.write(summary.toMarkdown());
        return;
    }
  } finally {
    client.close(force: true);
  }
}

typedef Ll6ChatCompletionSender =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

enum Ll6MeasurementMode {
  defaultDynamic('default_dynamic'),
  prefixStable('prefix_stable');

  const Ll6MeasurementMode(this.id);

  final String id;
}

enum Ll6MeasurementOutputFormat { markdown, json }

class Ll6MeasurementOptions {
  const Ll6MeasurementOptions({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.toolCount,
    required this.maxTokens,
    required this.timeout,
    required this.outputPath,
    required this.format,
    this.idSlot,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final int toolCount;
  final int maxTokens;
  final Duration timeout;
  final String? outputPath;
  final Ll6MeasurementOutputFormat format;
  final int? idSlot;

  Uri get chatCompletionsEndpoint {
    final normalized = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized/chat/completions');
  }

  static const usage =
      'Usage: dart run tool/ll6_prefix_stability_measurement.dart '
      '[--base-url URL] [--model MODEL] [--api-key KEY] '
      '[--tool-count N] [--max-tokens N] [--id-slot N] '
      '[--timeout-seconds N] [--output PATH] [--format markdown|json]\n\n'
      'Defaults: CAVERNO_LLM_BASE_URL or http://localhost:1234/v1, '
      'CAVERNO_LLM_MODEL or local-model, CAVERNO_LLM_API_KEY or no-key.';

  static Ll6MeasurementOptions? parse(
    List<String> args, {
    Map<String, String> environment = const {},
  }) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') {
        return null;
      }
      if (!arg.startsWith('--')) {
        return null;
      }
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
      null || '' || 'markdown' => Ll6MeasurementOutputFormat.markdown,
      'json' => Ll6MeasurementOutputFormat.json,
      _ => null,
    };
    if (format == null) return null;

    final toolCount = _parsePositiveInt(values['tool-count'], fallback: 30);
    final maxTokens = _parsePositiveInt(values['max-tokens'], fallback: 16);
    final timeoutSeconds = _parsePositiveInt(
      values['timeout-seconds'],
      fallback: 120,
    );
    final idSlot = _parseOptionalInt(values['id-slot']);
    if (toolCount == null || maxTokens == null || timeoutSeconds == null) {
      return null;
    }

    return Ll6MeasurementOptions(
      baseUrl:
          values['base-url'] ??
          environment['CAVERNO_LLM_BASE_URL'] ??
          'http://localhost:1234/v1',
      model:
          values['model'] ?? environment['CAVERNO_LLM_MODEL'] ?? 'local-model',
      apiKey:
          values['api-key'] ?? environment['CAVERNO_LLM_API_KEY'] ?? 'no-key',
      toolCount: toolCount,
      maxTokens: maxTokens,
      timeout: Duration(seconds: timeoutSeconds),
      idSlot: idSlot,
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

  static int? _parseOptionalInt(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return int.tryParse(value.trim());
  }
}

class Ll6TimingSample {
  const Ll6TimingSample({
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

  bool get hasCacheTiming => cacheN != null && promptN != null;

  double? get cachePromptRatio {
    final cacheTokens = cacheN;
    final promptTokens = promptN;
    if (cacheTokens == null || promptTokens == null || promptTokens <= 0) {
      return null;
    }
    return cacheTokens / promptTokens;
  }

  double? get cachedPromptShare {
    final cacheTokens = cacheN;
    final promptTokens = promptN;
    if (cacheTokens == null || promptTokens == null) return null;
    final totalPromptTokens = cacheTokens + promptTokens;
    if (totalPromptTokens <= 0) return null;
    return cacheTokens / totalPromptTokens;
  }

  factory Ll6TimingSample.fromResponseJson(Map<String, dynamic> response) {
    final timings = _asStringMap(response['timings']);
    if (timings == null) return const Ll6TimingSample();
    return Ll6TimingSample(
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
      if (cachePromptRatio != null) 'cachePromptRatio': cachePromptRatio,
      if (cachedPromptShare != null) 'cachedPromptShare': cachedPromptShare,
    };
  }
}

class Ll6MeasurementRun {
  const Ll6MeasurementRun({
    required this.mode,
    required this.idSlot,
    required this.initialToolCount,
    required this.followUpToolCount,
    required this.initialTiming,
    required this.followUpTiming,
    required this.warnings,
  });

  final Ll6MeasurementMode mode;
  final int? idSlot;
  final int initialToolCount;
  final int followUpToolCount;
  final Ll6TimingSample initialTiming;
  final Ll6TimingSample followUpTiming;
  final List<String> warnings;

  Map<String, dynamic> toJson() {
    return {
      'mode': mode.id,
      if (idSlot != null) 'idSlot': idSlot,
      'initialToolCount': initialToolCount,
      'followUpToolCount': followUpToolCount,
      'initialTiming': initialTiming.toJson(),
      'followUpTiming': followUpTiming.toJson(),
      if (warnings.isNotEmpty) 'warnings': warnings,
    };
  }
}

class Ll6PrefixStabilityMeasurementSummary {
  const Ll6PrefixStabilityMeasurementSummary({
    required this.generatedAt,
    required this.baseUrl,
    required this.model,
    required this.toolCount,
    required this.defaultRun,
    required this.prefixStableRun,
  });

  final DateTime generatedAt;
  final String baseUrl;
  final String model;
  final int toolCount;
  final Ll6MeasurementRun defaultRun;
  final Ll6MeasurementRun prefixStableRun;

  double? get defaultFollowUpRatio =>
      defaultRun.followUpTiming.cachePromptRatio;

  double? get prefixStableFollowUpRatio =>
      prefixStableRun.followUpTiming.cachePromptRatio;

  double? get defaultFollowUpCachedShare =>
      defaultRun.followUpTiming.cachedPromptShare;

  double? get prefixStableFollowUpCachedShare =>
      prefixStableRun.followUpTiming.cachedPromptShare;

  double? get absoluteRatioImprovement {
    final baseline = defaultFollowUpRatio;
    final candidate = prefixStableFollowUpRatio;
    if (baseline == null || candidate == null) return null;
    return candidate - baseline;
  }

  double? get relativeRatioImprovement {
    final baseline = defaultFollowUpRatio;
    final absolute = absoluteRatioImprovement;
    if (baseline == null || absolute == null || baseline == 0) return null;
    return absolute / baseline;
  }

  bool? get improved {
    final absolute = absoluteRatioImprovement;
    if (absolute == null) return null;
    return absolute > 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaName': 'caverno_ll6_prefix_stability_measurement',
      'schemaVersion': 1,
      'generatedAt': generatedAt.toIso8601String(),
      'baseUrl': baseUrl,
      'model': model,
      'toolCount': toolCount,
      'defaultRun': defaultRun.toJson(),
      'prefixStableRun': prefixStableRun.toJson(),
      'comparison': {
        if (defaultFollowUpRatio != null)
          'defaultFollowUpCachePromptRatio': defaultFollowUpRatio,
        if (prefixStableFollowUpRatio != null)
          'prefixStableFollowUpCachePromptRatio': prefixStableFollowUpRatio,
        if (defaultFollowUpCachedShare != null)
          'defaultFollowUpCachedPromptShare': defaultFollowUpCachedShare,
        if (prefixStableFollowUpCachedShare != null)
          'prefixStableFollowUpCachedPromptShare':
              prefixStableFollowUpCachedShare,
        if (absoluteRatioImprovement != null)
          'absoluteRatioImprovement': absoluteRatioImprovement,
        if (relativeRatioImprovement != null)
          'relativeRatioImprovement': relativeRatioImprovement,
        if (improved != null) 'improved': improved,
      },
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL6 Prefix-Stable Measurement')
      ..writeln()
      ..writeln('- Generated: `${generatedAt.toIso8601String()}`')
      ..writeln('- Base URL: `$baseUrl`')
      ..writeln('- Model: `$model`')
      ..writeln('- Tool count: `$toolCount`')
      ..writeln()
      ..writeln(
        '| Mode | Initial tools | Follow-up tools | id_slot | Initial cache/prompt | Follow-up cache/prompt | Follow-up cached share | Follow-up prompt_ms |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final run in [defaultRun, prefixStableRun]) {
      buffer.writeln(
        '| `${run.mode.id}` | ${run.initialToolCount} | '
        '${run.followUpToolCount} | ${run.idSlot ?? '-'} | '
        '${_formatRatio(run.initialTiming.cachePromptRatio)} | '
        '${_formatRatio(run.followUpTiming.cachePromptRatio)} | '
        '${_formatPercent(run.followUpTiming.cachedPromptShare)} | '
        '${_formatDouble(run.followUpTiming.promptMs)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Comparison')
      ..writeln()
      ..writeln(
        '- Absolute follow-up cache ratio improvement: '
        '`${_formatRatio(absoluteRatioImprovement)}`',
      )
      ..writeln(
        '- Relative follow-up cache ratio improvement: '
        '`${_formatPercent(relativeRatioImprovement)}`',
      )
      ..writeln('- Improved: `${improved ?? 'unknown'}`');

    final warnings = [
      ...defaultRun.warnings.map((warning) => 'default_dynamic: $warning'),
      ...prefixStableRun.warnings.map((warning) => 'prefix_stable: $warning'),
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

Future<Ll6PrefixStabilityMeasurementSummary> runLl6PrefixStabilityMeasurement({
  required Ll6MeasurementOptions options,
  required Ll6ChatCompletionSender sender,
  DateTime? generatedAt,
}) async {
  final defaultRun = await _runMode(
    options: options,
    sender: sender,
    mode: Ll6MeasurementMode.defaultDynamic,
  );
  final prefixStableRun = await _runMode(
    options: options,
    sender: sender,
    mode: Ll6MeasurementMode.prefixStable,
  );
  return Ll6PrefixStabilityMeasurementSummary(
    generatedAt: generatedAt ?? DateTime.now(),
    baseUrl: options.baseUrl,
    model: options.model,
    toolCount: options.toolCount,
    defaultRun: defaultRun,
    prefixStableRun: prefixStableRun,
  );
}

Future<Ll6MeasurementRun> _runMode({
  required Ll6MeasurementOptions options,
  required Ll6ChatCompletionSender sender,
  required Ll6MeasurementMode mode,
}) async {
  final idSlot = _idSlotForMode(options.idSlot, mode);
  final initialBody = buildLl6MeasurementRequestBody(
    mode: mode,
    requestPhase: Ll6MeasurementRequestPhase.initial,
    model: options.model,
    toolCount: options.toolCount,
    maxTokens: options.maxTokens,
    idSlot: idSlot,
  );
  final followUpBody = buildLl6MeasurementRequestBody(
    mode: mode,
    requestPhase: Ll6MeasurementRequestPhase.followUp,
    model: options.model,
    toolCount: options.toolCount,
    maxTokens: options.maxTokens,
    idSlot: idSlot,
  );

  final initialResponse = await sender(initialBody);
  final followUpResponse = await sender(followUpBody);
  final initialTiming = Ll6TimingSample.fromResponseJson(initialResponse);
  final followUpTiming = Ll6TimingSample.fromResponseJson(followUpResponse);
  return Ll6MeasurementRun(
    mode: mode,
    idSlot: idSlot,
    initialToolCount: _asList(initialBody['tools']).length,
    followUpToolCount: _asList(followUpBody['tools']).length,
    initialTiming: initialTiming,
    followUpTiming: followUpTiming,
    warnings: [
      if (!initialTiming.hasCacheTiming)
        'Initial response did not include timings.cache_n and timings.prompt_n.',
      if (!followUpTiming.hasCacheTiming)
        'Follow-up response did not include timings.cache_n and timings.prompt_n.',
    ],
  );
}

enum Ll6MeasurementRequestPhase { initial, followUp }

Map<String, dynamic> buildLl6MeasurementRequestBody({
  required Ll6MeasurementMode mode,
  required Ll6MeasurementRequestPhase requestPhase,
  required String model,
  required int toolCount,
  required int maxTokens,
  int? idSlot,
}) {
  final tools = buildLl6MeasurementTools(
    mode: mode,
    requestPhase: requestPhase,
    toolCount: toolCount,
  );
  return {
    'model': model,
    'messages': buildLl6MeasurementMessages(requestPhase, toolCount: toolCount),
    'temperature': 0.0,
    'max_tokens': maxTokens,
    'stream': false,
    'cache_prompt': true,
    'id_slot': ?idSlot,
    'tools': tools,
  };
}

List<Map<String, dynamic>> buildLl6MeasurementMessages(
  Ll6MeasurementRequestPhase phase, {
  required int toolCount,
}) {
  final messages = <Map<String, dynamic>>[
    {
      'role': 'system',
      'content':
          'You are the Caverno LL6 cache measurement assistant. Keep responses short and deterministic.',
    },
    {
      'role': 'user',
      'content':
          'Use the available tool context to inspect alpha.txt, then answer with a short summary.',
    },
  ];
  if (phase == Ll6MeasurementRequestPhase.initial) {
    return messages;
  }
  return [
    ...messages,
    {
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': 'call_ll6_measure_alpha',
          'type': 'function',
          'function': {
            'name': _targetToolName(toolCount),
            'arguments': '{"path":"alpha.txt"}',
          },
        },
      ],
    },
    {
      'role': 'tool',
      'tool_call_id': 'call_ll6_measure_alpha',
      'content': 'alpha.txt contains stable LL6 measurement fixture text.',
    },
  ];
}

List<Map<String, dynamic>> buildLl6MeasurementTools({
  required Ll6MeasurementMode mode,
  required Ll6MeasurementRequestPhase requestPhase,
  required int toolCount,
}) {
  final fullTools = buildLl6FullToolList(toolCount: toolCount);
  if (mode == Ll6MeasurementMode.prefixStable) {
    return fullTools;
  }
  return switch (requestPhase) {
    Ll6MeasurementRequestPhase.initial => [buildLl6ToolSearchDefinition()],
    Ll6MeasurementRequestPhase.followUp => [
      buildLl6SyntheticToolDefinition(_targetToolName(toolCount)),
    ],
  };
}

List<Map<String, dynamic>> buildLl6FullToolList({required int toolCount}) {
  return [
    buildLl6ToolSearchDefinition(),
    for (var index = 0; index < toolCount; index += 1)
      buildLl6SyntheticToolDefinition(_syntheticToolName(index)),
  ];
}

Map<String, dynamic> buildLl6ToolSearchDefinition() {
  return {
    'type': 'function',
    'function': {
      'name': 'tool_search',
      'description': 'Search the available tool catalog by name or purpose.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
    },
  };
}

Map<String, dynamic> buildLl6SyntheticToolDefinition(String name) {
  return {
    'type': 'function',
    'function': {
      'name': name,
      'description':
          'Read a deterministic LL6 measurement fixture and return concise text.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      },
    },
  };
}

Future<Map<String, dynamic>> postOpenAiChatCompletion({
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
    throw Ll6MeasurementHttpException(
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

class Ll6MeasurementHttpException implements Exception {
  const Ll6MeasurementHttpException({
    required this.statusCode,
    required this.responseBody,
  });

  final int statusCode;
  final String responseBody;

  @override
  String toString() {
    return 'LL6 measurement HTTP $statusCode: $responseBody';
  }
}

int? _idSlotForMode(int? baseIdSlot, Ll6MeasurementMode mode) {
  if (baseIdSlot == null) return null;
  return switch (mode) {
    Ll6MeasurementMode.defaultDynamic => baseIdSlot,
    Ll6MeasurementMode.prefixStable => baseIdSlot + 1,
  };
}

String _syntheticToolName(int index) {
  return 'll6_measure_tool_$index';
}

String _targetToolName(int toolCount) {
  return _syntheticToolName(toolCount - 1);
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

String _formatRatio(double? value) {
  if (value == null) return '-';
  return value.toStringAsFixed(3);
}

String _formatPercent(double? value) {
  if (value == null) return '-';
  return '${(value * 100).toStringAsFixed(1)}%';
}

String _formatDouble(double? value) {
  if (value == null) return '-';
  return value.toStringAsFixed(1);
}
