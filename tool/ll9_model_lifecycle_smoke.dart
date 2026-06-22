import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final config = Ll9SmokeConfig.parse(args, Platform.environment);
  if (config.showHelp) {
    stdout.writeln(Ll9SmokeConfig.usage);
    return;
  }

  final smoke = Ll9ModelLifecycleSmoke(config);
  final report = await smoke.run();
  await report.write();

  stdout.writeln('LL9 lifecycle smoke JSON: ${config.outJson}');
  stdout.writeln('LL9 lifecycle smoke Markdown: ${config.outMarkdown}');
  if (!report.passed) {
    exitCode = 1;
  }
}

class Ll9SmokeConfig {
  Ll9SmokeConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.fromModel,
    required this.toModel,
    required this.restore,
    required this.pollTimeout,
    required this.pollInterval,
    required this.outJson,
    required this.outMarkdown,
    this.showHelp = false,
  });

  factory Ll9SmokeConfig.parse(
    List<String> args,
    Map<String, String> environment,
  ) {
    final values = <String, String>{};
    var restore =
        _truthy(environment['CAVERNO_LL9_RESTORE']) ||
        _truthy(environment['CAVERNO_LL9_MODEL_LIFECYCLE_RESTORE']);
    var showHelp = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--help':
        case '-h':
          showHelp = true;
        case '--restore':
          restore = true;
        case '--no-restore':
          restore = false;
        case '--base-url':
        case '--api-key':
        case '--from-model':
        case '--to-model':
        case '--poll-timeout-seconds':
        case '--poll-interval-ms':
        case '--out-json':
        case '--out-md':
          if (i + 1 >= args.length) {
            throw ArgumentError('Missing value for $arg.');
          }
          values[arg] = args[++i];
        default:
          throw ArgumentError('Unknown argument: $arg.');
      }
    }

    final outJson =
        values['--out-json'] ??
        environment['CAVERNO_LL9_MODEL_LIFECYCLE_OUT_JSON'] ??
        'build/integration_test_reports/ll9_model_lifecycle_smoke.json';
    final outMarkdown =
        values['--out-md'] ??
        environment['CAVERNO_LL9_MODEL_LIFECYCLE_OUT_MD'] ??
        'build/integration_test_reports/ll9_model_lifecycle_smoke.md';

    return Ll9SmokeConfig(
      baseUrl: _normalizeOpenAiBaseUrl(
        values['--base-url'] ??
            environment['CAVERNO_LLM_BASE_URL'] ??
            'http://localhost:1234/v1',
      ),
      apiKey:
          values['--api-key'] ?? environment['CAVERNO_LLM_API_KEY'] ?? 'no-key',
      fromModel:
          values['--from-model'] ?? environment['CAVERNO_LL9_FROM_MODEL'] ?? '',
      toModel:
          values['--to-model'] ?? environment['CAVERNO_LL9_TO_MODEL'] ?? '',
      restore: restore,
      pollTimeout: Duration(
        seconds: int.parse(
          values['--poll-timeout-seconds'] ??
              environment['CAVERNO_LL9_POLL_TIMEOUT_SECONDS'] ??
              '180',
        ),
      ),
      pollInterval: Duration(
        milliseconds: int.parse(
          values['--poll-interval-ms'] ??
              environment['CAVERNO_LL9_POLL_INTERVAL_MS'] ??
              '2000',
        ),
      ),
      outJson: outJson,
      outMarkdown: outMarkdown,
      showHelp: showHelp,
    );
  }

  static const usage = '''
LL9 model lifecycle live smoke.

Required:
  --from-model MODEL_ID      Model to unload before loading the target.
  --to-model MODEL_ID        Target model to load.

Options:
  --base-url URL             OpenAI-compatible base URL. Defaults to CAVERNO_LLM_BASE_URL or localhost.
  --api-key KEY              API key. Defaults to CAVERNO_LLM_API_KEY or no-key.
  --restore                  Restore by unloading the target and loading the from-model.
  --no-restore               Do not restore after the smoke.
  --poll-timeout-seconds N   Poll timeout for state transitions.
  --poll-interval-ms N       Poll interval for state transitions.
  --out-json PATH            JSON report path.
  --out-md PATH              Markdown report path.
''';

  final Uri baseUrl;
  final String apiKey;
  final String fromModel;
  final String toModel;
  final bool restore;
  final Duration pollTimeout;
  final Duration pollInterval;
  final String outJson;
  final String outMarkdown;
  final bool showHelp;

  Uri get modelsUri => _appendPath(baseUrl, 'models');

  Uri lifecycleUri(String action) {
    final nativeRoot = _nativeRootBaseUrl(baseUrl);
    return _appendPath(nativeRoot, 'models/$action');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'baseUrl': baseUrl.toString(),
      'fromModel': fromModel,
      'toModel': toModel,
      'restore': restore,
      'pollTimeoutMs': pollTimeout.inMilliseconds,
      'pollIntervalMs': pollInterval.inMilliseconds,
    };
  }

  void validate() {
    if (fromModel.trim().isEmpty) {
      throw ArgumentError(
        '--from-model or CAVERNO_LL9_FROM_MODEL is required.',
      );
    }
    if (toModel.trim().isEmpty) {
      throw ArgumentError('--to-model or CAVERNO_LL9_TO_MODEL is required.');
    }
    if (fromModel == toModel) {
      throw ArgumentError('from-model and to-model must be different.');
    }
  }

  static bool _truthy(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }
}

