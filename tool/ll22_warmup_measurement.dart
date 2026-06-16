import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// LL22 idle warm-up measurement.
///
/// Quantifies the acceptance criterion "the first interactive turn after a
/// warm-up window reaches first token measurably faster than a cold start" by
/// comparing two first-turn requests against an OpenAI-compatible llama.cpp / LM
/// Studio endpoint:
///
/// - **cold**: a single first-turn request whose prompt has never been seen.
/// - **warm**: a minimal warm-up request (the LL22 KV warm) followed by the same
///   first-turn request, so the server slot already holds the prefix KV.
///
/// Each run carries a unique nonce at the head of the system prompt so "cold" is
/// genuinely cold regardless of prior slot state, and so the head changes the
/// way the real temporal context does between an overnight warm-up and the
/// morning turn. The warm path keeps the nonce identical between warm-up and the
/// measured request (the ideal LL22 case); in production the temporal head
/// differs and llama.cpp `--cache-reuse` recovers the stable bulk, so real-world
/// benefit is at most this measured upper bound.
Future<void> main(List<String> args) async {
  final options = Ll22MeasurementOptions.parse(
    args,
    environment: Platform.environment,
  );
  if (options == null) {
    stderr.writeln(Ll22MeasurementOptions.usage);
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  try {
    final summary = await runLl22WarmupMeasurement(
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
      case Ll22MeasurementOutputFormat.json:
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(summary.toJson()),
        );
        return;
      case Ll22MeasurementOutputFormat.markdown:
        stdout.write(summary.toMarkdown());
        return;
    }
  } finally {
    client.close(force: true);
  }
}

typedef Ll22ChatCompletionSender =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

enum Ll22MeasurementOutputFormat { markdown, json }

