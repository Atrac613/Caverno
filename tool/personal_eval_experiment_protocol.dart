import 'dart:convert';
import 'dart:io';

const _schemaName = 'caverno_personal_eval_experiment_protocol';
const _schemaVersion = 2;

Future<void> main(List<String> args) async {
  final options = PersonalEvalExperimentProtocolOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_experiment_protocol.dart '
      '--config PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }

  final PersonalEvalExperimentProtocol protocol;
  try {
    protocol = await buildPersonalEvalExperimentProtocol(
      configFile: File(options.configPath),
    );
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    exitCode = 66;
    return;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
    return;
  }

  final outputDirectory = Directory(options.outDir);
  outputDirectory.createSync(recursive: true);
  final jsonFile = File(
    '${outputDirectory.path}/personal_eval_experiment_protocol.json',
  );
  await jsonFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(protocol.toJson())}\n',
  );
  final markdownFile = File(
    '${outputDirectory.path}/personal_eval_experiment_protocol.md',
  );
  await markdownFile.writeAsString(protocol.toMarkdown());

  stdout.writeln('Personal eval protocol written to ${jsonFile.path}');
}

Future<PersonalEvalExperimentProtocol> buildPersonalEvalExperimentProtocol({
  required File configFile,
  DateTime? generatedAt,
}) async {
  final decoded = jsonDecode(await configFile.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException(
      'Experiment protocol config must be a JSON object: ${configFile.path}',
    );
  }
  return PersonalEvalExperimentProtocol.fromJson(
    decoded,
    path: configFile.path,
    generatedAt: generatedAt,
  );
}

final class PersonalEvalExperimentProtocolOptions {
  const PersonalEvalExperimentProtocolOptions({
    required this.configPath,
    required this.outDir,
  });

  final String configPath;
  final String outDir;

  static PersonalEvalExperimentProtocolOptions? parse(List<String> args) {
    String? configPath;
    String? outDir;
    for (var index = 0; index < args.length; index += 1) {
      switch (args[index]) {
        case '--config':
          configPath = _nextValue(args, ++index);
          if (configPath == null) return null;
        case '--out-dir':
          outDir = _nextValue(args, ++index);
          if (outDir == null) return null;
        default:
          return null;
      }
    }
    if (configPath == null || outDir == null) return null;
    return PersonalEvalExperimentProtocolOptions(
      configPath: configPath,
      outDir: outDir,
    );
  }

  static String? _nextValue(List<String> args, int index) {
    if (index >= args.length) return null;
    final value = args[index];
    return value.startsWith('--') ? null : value;
  }
}

final class PersonalEvalExperimentProtocol {
  const PersonalEvalExperimentProtocol({
    required this.generatedAt,
    required this.label,
    required this.studyIntent,
    required this.decisionCriteria,
    required this.incumbent,
    required this.candidate,
    required this.executionBudget,
    required this.trialOrders,
  });

  final DateTime generatedAt;
  final String label;
  final PersonalEvalStudyIntent studyIntent;
  final PersonalEvalDecisionCriteria? decisionCriteria;
  final PersonalEvalProtocolModel incumbent;
  final PersonalEvalProtocolModel candidate;
  final PersonalEvalExecutionBudget executionBudget;
  final List<PersonalEvalTrialOrder> trialOrders;

  factory PersonalEvalExperimentProtocol.fromJson(
    Map<String, dynamic> json, {
    String path = 'experiment protocol',
    DateTime? generatedAt,
  }) {
    final schemaName = json['schemaName'];
    if (schemaName != null && schemaName != _schemaName) {
      throw FormatException('Unsupported protocol schema in $path.');
    }
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != null && schemaVersion != _schemaVersion) {
      throw FormatException('Unsupported protocol schema version in $path.');
    }