class Ll9ModelLifecycleSmoke {
  Ll9ModelLifecycleSmoke(this.config);

  final Ll9SmokeConfig config;
  final HttpClient _client = HttpClient();
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];

  Future<Ll9SmokeReport> run() async {
    config.validate();
    final startedAt = DateTime.now().toUtc();
    var passed = false;
    String? failure;
    Map<String, String>? initialStates;
    Map<String, String>? finalStates;

    try {
      _log('catalog', 'Fetching initial model catalog.');
      initialStates = await _fetchModelStates();
      _requireModel(initialStates, config.fromModel);
      _requireModel(initialStates, config.toModel);

      await _unloadAndConfirm(config.fromModel);
      await _loadAndConfirm(config.toModel);
      passed = true;
    } on Object catch (error, stackTrace) {
      failure = '${error.runtimeType}: $error';
      _log('failure', failure);
      _log('stackTrace', stackTrace.toString());
    } finally {
      if (config.restore) {
        try {
          _log('restore', 'Restoring ${config.fromModel}.');
          await _unloadAndConfirm(config.toModel);
          await _loadAndConfirm(config.fromModel);
        } on Object catch (error, stackTrace) {
          passed = false;
          final restoreFailure = '${error.runtimeType}: $error';
          failure = failure == null
              ? 'Restore failed: $restoreFailure'
              : '$failure\nRestore failed: $restoreFailure';
          _log('restoreFailure', restoreFailure);
          _log('restoreStackTrace', stackTrace.toString());
        }
      }

      try {
        finalStates = await _fetchModelStates();
      } on Object catch (error) {
        failure = failure == null
            ? 'Failed to fetch final model catalog: $error'
            : '$failure\nFailed to fetch final model catalog: $error';
      }
      _client.close(force: true);
    }

    return Ll9SmokeReport(
      config: config,
      passed: passed,
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
      failure: failure,
      initialStates: initialStates ?? const <String, String>{},
      finalStates: finalStates ?? const <String, String>{},
      events: List<Map<String, Object?>>.unmodifiable(_events),
    );
  }

  Future<void> _unloadAndConfirm(String modelId) async {
    await _postLifecycleAction('unload', modelId);
    await _waitForState(modelId, const <String>{'unloaded'});
  }

  Future<void> _loadAndConfirm(String modelId) async {
    await _postLifecycleAction('load', modelId);
    await _waitForState(modelId, const <String>{'loaded'});
  }

  Future<void> _postLifecycleAction(String action, String modelId) async {
    final uri = config.lifecycleUri(action);
    _log(action, 'POST $uri model="$modelId"');
    final response = await _sendJson(
      'POST',
      uri,
      body: <String, String>{'model': modelId},
    );
    _log(
      action,
      'status=${response.statusCode} body=${_truncate(response.body)}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Failed to $action "$modelId": '
        'HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> _waitForState(String modelId, Set<String> allowedStates) async {
    final deadline = DateTime.now().add(config.pollTimeout);
    String? lastState;
    while (DateTime.now().isBefore(deadline)) {
      final states = await _fetchModelStates();
      lastState = states[modelId];
      _log('poll', 'model="$modelId" state=$lastState');
      if (lastState != null && allowedStates.contains(lastState)) {
        return;
      }
      await Future<void>.delayed(config.pollInterval);
    }
    throw TimeoutException(
      'Timed out waiting for "$modelId" to enter '
      '${allowedStates.join('/')} (last state: $lastState).',
      config.pollTimeout,
    );
  }

  Future<Map<String, String>> _fetchModelStates() async {
    final response = await _sendJson('GET', config.modelsUri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Failed to fetch model catalog: '
        'HTTP ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model catalog is not a JSON object.');
    }
    final data = decoded['data'];
    if (data is! List) {
      throw const FormatException('Model catalog does not include data list.');
    }

    final states = <String, String>{};
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      if (id is! String || id.trim().isEmpty) continue;
      final status = item['status'];
      final value = status is Map<String, dynamic> ? status['value'] : null;
      states[id] = value is String ? value : 'unknown';
    }
    return states;
  }

  Future<_HttpResponseBody> _sendJson(
    String method,
    Uri uri, {
    Object? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final apiKey = config.apiKey.trim();
    if (apiKey.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(config.pollTimeout);
    final responseBody = await utf8.decodeStream(response);
    return _HttpResponseBody(response.statusCode, responseBody);
  }

  void _requireModel(Map<String, String> states, String modelId) {
    if (!states.containsKey(modelId)) {
      throw StateError(
        'Model "$modelId" was not present in ${config.modelsUri}. '
        'Available models: ${states.keys.join(', ')}',
      );
    }
  }

  void _log(String event, String message) {
    stdout.writeln('[ll9-smoke] $event: $message');
    _events.add(<String, Object?>{
      'at': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'message': message,
    });
  }
}

class Ll9SmokeReport {
  Ll9SmokeReport({
    required this.config,
    required this.passed,
    required this.startedAt,
    required this.finishedAt,
    required this.failure,
    required this.initialStates,
    required this.finalStates,
    required this.events,
  });

  final Ll9SmokeConfig config;
  final bool passed;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String? failure;
  final Map<String, String> initialStates;
  final Map<String, String> finalStates;
  final List<Map<String, Object?>> events;

  Future<void> write() async {
    final jsonFile = File(config.outJson);
    await jsonFile.parent.create(recursive: true);
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );

    final markdownFile = File(config.outMarkdown);
    await markdownFile.parent.create(recursive: true);
    await markdownFile.writeAsString(toMarkdown());
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'caverno_ll9_model_lifecycle_smoke_report',
      'passed': passed,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt.toIso8601String(),
      'durationMs': finishedAt.difference(startedAt).inMilliseconds,
      'failure': failure,
      'config': config.toJson(),
      'initialStates': initialStates,
      'finalStates': finalStates,
      'events': events,
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL9 Model Lifecycle Smoke')
      ..writeln()
      ..writeln('- Passed: `$passed`')
      ..writeln('- Base URL: `${config.baseUrl}`')
      ..writeln('- From model: `${config.fromModel}`')
      ..writeln('- To model: `${config.toModel}`')
      ..writeln('- Restore: `${config.restore}`')
      ..writeln('- Started: `${startedAt.toIso8601String()}`')
      ..writeln('- Finished: `${finishedAt.toIso8601String()}`');
    if (failure != null) {
      buffer
        ..writeln()
        ..writeln('## Failure')
        ..writeln()
        ..writeln('```text')
        ..writeln(failure)
        ..writeln('```');
    }
    buffer
      ..writeln()
      ..writeln('## Initial States')
      ..writeln()
      ..writeln(_statesTable(initialStates))
      ..writeln()
      ..writeln('## Final States')
      ..writeln()
      ..writeln(_statesTable(finalStates))
      ..writeln()
      ..writeln('## Events')
      ..writeln()
      ..writeln('| Time | Event | Message |')
      ..writeln('|------|-------|---------|');
    for (final event in events) {
      buffer.writeln(
        '| `${event['at']}` | `${event['event']}` | '
        '${_escapeMarkdownCell('${event['message']}')} |',
      );
    }
    return buffer.toString();
  }

  String _statesTable(Map<String, String> states) {
    final buffer = StringBuffer()
      ..writeln('| Model | State |')
      ..writeln('|-------|-------|');
    for (final entry in states.entries) {
      buffer.writeln('| `${entry.key}` | `${entry.value}` |');
    }
    return buffer.toString();
  }

  String _escapeMarkdownCell(String value) {
    return value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
  }
}

