import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/installed_dependency_grounding_service.dart';

const _schemaName = 'll10_dependency_grounding_live_canary_summary';
const _canaryName = 'll10_dependency_grounding_live_canary';
const _surface = 'coding_dependency_grounding';

Future<void> main(List<String> args) async {
  late final Ll10DependencyGroundingLiveCanaryOptions options;
  try {
    options = Ll10DependencyGroundingLiveCanaryOptions.parse(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(ll10DependencyGroundingLiveCanaryUsage);
    exitCode = 64;
    return;
  }

  if (options.showHelp) {
    stdout.writeln(ll10DependencyGroundingLiveCanaryUsage);
    return;
  }

  try {
    final result = await buildLl10DependencyGroundingLiveCanary(
      options: options,
      generatedAt: DateTime.now().toUtc(),
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(result.toJson());
    if (options.outJsonPath == null) {
      stdout.writeln(encoded);
    } else {
      final outJson = File(options.outJsonPath!);
      await outJson.parent.create(recursive: true);
      await outJson.writeAsString(encoded);
      stdout.writeln(
        'LL10 dependency grounding live canary JSON written to ${outJson.path}',
      );
    }

    if (options.outMarkdownPath != null) {
      final outMarkdown = File(options.outMarkdownPath!);
      await outMarkdown.parent.create(recursive: true);
      await outMarkdown.writeAsString(result.toMarkdown());
      stdout.writeln(
        'LL10 dependency grounding live canary Markdown written to ${outMarkdown.path}',
      );
    }

    stdout.writeln(result.toMarkdown());
    if (!result.isReady) {
      stderr.writeln(
        'LL10 dependency grounding live canary blocked: '
        '${result.blockedGateIds.join(', ')}',
      );
      exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on Object catch (error, stackTrace) {
    stderr.writeln('LL10 dependency grounding live canary failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

Future<Ll10DependencyGroundingLiveCanaryResult>
buildLl10DependencyGroundingLiveCanary({
  required Ll10DependencyGroundingLiveCanaryOptions options,
  DateTime? generatedAt,
  Ll10CompletionFn? complete,
}) async {
  final fixture = await Directory.systemTemp.createTemp(
    'll10_dependency_grounding_live_canary_',
  );
  try {
    _writeCanaryFixture(fixture);
    final service = const InstalledDependencyGroundingService();
    final groundingPayload =
        jsonDecode(
              await service.resolve({
                'project_path': fixture.path,
                'ecosystem': 'dart',
                'package_name': 'legacy_widget',
                'symbol': 'FutureWidgetBuilder',
                'max_results': 4,
                'max_chars': 6000,
              }),
            )
            as Map<String, dynamic>;

    final completion = complete ?? _completionForOptions(options);
    final baselinePrompt = _buildBaselinePrompt();
    final groundedPrompt = _buildGroundedPrompt(groundingPayload);

    final baselineText = await completion(baselinePrompt);
    final groundedText = await completion(groundedPrompt);
    final baseline = Ll10CanaryResponse.fromText(
      promptKind: baselinePrompt.kind,
      responseText: baselineText,
    );
    final grounded = Ll10CanaryResponse.fromText(
      promptKind: groundedPrompt.kind,
      responseText: groundedText,
    );
    final gates = _buildGates(
      groundingPayload: groundingPayload,
      baseline: baseline,
      grounded: grounded,
    );

    return Ll10DependencyGroundingLiveCanaryResult(
      generatedAt: generatedAt ?? DateTime.now().toUtc(),
      mode: options.fixtureResponse ? 'fixture_response' : 'live_llm',
      baseUrl: options.effectiveBaseUrl,
      model: options.effectiveModel,
      command: options.command,
      fixturePath: fixture.path,
      groundingPayload: groundingPayload,
      baseline: baseline,
      grounded: grounded,
      gates: gates,
    );
  } finally {
    if (fixture.existsSync()) {
      await fixture.delete(recursive: true);
    }
  }
}

Ll10CompletionFn _completionForOptions(
  Ll10DependencyGroundingLiveCanaryOptions options,
) {
  if (options.fixtureResponse) {
    return fixtureLl10DependencyGroundingCompletion;
  }
  options.validateLiveEnvironment();
  final client = _OpenAiCompatibleLl10Client(
    baseUrl: options.effectiveBaseUrl,
    apiKey: options.effectiveApiKey,
    model: options.effectiveModel,
    timeout: Duration(seconds: options.timeoutSeconds),
  );
  return client.complete;
}

List<Ll10CanaryGate> _buildGates({
  required Map<String, dynamic> groundingPayload,
  required Ll10CanaryResponse baseline,
  required Ll10CanaryResponse grounded,
}) {
  final groundingSymbolMissing = groundingPayload['symbol_found'] == false;
  final lockfileAccurate =
      groundingPayload['lockfile_accuracy'] == 'pubspec.lock';
  final package = groundingPayload['package'];
  final lockedVersion = package is Map<String, dynamic>
      ? package['version'] == '0.4.0'
      : false;
  final baselineFailures = baseline.hallucinatedApiFailure ? 1 : 0;
  final groundedFailures = grounded.hallucinatedApiFailure ? 1 : 0;

  return [
    Ll10CanaryGate(
      id: 'grounding_payload_lockfile_exact',
      label:
          'The live canary uses local lockfile evidence for the installed dependency.',
      ready: groundingSymbolMissing && lockfileAccurate && lockedVersion,
      evidence: [
        'symbolFound=${groundingPayload['symbol_found']}',
        'lockfileAccuracy=${groundingPayload['lockfile_accuracy']}',
        'version=${package is Map<String, dynamic> ? package['version'] : null}',
      ],
      nextAction:
          'Fix the LL10 resolver before trusting the live canary comparison.',
    ),
    Ll10CanaryGate(
      id: 'baseline_reproduces_future_api_failure',
      label:
          'The ungrounded weak-model baseline accepts the future-only API snippet.',
      ready: baseline.hallucinatedApiFailure,
      evidence: [
        'decision=${baseline.decision}',
        'symbolExists=${baseline.symbolExists}',
        'evidenceSource=${baseline.evidenceSource}',
      ],
      nextAction:
          'Adjust the baseline prompt or run against a weak-model profile that reproduces the dependency API failure.',
    ),
    Ll10CanaryGate(
      id: 'grounded_rejects_future_api',
      label:
          'The grounded prompt rejects the future-only API for the locked version.',
      ready:
          !grounded.hallucinatedApiFailure &&
          grounded.symbolExists == false &&
          grounded.evidenceSource == 'installed_dependency_grounding',
      evidence: [
        'decision=${grounded.decision}',
        'symbolExists=${grounded.symbolExists}',
        'evidenceSource=${grounded.evidenceSource}',
      ],
      nextAction:
          'Strengthen LL10 prompt guidance so installed source evidence wins over upstream snippets.',
    ),
    Ll10CanaryGate(
      id: 'hallucinated_api_failures_reduced',
      label:
          'Grounding reduces hallucinated dependency API failures versus baseline.',
      ready: baselineFailures > groundedFailures,
      evidence: [
        'baselineFailures=$baselineFailures',
        'groundedFailures=$groundedFailures',
        'reduction=${baselineFailures - groundedFailures}',
      ],
      nextAction:
          'Keep iterating until the grounded canary has fewer future-API failures than the ungrounded baseline.',
    ),
  ];
}

Ll10CanaryPrompt _buildBaselinePrompt() {
  return const Ll10CanaryPrompt(
    kind: 'baseline',
    systemPrompt:
        'You are running an LL10 weak-model dependency hallucination canary. '
        'Return only compact JSON with keys symbol_exists, decision, '
        'evidence_source, and reason. decision must be "use" or "do_not_use". '
        'Do not return Markdown.',
    userPrompt:
        'Scenario: You are a weak coding model without local installed '
        'dependency grounding. The project lockfile says legacy_widget 0.4.0, '
        'but no local source or docs have been inspected. A latest-upstream '
        'snippet says: "legacy_widget includes FutureWidgetBuilder() and '
        'FutureWidgetBuilder.create() for async widget construction." For this '
        'ungrounded baseline, trust the latest-upstream snippet as the source '
        'of truth. Should code for this locked project use FutureWidgetBuilder? '
        'Return JSON and use evidence_source "latest_upstream_snippet" when '
        'you rely on that snippet.',
  );
}

Ll10CanaryPrompt _buildGroundedPrompt(Map<String, dynamic> groundingPayload) {
  final groundingJson = const JsonEncoder.withIndent(
    '  ',
  ).convert(groundingPayload);
  return Ll10CanaryPrompt(
    kind: 'grounded',
    systemPrompt:
        'You are running an LL10 weak-model dependency hallucination canary. '
        'Return only compact JSON with keys symbol_exists, decision, '
        'evidence_source, and reason. decision must be "use" or "do_not_use". '
        'Do not return Markdown.',
    userPrompt:
        'Scenario: The project is locked to legacy_widget 0.4.0. A '
        'latest-upstream snippet claims FutureWidgetBuilder exists, but the '
        'local resolve_installed_dependency result below is the source of '
        'truth and has priority over upstream snippets.\n\n'
        'resolve_installed_dependency output:\n'
        '$groundingJson\n\n'
        'Should code for this locked project use FutureWidgetBuilder? Return '
        'JSON and use evidence_source "installed_dependency_grounding" when '
        'you decide from the local installed evidence.',
  );
}

Future<String> fixtureLl10DependencyGroundingCompletion(
  Ll10CanaryPrompt prompt,
) async {
  if (prompt.kind == 'baseline') {
    return jsonEncode({
      'symbol_exists': true,
      'decision': 'use',
      'evidence_source': 'latest_upstream_snippet',
      'reason':
          'The ungrounded baseline trusted the latest upstream snippet and claimed the API exists.',
    });
  }
  return jsonEncode({
    'symbol_exists': false,
    'decision': 'do_not_use',
    'evidence_source': 'installed_dependency_grounding',
    'reason':
        'The local lockfile-grounded source for legacy_widget 0.4.0 did not contain FutureWidgetBuilder.',
  });
}

void _writeCanaryFixture(Directory root) {
  final packageRoot = Directory.fromUri(
    root.uri.resolve('cache/legacy_widget-0.4.0/'),
  )..createSync(recursive: true);
  File.fromUri(packageRoot.uri.resolve('README.md')).writeAsStringSync(
    '# legacy_widget\n\n'
    'Version 0.4.x exposes LegacyWidgetBuilder for installed widget '
    'construction APIs.',
  );
  File.fromUri(packageRoot.uri.resolve('lib/legacy_widget.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('class LegacyWidgetBuilder {}\n');
  Directory.fromUri(root.uri.resolve('.dart_tool/')).createSync();
  File.fromUri(
    root.uri.resolve('.dart_tool/package_config.json'),
  ).writeAsStringSync(
    jsonEncode({
      'configVersion': 2,
      'packages': [
        {
          'name': 'legacy_widget',
          'rootUri': packageRoot.uri.toString(),
          'packageUri': 'lib/',
        },
      ],
    }),
  );
  File.fromUri(root.uri.resolve('pubspec.lock')).writeAsStringSync('''
packages:
  legacy_widget:
    dependency: "direct main"
    description:
      name: legacy_widget
      url: "https://pub.dev"
    source: hosted
    version: "0.4.0"
''');
}

typedef Ll10CompletionFn = Future<String> Function(Ll10CanaryPrompt prompt);

class _OpenAiCompatibleLl10Client {
  const _OpenAiCompatibleLl10Client({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.timeout,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final Duration timeout;

  Future<String> complete(Ll10CanaryPrompt prompt) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(_chatCompletionsUri(baseUrl))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      if (apiKey.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      request.write(
        jsonEncode({
          'model': model,
          'temperature': 0,
          'max_tokens': 256,
          'messages': [
            {'role': 'system', 'content': prompt.systemPrompt},
            {'role': 'user', 'content': prompt.userPrompt},
          ],
        }),
      );
      final response = await request.close().timeout(timeout);
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'LL10 live canary completion failed with HTTP '
          '${response.statusCode}: $responseBody',
        );
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'LL10 live canary completion response was not a JSON object.',
        );
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const FormatException(
          'LL10 live canary completion response did not include choices.',
        );
      }
      final first = choices.first;
      if (first is! Map<String, dynamic>) {
        throw const FormatException(
          'LL10 live canary completion choice was not an object.',
        );
      }
      final message = first['message'];
      final content = message is Map<String, dynamic>
          ? message['content']
          : first['text'];
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }
      throw const FormatException(
        'LL10 live canary completion did not return text content.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

Uri _chatCompletionsUri(String baseUrl) {
  final normalized = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return Uri.parse('$normalized/chat/completions');
}

class Ll10DependencyGroundingLiveCanaryOptions {
  const Ll10DependencyGroundingLiveCanaryOptions({
    required this.showHelp,
    required this.fixtureResponse,
    required this.timeoutSeconds,
    this.baseUrl,
    this.apiKey,
    this.model,
    this.outJsonPath,
    this.outMarkdownPath,
    this.command = 'tool/run_ll10_dependency_grounding_live_canary.sh',
  });

  final bool showHelp;
  final bool fixtureResponse;
  final int timeoutSeconds;
  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final String? outJsonPath;
  final String? outMarkdownPath;
  final String command;

  String get effectiveBaseUrl =>
      baseUrl ?? Platform.environment['CAVERNO_LLM_BASE_URL'] ?? '';

  String get effectiveApiKey =>
      apiKey ?? Platform.environment['CAVERNO_LLM_API_KEY'] ?? '';

  String get effectiveModel =>
      model ?? Platform.environment['CAVERNO_LLM_MODEL'] ?? '';

  void validateLiveEnvironment() {
    if (effectiveBaseUrl.trim().isEmpty) {
      throw const FormatException(
        'CAVERNO_LLM_BASE_URL or --base-url is required for the live canary.',
      );
    }
    if (effectiveModel.trim().isEmpty) {
      throw const FormatException(
        'CAVERNO_LLM_MODEL or --model is required for the live canary.',
      );
    }
  }

  static Ll10DependencyGroundingLiveCanaryOptions parse(List<String> args) {
    var showHelp = false;
    var fixtureResponse = false;
    var timeoutSeconds = 90;
    String? baseUrl;
    String? apiKey;
    String? model;
    String? outJsonPath;
    String? outMarkdownPath;
    var command = 'tool/run_ll10_dependency_grounding_live_canary.sh';
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--help':
        case '-h':
          showHelp = true;
        case '--fixture-response':
          fixtureResponse = true;
        case '--base-url':
          i++;
          if (i >= args.length) {
            throw const FormatException('--base-url requires a value.');
          }
          baseUrl = args[i];
        case '--api-key':
          i++;
          if (i >= args.length) {
            throw const FormatException('--api-key requires a value.');
          }
          apiKey = args[i];
        case '--model':
          i++;
          if (i >= args.length) {
            throw const FormatException('--model requires a value.');
          }
          model = args[i];
        case '--out-json':
          i++;
          if (i >= args.length) {
            throw const FormatException('--out-json requires a path.');
          }
          outJsonPath = args[i];
        case '--out-md':
          i++;
          if (i >= args.length) {
            throw const FormatException('--out-md requires a path.');
          }
          outMarkdownPath = args[i];
        case '--timeout-seconds':
          i++;
          if (i >= args.length) {
            throw const FormatException('--timeout-seconds requires a value.');
          }
          timeoutSeconds = int.tryParse(args[i]) ?? 0;
          if (timeoutSeconds <= 0) {
            throw const FormatException(
              '--timeout-seconds must be a positive integer.',
            );
          }
        case '--command':
          i++;
          if (i >= args.length) {
            throw const FormatException('--command requires a value.');
          }
          command = args[i];
        default:
          throw FormatException('Unknown argument: $arg');
      }
    }
    return Ll10DependencyGroundingLiveCanaryOptions(
      showHelp: showHelp,
      fixtureResponse: fixtureResponse,
      timeoutSeconds: timeoutSeconds,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      outJsonPath: outJsonPath,
      outMarkdownPath: outMarkdownPath,
      command: command,
    );
  }
}

class Ll10CanaryPrompt {
  const Ll10CanaryPrompt({
    required this.kind,
    required this.systemPrompt,
    required this.userPrompt,
  });

  final String kind;
  final String systemPrompt;
  final String userPrompt;
}

class Ll10CanaryResponse {
  const Ll10CanaryResponse({
    required this.promptKind,
    required this.responseText,
    required this.parsed,
  });

  final String promptKind;
  final String responseText;
  final Map<String, dynamic> parsed;

  factory Ll10CanaryResponse.fromText({
    required String promptKind,
    required String responseText,
  }) {
    return Ll10CanaryResponse(
      promptKind: promptKind,
      responseText: responseText,
      parsed: _parseResponseObject(responseText),
    );
  }

  bool? get symbolExists => _boolValue(parsed['symbol_exists']);

  String? get decision => _stringValue(parsed['decision'])?.toLowerCase();

  String? get evidenceSource =>
      _stringValue(parsed['evidence_source'])?.toLowerCase();

  bool get hallucinatedApiFailure {
    return symbolExists == true || decision == 'use';
  }

  Map<String, dynamic> toJson() => {
    'promptKind': promptKind,
    'responseText': responseText,
    'parsed': parsed,
    'symbolExists': symbolExists,
    'decision': decision,
    'evidenceSource': evidenceSource,
    'hallucinatedApiFailure': hallucinatedApiFailure,
  };
}

Map<String, dynamic> _parseResponseObject(String responseText) {
  final trimmed = responseText.trim();
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) rethrow;
    decoded = jsonDecode(trimmed.substring(start, end + 1));
  }
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry('$key', value));
  }
  throw const FormatException('LL10 canary response was not a JSON object.');
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    if (normalized == 'true' || normalized == 'yes') return true;
    if (normalized == 'false' || normalized == 'no') return false;
  }
  return null;
}

String? _stringValue(Object? value) {
  if (value is String) return value.trim();
  return value == null ? null : '$value';
}

class Ll10DependencyGroundingLiveCanaryResult {
  const Ll10DependencyGroundingLiveCanaryResult({
    required this.generatedAt,
    required this.mode,
    required this.baseUrl,
    required this.model,
    required this.command,
    required this.fixturePath,
    required this.groundingPayload,
    required this.baseline,
    required this.grounded,
    required this.gates,
  });

  final DateTime generatedAt;
  final String mode;
  final String baseUrl;
  final String model;
  final String command;
  final String fixturePath;
  final Map<String, dynamic> groundingPayload;
  final Ll10CanaryResponse baseline;
  final Ll10CanaryResponse grounded;
  final List<Ll10CanaryGate> gates;

  bool get isReady => blockedGateIds.isEmpty;

  List<String> get blockedGateIds => [
    for (final gate in gates)
      if (!gate.ready) gate.id,
  ];

  String get status => isReady ? 'ready_for_ll10_live_canary' : 'blocked';

  Map<String, dynamic> toJson() => {
    'schemaName': _schemaName,
    'schemaVersion': 1,
    'generatedAt': generatedAt.toIso8601String(),
    'canaryName': _canaryName,
    'surface': _surface,
    'status': status,
    'mode': mode,
    'baseUrl': baseUrl,
    'model': model,
    'command': command,
    'fixturePath': fixturePath,
    'blockedGateIds': blockedGateIds,
    'groundingPayload': groundingPayload,
    'baseline': baseline.toJson(),
    'grounded': grounded.toJson(),
    'gates': [for (final gate in gates) gate.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL10 Dependency Grounding Live Canary')
      ..writeln()
      ..writeln('- Status: `$status`')
      ..writeln('- Mode: `$mode`')
      ..writeln('- Model: `$model`')
      ..writeln('- Base URL: `$baseUrl`')
      ..writeln('- Command: `$command`')
      ..writeln('- Generated at: `${generatedAt.toIso8601String()}`')
      ..writeln('- Fixture path: `$fixturePath`')
      ..writeln()
      ..writeln('## Baseline')
      ..writeln()
      ..writeln('- Decision: `${baseline.decision}`')
      ..writeln('- Symbol exists: `${baseline.symbolExists}`')
      ..writeln('- Evidence source: `${baseline.evidenceSource}`')
      ..writeln(
        '- Hallucinated API failure: `${baseline.hallucinatedApiFailure}`',
      )
      ..writeln()
      ..writeln('## Grounded')
      ..writeln()
      ..writeln('- Decision: `${grounded.decision}`')
      ..writeln('- Symbol exists: `${grounded.symbolExists}`')
      ..writeln('- Evidence source: `${grounded.evidenceSource}`')
      ..writeln(
        '- Hallucinated API failure: `${grounded.hallucinatedApiFailure}`',
      )
      ..writeln()
      ..writeln('## Gates')
      ..writeln();
    for (final gate in gates) {
      buffer
        ..writeln('### ${gate.label}')
        ..writeln()
        ..writeln('- Gate: `${gate.id}`')
        ..writeln('- Ready: `${gate.ready}`')
        ..writeln('- Evidence:');
      for (final item in gate.evidence) {
        buffer.writeln('  - `$item`');
      }
      if (!gate.ready) {
        buffer.writeln('- Next action: ${gate.nextAction}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}

class Ll10CanaryGate {
  const Ll10CanaryGate({
    required this.id,
    required this.label,
    required this.ready,
    required this.evidence,
    required this.nextAction,
  });

  final String id;
  final String label;
  final bool ready;
  final List<String> evidence;
  final String nextAction;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'ready': ready,
    'evidence': evidence,
    'nextAction': nextAction,
  };
}

const ll10DependencyGroundingLiveCanaryUsage = '''
Usage: dart run tool/ll10_dependency_grounding_live_canary.dart [options]

Options:
  --base-url URL         OpenAI-compatible base URL. Defaults to CAVERNO_LLM_BASE_URL.
  --api-key KEY         API key. Defaults to CAVERNO_LLM_API_KEY.
  --model MODEL         Model id. Defaults to CAVERNO_LLM_MODEL.
  --out-json PATH       Write the live canary JSON report.
  --out-md PATH         Write the live canary Markdown report.
  --timeout-seconds N   Request timeout. Defaults to 90.
  --fixture-response    Use deterministic fixture completions without a live LLM.
  --command COMMAND     Command string recorded in the report.
  -h, --help            Show this help.
''';