    final label = _requiredString(json, 'label', path);
    final studyIntent = PersonalEvalStudyIntent.parse(json['studyIntent']);
    if (studyIntent == null) {
      throw FormatException(
        'studyIntent must be corpus_design or model_selection in $path.',
      );
    }
    final PersonalEvalDecisionCriteria? decisionCriteria =
        switch (studyIntent) {
          PersonalEvalStudyIntent.corpusDesign => _rejectDecisionCriteria(
            json['decisionCriteria'],
            path,
          ),
          PersonalEvalStudyIntent.modelSelection =>
            PersonalEvalDecisionCriteria.fromJson(
              _requiredObject(json, 'decisionCriteria', path),
              path: '$path.decisionCriteria',
            ),
        };
    final incumbentJson = _requiredObject(json, 'incumbent', path);
    final candidateJson = _requiredObject(json, 'candidate', path);
    final incumbent = PersonalEvalProtocolModel.fromJson(
      incumbentJson,
      path: '$path.incumbent',
    );
    final candidate = PersonalEvalProtocolModel.fromJson(
      candidateJson,
      path: '$path.candidate',
    );
    if (incumbent.model == candidate.model) {
      throw FormatException(
        'Incumbent and candidate models must differ in $path.',
      );
    }

    final rawOrders = json['trialOrders'];
    if (rawOrders is! List || rawOrders.isEmpty) {
      throw FormatException('trialOrders must be a non-empty array in $path.');
    }
    final orders = <PersonalEvalTrialOrder>[];
    final seenTrialKeys = <String>{};
    for (var index = 0; index < rawOrders.length; index += 1) {
      final rawOrder = rawOrders[index];
      if (rawOrder is! Map<String, dynamic>) {
        throw FormatException(
          'trialOrders[$index] must be an object in $path.',
        );
      }
      final order = PersonalEvalTrialOrder.fromJson(
        rawOrder,
        path: '$path.trialOrders[$index]',
      );
      if (!seenTrialKeys.add(order.trialKey)) {
        throw FormatException('Duplicate trial order: ${order.trialKey}');
      }
      orders.add(order);
    }
    _validateOrderBalance(orders, path);

    return PersonalEvalExperimentProtocol(
      generatedAt: generatedAt ?? _optionalDateTime(json, 'generatedAt', path),
      label: label,
      studyIntent: studyIntent,
      decisionCriteria: decisionCriteria,
      incumbent: incumbent,
      candidate: candidate,
      executionBudget: PersonalEvalExecutionBudget.fromJson(
        _requiredObject(json, 'executionBudget', path),
        path: '$path.executionBudget',
      ),
      trialOrders: List.unmodifiable(orders),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaName': _schemaName,
    'schemaVersion': _schemaVersion,
    'generatedAt': generatedAt.toIso8601String(),
    'label': label,
    'studyIntent': studyIntent.jsonValue,
    if (decisionCriteria != null)
      'decisionCriteria': decisionCriteria!.toJson(),
    'incumbent': incumbent.toJson(),
    'candidate': candidate.toJson(),
    'executionBudget': executionBudget.toJson(),
    'trialOrders': trialOrders.map((order) => order.toJson()).toList(),
  };

  String toMarkdown() {
    final incumbentFirst = trialOrders
        .where((order) => order.first == PersonalEvalModelRole.incumbent)
        .length;
    final candidateFirst = trialOrders.length - incumbentFirst;
    final buffer = StringBuffer()
      ..writeln('# Personal Eval Experiment Protocol')
      ..writeln()
      ..writeln('- Label: `$label`')
      ..writeln('- Study intent: `${studyIntent.jsonValue}`')
      ..writeln('- Incumbent: `${incumbent.model}`')
      ..writeln('- Candidate: `${candidate.model}`')
      ..writeln('- Trials: `${trialOrders.length}`')
      ..writeln(
        '- Order balance: `$incumbentFirst incumbent-first / '
        '$candidateFirst candidate-first`',
      )
      ..writeln('- Maximum duration: `${executionBudget.maxDurationMs} ms`')
      ..writeln('- Maximum turns: `${executionBudget.maxTurns}`')
      ..writeln('- Maximum tool calls: `${executionBudget.maxToolCalls}`')
      ..writeln();
    if (decisionCriteria case final criteria?) {
      buffer
        ..writeln(
          '- Minimum effect tasks: `${criteria.minimumEffectTaskCount}`',
        )
        ..writeln(
          '- Minimum held-out effect tasks: '
          '`${criteria.minimumHeldOutEffectTaskCount}`',
        );
    }
    buffer
      ..writeln()
      ..writeln('## Model Conditions')
      ..writeln()
      ..writeln(
        '| Role | Model | Base URL | Sampler Settings | Warm-up Iterations |',
      )
      ..writeln(
        '|------|-------|----------|------------------|--------------------|',
      )
      ..writeln(_modelMarkdownRow('Incumbent', incumbent))
      ..writeln(_modelMarkdownRow('Candidate', candidate))
      ..writeln()
      ..writeln('## Execution Order')
      ..writeln()
      ..writeln('| Position | Case | Trial | First | Second |')
      ..writeln('|----------|------|-------|-------|--------|');
    for (var index = 0; index < trialOrders.length; index += 1) {
      final order = trialOrders[index];
      buffer.writeln(
        '| `${index + 1}` | ${_markdownCell(order.caseId)} '
        '| ${_markdownCell(order.trialId)} | `${order.first.jsonValue}` '
        '| `${order.second.jsonValue}` |',
      );
    }
    return buffer.toString();
  }
}