class Ll22MeasurementOptions {
  const Ll22MeasurementOptions({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.toolCount,
    required this.promptChars,
    required this.maxTokens,
    required this.warmupMaxTokens,
    required this.timeout,
    required this.outputPath,
    required this.format,
    this.idSlot,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final int toolCount;
  final int promptChars;
  final int maxTokens;
  final int warmupMaxTokens;
  final Duration timeout;
  final String? outputPath;
  final Ll22MeasurementOutputFormat format;
  final int? idSlot;

  Uri get chatCompletionsEndpoint {
    final normalized = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized/chat/completions');
  }

  static const usage =
      'Usage: dart run tool/ll22_warmup_measurement.dart '
      '[--base-url URL] [--model MODEL] [--api-key KEY] '
      '[--tool-count N] [--prompt-chars N] [--max-tokens N] '
      '[--warmup-max-tokens N] [--id-slot N] [--timeout-seconds N] '
      '[--output PATH] [--format markdown|json]\n\n'
      'Defaults: CAVERNO_LLM_BASE_URL or http://localhost:1234/v1, '
      'CAVERNO_LLM_MODEL or local-model, CAVERNO_LLM_API_KEY or no-key. '
      '--id-slot is recommended for reliable cold/warm isolation.';

  static Ll22MeasurementOptions? parse(
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
      null || '' || 'markdown' => Ll22MeasurementOutputFormat.markdown,
      'json' => Ll22MeasurementOutputFormat.json,
      _ => null,
    };
    if (format == null) return null;

    final toolCount = _parsePositiveInt(values['tool-count'], fallback: 24);
    final promptChars = _parsePositiveInt(
      values['prompt-chars'],
      fallback: 6000,
    );
    final maxTokens = _parsePositiveInt(values['max-tokens'], fallback: 16);
    final warmupMaxTokens = _parsePositiveInt(
      values['warmup-max-tokens'],
      fallback: 1,
    );
    final timeoutSeconds = _parsePositiveInt(
      values['timeout-seconds'],
      fallback: 120,
    );
    final idSlot = _parseOptionalInt(values['id-slot']);
    if (toolCount == null ||
        promptChars == null ||
        maxTokens == null ||
        warmupMaxTokens == null ||
        timeoutSeconds == null) {
      return null;
    }

    return Ll22MeasurementOptions(
      baseUrl:
          values['base-url'] ??
          environment['CAVERNO_LLM_BASE_URL'] ??
          'http://localhost:1234/v1',
      model:
          values['model'] ?? environment['CAVERNO_LLM_MODEL'] ?? 'local-model',
      apiKey:
          values['api-key'] ?? environment['CAVERNO_LLM_API_KEY'] ?? 'no-key',
      toolCount: toolCount,
      promptChars: promptChars,
      maxTokens: maxTokens,
      warmupMaxTokens: warmupMaxTokens,
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

class Ll22TimingSample {
  const Ll22TimingSample({
    this.cacheN,
    this.promptN,
    this.promptMs,
    this.predictedMs,
    this.promptPerSecond,
  });

  final int? cacheN;
  final int? promptN;
  final double? promptMs;
  final double? predictedMs;
  final double? promptPerSecond;

  bool get hasCacheTiming => cacheN != null && promptN != null;

  /// Share of the prompt served from cache: cache_n / (cache_n + prompt_n).
  double? get cachedPromptShare {
    final cacheTokens = cacheN;
    final promptTokens = promptN;
    if (cacheTokens == null || promptTokens == null) return null;
    final total = cacheTokens + promptTokens;
    if (total <= 0) return null;
    return cacheTokens / total;
  }

  factory Ll22TimingSample.fromResponseJson(Map<String, dynamic> response) {
    final timings = _asStringMap(response['timings']);
    if (timings == null) return const Ll22TimingSample();
    return Ll22TimingSample(
      cacheN: _asInt(timings['cache_n']),
      promptN: _asInt(timings['prompt_n']),
      promptMs: _asDouble(timings['prompt_ms']),
      predictedMs: _asDouble(timings['predicted_ms']),
      promptPerSecond: _asDouble(timings['prompt_per_second']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (cacheN != null) 'cacheN': cacheN,
      if (promptN != null) 'promptN': promptN,
      if (promptMs != null) 'promptMs': promptMs,
      if (predictedMs != null) 'predictedMs': predictedMs,
      if (promptPerSecond != null) 'promptPerSecond': promptPerSecond,
      if (cachedPromptShare != null) 'cachedPromptShare': cachedPromptShare,
    };
  }
}

class Ll22MeasurementRun {
  const Ll22MeasurementRun({
    required this.label,
    required this.idSlot,
    required this.toolCount,
    required this.warmedFirst,
    required this.timing,
    required this.warnings,
  });

  final String label;
  final int? idSlot;
  final int toolCount;
  final bool warmedFirst;
  final Ll22TimingSample timing;
  final List<String> warnings;

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      if (idSlot != null) 'idSlot': idSlot,
      'toolCount': toolCount,
      'warmedFirst': warmedFirst,
      'timing': timing.toJson(),
      if (warnings.isNotEmpty) 'warnings': warnings,
    };
  }
}

class Ll22WarmupMeasurementSummary {
  const Ll22WarmupMeasurementSummary({
    required this.generatedAt,
    required this.baseUrl,
    required this.model,
    required this.toolCount,
    required this.promptChars,
    required this.coldRun,
    required this.warmRun,
  });

  final DateTime generatedAt;
  final String baseUrl;
  final String model;
  final int toolCount;
  final int promptChars;
  final Ll22MeasurementRun coldRun;
  final Ll22MeasurementRun warmRun;

  double? get coldPromptMs => coldRun.timing.promptMs;
  double? get warmPromptMs => warmRun.timing.promptMs;

  double? get promptMsReductionAbs {
    final cold = coldPromptMs;
    final warm = warmPromptMs;
    if (cold == null || warm == null) return null;
    return cold - warm;
  }

  double? get promptMsReductionPct {
    final cold = coldPromptMs;
    final reduction = promptMsReductionAbs;
    if (cold == null || reduction == null || cold <= 0) return null;
    return reduction / cold;
  }

  double? get coldCachedShare => coldRun.timing.cachedPromptShare;
  double? get warmCachedShare => warmRun.timing.cachedPromptShare;

  bool? get improved {
    final reduction = promptMsReductionAbs;
    if (reduction == null) return null;
    return reduction > 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaName': 'caverno_ll22_warmup_measurement',
      'schemaVersion': 1,
      'generatedAt': generatedAt.toIso8601String(),
      'baseUrl': baseUrl,
      'model': model,
      'toolCount': toolCount,
      'promptChars': promptChars,
      'coldRun': coldRun.toJson(),
      'warmRun': warmRun.toJson(),
      'comparison': {
        if (coldPromptMs != null) 'coldPromptMs': coldPromptMs,
        if (warmPromptMs != null) 'warmPromptMs': warmPromptMs,
        if (promptMsReductionAbs != null)
          'promptMsReductionAbs': promptMsReductionAbs,
        if (promptMsReductionPct != null)
          'promptMsReductionPct': promptMsReductionPct,
        if (coldCachedShare != null) 'coldCachedPromptShare': coldCachedShare,
        if (warmCachedShare != null) 'warmCachedPromptShare': warmCachedShare,
        if (improved != null) 'improved': improved,
      },
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL22 Idle Warm-Up Measurement')
      ..writeln()
      ..writeln('- Generated: `${generatedAt.toIso8601String()}`')
      ..writeln('- Base URL: `$baseUrl`')
      ..writeln('- Model: `$model`')
      ..writeln('- Tool count: `$toolCount`')
      ..writeln('- Prompt chars: `$promptChars`')
      ..writeln()
      ..writeln(
        '| Run | id_slot | Warmed first | prompt_ms | cached share | cache_n | prompt_n |',
      )
      ..writeln('| --- | ---: | :--: | ---: | ---: | ---: | ---: |');
    for (final run in [coldRun, warmRun]) {
      buffer.writeln(
        '| `${run.label}` | ${run.idSlot ?? '-'} | '
        '${run.warmedFirst ? 'yes' : 'no'} | '
        '${_formatDouble(run.timing.promptMs)} | '
        '${_formatPercent(run.timing.cachedPromptShare)} | '
        '${run.timing.cacheN ?? '-'} | ${run.timing.promptN ?? '-'} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Comparison')
      ..writeln()
      ..writeln('- Cold prompt_ms: `${_formatDouble(coldPromptMs)}`')
      ..writeln('- Warm prompt_ms: `${_formatDouble(warmPromptMs)}`')
      ..writeln(
        '- prompt_ms reduction: `${_formatDouble(promptMsReductionAbs)}` '
        '(`${_formatPercent(promptMsReductionPct)}`)',
      )
      ..writeln('- Improved: `${improved ?? 'unknown'}`');

    final warnings = [
      ...coldRun.warnings.map((warning) => 'cold: $warning'),
      ...warmRun.warnings.map((warning) => 'warm: $warning'),
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

Future<Ll22WarmupMeasurementSummary> runLl22WarmupMeasurement({
  required Ll22MeasurementOptions options,
  required Ll22ChatCompletionSender sender,
  DateTime? generatedAt,
}) async {
  final coldSlot = options.idSlot;
  final warmSlot = options.idSlot == null ? null : options.idSlot! + 1;

  // Cold: a never-before-seen prefix, measured with no preceding warm-up.
  final coldNonce = 'cold-${DateTime.now().microsecondsSinceEpoch}';
  final coldBody = buildLl22MeasuredRequestBody(
    options: options,
    nonce: coldNonce,
    idSlot: coldSlot,
  );
  final coldResponse = await sender(coldBody);
  final coldTiming = Ll22TimingSample.fromResponseJson(coldResponse);

  // Warm: prime the slot with the warm-up request, then measure the same
  // first-turn prefix on the same slot.
  final warmNonce = 'warm-${DateTime.now().microsecondsSinceEpoch}';
  final warmupBody = buildLl22WarmupRequestBody(
    options: options,
    nonce: warmNonce,
    idSlot: warmSlot,
  );
  await sender(warmupBody);
  final warmMeasuredBody = buildLl22MeasuredRequestBody(
    options: options,
    nonce: warmNonce,
    idSlot: warmSlot,
  );
  final warmResponse = await sender(warmMeasuredBody);
  final warmTiming = Ll22TimingSample.fromResponseJson(warmResponse);

  return Ll22WarmupMeasurementSummary(
    generatedAt: generatedAt ?? DateTime.now(),
    baseUrl: options.baseUrl,
    model: options.model,
    toolCount: options.toolCount,
    promptChars: options.promptChars,
    coldRun: Ll22MeasurementRun(
      label: 'cold',
      idSlot: coldSlot,
      toolCount: _asList(coldBody['tools']).length,
      warmedFirst: false,
      timing: coldTiming,
      warnings: [
        if (!coldTiming.hasCacheTiming)
          'Cold response did not include timings.cache_n and timings.prompt_n.',
      ],
    ),
    warmRun: Ll22MeasurementRun(
      label: 'warm',
      idSlot: warmSlot,
      toolCount: _asList(warmMeasuredBody['tools']).length,
      warmedFirst: true,
      timing: warmTiming,
      warnings: [
        if (!warmTiming.hasCacheTiming)
          'Warm response did not include timings.cache_n and timings.prompt_n.',
      ],
    ),
  );
}

Map<String, dynamic> buildLl22MeasuredRequestBody({
  required Ll22MeasurementOptions options,
  required String nonce,
  int? idSlot,
}) {
  return {
    'model': options.model,
    'messages': [
      {
        'role': 'system',
        'content': buildLl22SystemPrompt(
          nonce: nonce,
          promptChars: options.promptChars,
        ),
      },
      {
        'role': 'user',
        'content':
            'Inspect the active project and outline the first edit you would make.',
      },
    ],
    'temperature': 0.0,
    'max_tokens': options.maxTokens,
    'stream': false,
    'cache_prompt': true,
    'id_slot': ?idSlot,
    'tools': buildLl22MeasurementTools(options.toolCount),
  };
}

Map<String, dynamic> buildLl22WarmupRequestBody({
  required Ll22MeasurementOptions options,
  required String nonce,
  int? idSlot,
}) {
  return {
    'model': options.model,
    'messages': [
      {
        'role': 'system',
        'content': buildLl22SystemPrompt(
          nonce: nonce,
          promptChars: options.promptChars,
        ),
      },
      {'role': 'user', 'content': 'ready'},
    ],
    'temperature': 0.0,
    'max_tokens': options.warmupMaxTokens,
    'stream': false,
    'cache_prompt': true,
    'id_slot': ?idSlot,
    'tools': buildLl22MeasurementTools(options.toolCount),
  };
}

/// Builds a deterministic system prompt of roughly [promptChars] characters,
/// with the run [nonce] at the head (modeling the volatile temporal context)
/// followed by a stable bulk (modeling the repo map + harness guidance).
String buildLl22SystemPrompt({
  required String nonce,
  required int promptChars,
}) {
  final buffer = StringBuffer()
    ..writeln('RUN-NONCE: $nonce')
    ..writeln(
      'You are the Caverno LL22 warm-up measurement coding assistant. '
      'Keep responses short and deterministic.',
    )
    ..writeln('<repo_map>');
  var line = 0;
  while (buffer.length < promptChars) {
    buffer.writeln(
      '- lib/features/module_$line/service_$line.dart: '
      'class Service$line, function handle$line, provider service${line}Provider',
    );
    line += 1;
  }
  buffer.writeln('</repo_map>');
  return buffer.toString();
}

List<Map<String, dynamic>> buildLl22MeasurementTools(int toolCount) {
  return [
    for (var index = 0; index < toolCount; index += 1)
      {
        'type': 'function',
        'function': {
          'name': 'll22_tool_$index',
          'description':
              'Read a deterministic LL22 measurement fixture and return text.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
            },
            'required': ['path'],
          },
        },
      },
  ];
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
    throw Ll22MeasurementHttpException(
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

class Ll22MeasurementHttpException implements Exception {
  const Ll22MeasurementHttpException({
    required this.statusCode,
    required this.responseBody,
  });

  final int statusCode;
  final String responseBody;

  @override
  String toString() {
    return 'LL22 measurement HTTP $statusCode: $responseBody';
  }
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

String _formatPercent(double? value) {
  if (value == null) return '-';
  return '${(value * 100).toStringAsFixed(1)}%';
}

String _formatDouble(double? value) {
  if (value == null) return '-';
  return value.toStringAsFixed(1);
}