class _HttpResponseBody {
  const _HttpResponseBody(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

Uri _normalizeOpenAiBaseUrl(String rawBaseUrl) {
  var raw = rawBaseUrl.trim();
  if (raw.isEmpty) {
    raw = 'http://localhost:1234/v1';
  }
  if (!raw.contains('://')) {
    raw = 'http://$raw';
  }
  final uri = Uri.parse(raw);
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.isEmpty) {
    path = '/v1';
  } else if (!path.endsWith('/v1')) {
    path = '$path/v1';
  }
  return uri.replace(path: path, query: null, fragment: null);
}

Uri _nativeRootBaseUrl(Uri openAiBaseUrl) {
  var path = openAiBaseUrl.path.replaceAll(RegExp(r'/+$'), '');
  if (path.endsWith('/v1')) {
    path = path.substring(0, path.length - '/v1'.length);
  }
  if (path.isEmpty) {
    path = '/';
  }
  return openAiBaseUrl.replace(path: path, query: null, fragment: null);
}

Uri _appendPath(Uri baseUrl, String suffix) {
  final basePath = baseUrl.path.replaceAll(RegExp(r'/+$'), '');
  final cleanSuffix = suffix.replaceAll(RegExp(r'^/+'), '');
  final path = basePath.isEmpty || basePath == '/'
      ? '/$cleanSuffix'
      : '$basePath/$cleanSuffix';
  return baseUrl.replace(path: path, query: null, fragment: null);
}

String _truncate(String value, {int maxLength = 500}) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...';
}