enum PersonalEvalStudyIntent {
  corpusDesign('corpus_design'),
  modelSelection('model_selection');

  const PersonalEvalStudyIntent(this.jsonValue);

  final String jsonValue;

  static PersonalEvalStudyIntent? parse(Object? value) {
    for (final intent in values) {
      if (intent.jsonValue == value) return intent;
    }
    return null;
  }
}

final class PersonalEvalDecisionCriteria {
  const PersonalEvalDecisionCriteria({
    required this.minimumEffectTaskCount,
    required this.minimumHeldOutEffectTaskCount,
  });

  final int minimumEffectTaskCount;
  final int minimumHeldOutEffectTaskCount;

  factory PersonalEvalDecisionCriteria.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final minimumEffectTaskCount = _requiredPositiveInt(
      json,
      'minimumEffectTaskCount',
      path,
    );
    final minimumHeldOutEffectTaskCount = _requiredNonNegativeInt(
      json,
      'minimumHeldOutEffectTaskCount',
      path,
    );
    if (minimumHeldOutEffectTaskCount > minimumEffectTaskCount) {
      throw FormatException(
        'minimumHeldOutEffectTaskCount cannot exceed '
        'minimumEffectTaskCount in $path.',
      );
    }
    return PersonalEvalDecisionCriteria(
      minimumEffectTaskCount: minimumEffectTaskCount,
      minimumHeldOutEffectTaskCount: minimumHeldOutEffectTaskCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'minimumEffectTaskCount': minimumEffectTaskCount,
    'minimumHeldOutEffectTaskCount': minimumHeldOutEffectTaskCount,
  };
}

PersonalEvalDecisionCriteria? _rejectDecisionCriteria(
  Object? value,
  String path,
) {
  if (value != null) {
    throw FormatException(
      'decisionCriteria is only valid for model_selection in $path.',
    );
  }
  return null;
}

final class PersonalEvalProtocolModel {
  const PersonalEvalProtocolModel({
    required this.model,
    required this.baseUrl,
    required this.samplerSettings,
    required this.warmupIterations,
  });

  final String model;
  final String? baseUrl;
  final Map<String, dynamic> samplerSettings;
  final int warmupIterations;

  factory PersonalEvalProtocolModel.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final samplerSettings = json['samplerSettings'];
    if (samplerSettings is! Map<String, dynamic> || samplerSettings.isEmpty) {
      throw FormatException(
        'samplerSettings must be a non-empty object in $path.',
      );
    }
    _validateJsonValue(samplerSettings, '$path.samplerSettings');

    final warmup = _requiredObject(json, 'warmup', path);
    if (warmup['completed'] != true) {
      throw FormatException('warmup.completed must be true in $path.');
    }
    final iterations = _requiredPositiveInt(
      warmup,
      'iterations',
      '$path.warmup',
    );
    return PersonalEvalProtocolModel(
      model: _requiredString(json, 'model', path),
      baseUrl: _optionalString(json, 'baseUrl', path),
      samplerSettings: Map.unmodifiable(samplerSettings),
      warmupIterations: iterations,
    );
  }

  Map<String, dynamic> toJson() => {
    'model': model,
    if (baseUrl != null) 'baseUrl': baseUrl,
    'samplerSettings': samplerSettings,
    'warmup': {'completed': true, 'iterations': warmupIterations},
  };
}

final class PersonalEvalExecutionBudget {
  const PersonalEvalExecutionBudget({
    required this.maxDurationMs,
    required this.maxTurns,
    required this.maxToolCalls,
  });

  final int maxDurationMs;
  final int maxTurns;
  final int maxToolCalls;

  factory PersonalEvalExecutionBudget.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    return PersonalEvalExecutionBudget(
      maxDurationMs: _requiredPositiveInt(json, 'maxDurationMs', path),
      maxTurns: _requiredPositiveInt(json, 'maxTurns', path),
      maxToolCalls: _requiredPositiveInt(json, 'maxToolCalls', path),
    );
  }

  Map<String, dynamic> toJson() => {
    'maxDurationMs': maxDurationMs,
    'maxTurns': maxTurns,
    'maxToolCalls': maxToolCalls,
  };
}

enum PersonalEvalModelRole {
  incumbent('incumbent'),
  candidate('candidate');

  const PersonalEvalModelRole(this.jsonValue);
  final String jsonValue;

  PersonalEvalModelRole get opposite => switch (this) {
    incumbent => candidate,
    candidate => incumbent,
  };

  static PersonalEvalModelRole? parse(Object? value) {
    for (final role in values) {
      if (role.jsonValue == value) return role;
    }
    return null;
  }
}

final class PersonalEvalTrialOrder {
  const PersonalEvalTrialOrder({
    required this.caseId,
    required this.trialId,
    required this.first,
  });

  final String caseId;
  final String trialId;
  final PersonalEvalModelRole first;

  String get trialKey => '$caseId#$trialId';
  PersonalEvalModelRole get second => first.opposite;

  factory PersonalEvalTrialOrder.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final first = PersonalEvalModelRole.parse(json['first']);
    if (first == null) {
      throw FormatException('first must be incumbent or candidate in $path.');
    }
    return PersonalEvalTrialOrder(
      caseId: _requiredString(json, 'caseId', path),
      trialId: _requiredString(json, 'trialId', path),
      first: first,
    );
  }

  Map<String, dynamic> toJson() => {
    'caseId': caseId,
    'trialId': trialId,
    'first': first.jsonValue,
    'second': second.jsonValue,
  };
}

void _validateOrderBalance(List<PersonalEvalTrialOrder> orders, String path) {
  void requireBalanced(Iterable<PersonalEvalTrialOrder> values, String scope) {
    final entries = values.toList();
    if (entries.length < 2) return;
    final incumbentFirst = entries
        .where((entry) => entry.first == PersonalEvalModelRole.incumbent)
        .length;
    final candidateFirst = entries.length - incumbentFirst;
    if ((incumbentFirst - candidateFirst).abs() > 1) {
      throw FormatException('AB/BA order is unbalanced for $scope in $path.');
    }
  }

  requireBalanced(orders, 'the experiment');
  final caseIds = orders.map((order) => order.caseId).toSet();
  for (final caseId in caseIds) {
    requireBalanced(
      orders.where((order) => order.caseId == caseId),
      'case $caseId',
    );
  }
}

String _modelMarkdownRow(String role, PersonalEvalProtocolModel model) {
  final settings = jsonEncode(model.samplerSettings).replaceAll('|', r'\|');
  return '| $role | ${_markdownCell(model.model)} '
      '| ${_markdownCell(model.baseUrl ?? '-')} | `$settings` '
      '| `${model.warmupIterations}` |';
}

String _markdownCell(String value) => value.replaceAll('|', r'\|');

Map<String, dynamic> _requiredObject(
  Map<String, dynamic> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('$key must be an object in $path.');
  }
  return value;
}

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string in $path.');
  }
  return value.trim();
}

String? _optionalString(Map<String, dynamic> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string in $path.');
  }
  return value.trim();
}

int _requiredPositiveInt(Map<String, dynamic> json, String key, String path) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('$key must be a positive integer in $path.');
  }
  return value;
}

int _requiredNonNegativeInt(
  Map<String, dynamic> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('$key must be a non-negative integer in $path.');
  }
  return value;
}

DateTime _optionalDateTime(Map<String, dynamic> json, String key, String path) {
  final value = json[key];
  if (value == null) return DateTime.now();
  if (value is! String) {
    throw FormatException('$key must be an ISO-8601 string in $path.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$key must be an ISO-8601 string in $path.');
  }
  return parsed;
}

void _validateJsonValue(Object? value, String path) {
  if (value == null || value is String || value is num || value is bool) return;
  if (value is List) {
    for (var index = 0; index < value.length; index += 1) {
      _validateJsonValue(value[index], '$path[$index]');
    }
    return;
  }
  if (value is Map<String, dynamic>) {
    for (final entry in value.entries) {
      _validateJsonValue(entry.value, '$path.${entry.key}');
    }
    return;
  }
  throw FormatException('Value at $path is not JSON-safe.');
}
