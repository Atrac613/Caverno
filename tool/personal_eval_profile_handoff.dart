import 'dart:convert';
import 'dart:io';

const _schemaName = 'caverno_personal_eval_profile_handoff';
const _schemaVersion = 1;
const _suiteReportSchemaName = 'caverno_personal_eval_suite_report';
const _defaultProvider = 'openAiCompatible';

Future<void> main(List<String> args) async {
  final options = PersonalEvalProfileHandoffOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_profile_handoff.dart '
      '--suite-report PATH --out-dir PATH '
      '[--label LABEL] [--target-profile-id ID] '
      '[--target-provider PROVIDER] [--target-base-url URL] '
      '[--target-model MODEL]',
    );
    exitCode = 64;
    return;
  }

  final PersonalEvalProfileHandoff handoff;
  try {
    handoff = await buildPersonalEvalProfileHandoff(
      suiteReportFile: File(options.suiteReportPath),
      label: options.label,
      targetProfileId: options.targetProfileId,
      targetProvider: options.targetProvider,
      targetBaseUrl: options.targetBaseUrl,
      targetModel: options.targetModel,
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
  await outputDirectory.create(recursive: true);
  final jsonFile = File(
    '${outputDirectory.path}/personal_eval_profile_handoff.json',
  );
  final markdownFile = File(
    '${outputDirectory.path}/personal_eval_profile_handoff.md',
  );
  await jsonFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(handoff.toJson())}\n',
  );
  await markdownFile.writeAsString(handoff.toMarkdown());

  stdout.writeln('Personal eval profile handoff written to ${jsonFile.path}');
  stdout.writeln(handoff.toMarkdown());

  if (!handoff.readyForProfileUpdate) {
    exitCode = 1;
  }
}

Future<PersonalEvalProfileHandoff> buildPersonalEvalProfileHandoff({
  required File suiteReportFile,
  String? label,
  String? targetProfileId,
  String? targetProvider,
  String? targetBaseUrl,
  String? targetModel,
  DateTime? generatedAt,
}) async {
  if (!suiteReportFile.existsSync()) {
    throw FileSystemException(
      'Suite report file not found.',
      suiteReportFile.path,
    );
  }
  final report = PersonalEvalSuiteReportSnapshot.fromJson(
    await _readJsonObject(suiteReportFile),
    path: suiteReportFile.path,
  );
  final target = PersonalEvalProfileTarget.fromReport(
    report,
    profileId: targetProfileId,
    provider: targetProvider,
    baseUrl: targetBaseUrl,
    model: targetModel,
  );
  final blockers = <String>[];
  if (report.recommendation != 'candidate_ready') {
    blockers.add('suite recommendation is ${report.recommendation}');
  }
  if (report.hardRegressionCount > 0) {
    blockers.add('suite has ${report.hardRegressionCount} hard regression(s)');
  }
  if (!target.isComplete) {
    blockers.add('candidate profile target is incomplete');
  }

  final readyForProfileUpdate = blockers.isEmpty;
  return PersonalEvalProfileHandoff(
    schemaName: _schemaName,
    schemaVersion: _schemaVersion,
    generatedAt: generatedAt ?? DateTime.now(),
    label: _trimToNull(label) ?? report.label,
    suiteReportPath: suiteReportFile.path,
    result: readyForProfileUpdate ? 'ready' : 'blocked',
    action: readyForProfileUpdate
        ? 'apply_profile_metadata'
        : 'do_not_apply_profile_metadata',
    readyForProfileUpdate: readyForProfileUpdate,
    blockers: List.unmodifiable(blockers),
    target: target,
    metrics: PersonalEvalProfileHandoffMetrics.fromReport(report),
    metadataPatch: _metadataPatch(report, suiteReportFile.path),
    watchSignals: List.unmodifiable(report.watchSignals),
    improvements: List.unmodifiable(report.improvements),
  );
}

Map<String, String> _metadataPatch(
  PersonalEvalSuiteReportSnapshot report,
  String suiteReportPath,
) {
  return {
    'personalEval.lastReportPath': suiteReportPath,
    'personalEval.lastGeneratedAt': report.generatedAt,
    'personalEval.lastLabel': report.label,
    'personalEval.lastResult': report.result,
    'personalEval.lastRecommendation': report.recommendation,
    'personalEval.caseCount': report.caseCount.toString(),
    'personalEval.hardRegressionCount': report.hardRegressionCount.toString(),
    'personalEval.watchSignalCount': report.watchSignalCount.toString(),
    'personalEval.improvementCount': report.improvementCount.toString(),
    'personalEval.incumbentPassRate': _formatDouble(report.incumbentPassRate),
    'personalEval.candidatePassRate': _formatDouble(report.candidatePassRate),
    'personalEval.candidateModel': report.candidateModel ?? '',
    'personalEval.candidateBaseUrl': report.candidateBaseUrl ?? '',
  };
}

String _formatDouble(double value) {
  final rounded = value.toStringAsFixed(4);
  return rounded
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

final class PersonalEvalProfileHandoffOptions {
  const PersonalEvalProfileHandoffOptions({
    required this.suiteReportPath,
    required this.outDir,
    this.label,
    this.targetProfileId,
    this.targetProvider,
    this.targetBaseUrl,
    this.targetModel,
  });

  final String suiteReportPath;
  final String outDir;
  final String? label;
  final String? targetProfileId;
  final String? targetProvider;
  final String? targetBaseUrl;
  final String? targetModel;

  static PersonalEvalProfileHandoffOptions? parse(List<String> args) {
    String? suiteReportPath;
    String? outDir;
    String? label;
    String? targetProfileId;
    String? targetProvider;
    String? targetBaseUrl;
    String? targetModel;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--suite-report':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          suiteReportPath = value;
        case '--out-dir':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          outDir = value;
        case '--label':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          label = value;
        case '--target-profile-id':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          targetProfileId = value;
        case '--target-provider':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          targetProvider = value;
        case '--target-base-url':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          targetBaseUrl = value;
        case '--target-model':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          targetModel = value;
        default:
          return null;
      }
    }

    if (suiteReportPath == null || outDir == null) {
      return null;
    }
    return PersonalEvalProfileHandoffOptions(
      suiteReportPath: suiteReportPath,
      outDir: outDir,
      label: label,
      targetProfileId: targetProfileId,
      targetProvider: targetProvider,
      targetBaseUrl: targetBaseUrl,
      targetModel: targetModel,
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

final class PersonalEvalProfileHandoff {
  const PersonalEvalProfileHandoff({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.label,
    required this.suiteReportPath,
    required this.result,
    required this.action,
    required this.readyForProfileUpdate,
    required this.blockers,
    required this.target,
    required this.metrics,
    required this.metadataPatch,
    required this.watchSignals,
    required this.improvements,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String label;
  final String suiteReportPath;
  final String result;
  final String action;
  final bool readyForProfileUpdate;
  final List<String> blockers;
  final PersonalEvalProfileTarget target;
  final PersonalEvalProfileHandoffMetrics metrics;
  final Map<String, String> metadataPatch;
  final List<String> watchSignals;
  final List<String> improvements;

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'label': label,
      'suiteReportPath': suiteReportPath,
      'result': result,
      'action': action,
      'readyForProfileUpdate': readyForProfileUpdate,
      'blockers': blockers,
      'target': target.toJson(),
      'metrics': metrics.toJson(),
      'probeMetadataPatch': metadataPatch,
      'watchSignals': watchSignals,
      'improvements': improvements,
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Personal Eval Profile Handoff')
      ..writeln()
      ..writeln('- Label: `$label`')
      ..writeln('- Result: `$result`')
      ..writeln('- Action: `$action`')
      ..writeln('- Ready for profile update: `$readyForProfileUpdate`')
      ..writeln('- Profile id: `${target.profileId ?? 'unknown'}`')
      ..writeln('- Provider: `${target.provider}`')
      ..writeln('- Base URL: `${target.baseUrl ?? 'unknown'}`')
      ..writeln('- Model: `${target.model ?? 'unknown'}`')
      ..writeln('- Suite report: `$suiteReportPath`')
      ..writeln()
      ..writeln('## Metrics')
      ..writeln()
      ..writeln('- Cases: `${metrics.caseCount}`')
      ..writeln(
        '- Incumbent pass rate: `${_percent(metrics.incumbentPassRate)}`',
      )
      ..writeln(
        '- Candidate pass rate: `${_percent(metrics.candidatePassRate)}`',
      )
      ..writeln('- Hard regressions: `${metrics.hardRegressionCount}`')
      ..writeln('- Watch signals: `${metrics.watchSignalCount}`')
      ..writeln('- Improvements: `${metrics.improvementCount}`');

    _writeList(buffer, 'Blockers', blockers);
    _writeList(buffer, 'Watch Signals', watchSignals);
    _writeList(buffer, 'Improvements', improvements);

    buffer
      ..writeln()
      ..writeln('## Metadata Patch')
      ..writeln()
      ..writeln('| Key | Value |')
      ..writeln('|-----|-------|');
    for (final entry in metadataPatch.entries) {
      buffer.writeln(
        '| ${_tableCell(entry.key)} | ${_tableCell(entry.value)} |',
      );
    }
    return buffer.toString();
  }
}

final class PersonalEvalProfileTarget {
  const PersonalEvalProfileTarget({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.profileId,
  });

  final String provider;
  final String? baseUrl;
  final String? model;
  final String? profileId;

  bool get isComplete =>
      _trimToNull(provider) != null &&
      _trimToNull(baseUrl) != null &&
      _trimToNull(model) != null &&
      _trimToNull(profileId) != null;

  factory PersonalEvalProfileTarget.fromReport(
    PersonalEvalSuiteReportSnapshot report, {
    String? profileId,
    String? provider,
    String? baseUrl,
    String? model,
  }) {
    final normalizedProvider = _trimToNull(provider) ?? _defaultProvider;
    final normalizedBaseUrl = _trimToNull(baseUrl) ?? report.candidateBaseUrl;
    final normalizedModel = _trimToNull(model) ?? report.candidateModel;
    return PersonalEvalProfileTarget(
      provider: normalizedProvider,
      baseUrl: normalizedBaseUrl,
      model: normalizedModel,
      profileId:
          _trimToNull(profileId) ??
          _buildProfileId(
            provider: normalizedProvider,
            baseUrl: normalizedBaseUrl,
            model: normalizedModel,
          ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      if (baseUrl != null) 'baseUrl': baseUrl,
      if (model != null) 'model': model,
      if (profileId != null) 'profileId': profileId,
    };
  }
}

final class PersonalEvalProfileHandoffMetrics {
  const PersonalEvalProfileHandoffMetrics({
    required this.caseCount,
    required this.incumbentPassRate,
    required this.candidatePassRate,
    required this.hardRegressionCount,
    required this.watchSignalCount,
    required this.improvementCount,
  });

  final int caseCount;
  final double incumbentPassRate;
  final double candidatePassRate;
  final int hardRegressionCount;
  final int watchSignalCount;
  final int improvementCount;

  factory PersonalEvalProfileHandoffMetrics.fromReport(
    PersonalEvalSuiteReportSnapshot report,
  ) {
    return PersonalEvalProfileHandoffMetrics(
      caseCount: report.caseCount,
      incumbentPassRate: report.incumbentPassRate,
      candidatePassRate: report.candidatePassRate,
      hardRegressionCount: report.hardRegressionCount,
      watchSignalCount: report.watchSignalCount,
      improvementCount: report.improvementCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caseCount': caseCount,
      'incumbentPassRate': incumbentPassRate,
      'candidatePassRate': candidatePassRate,
      'hardRegressionCount': hardRegressionCount,
      'watchSignalCount': watchSignalCount,
      'improvementCount': improvementCount,
    };
  }
}

final class PersonalEvalSuiteReportSnapshot {
  const PersonalEvalSuiteReportSnapshot({
    required this.generatedAt,
    required this.label,
    required this.result,
    required this.recommendation,
    required this.hardRegressionCount,
    required this.watchSignalCount,
    required this.improvementCount,
    required this.incumbentPassRate,
    required this.candidatePassRate,
    required this.candidateModel,
    required this.candidateBaseUrl,
    required this.entries,
  });

  final String generatedAt;
  final String label;
  final String result;
  final String recommendation;
  final int hardRegressionCount;
  final int watchSignalCount;
  final int improvementCount;
  final double incumbentPassRate;
  final double candidatePassRate;
  final String? candidateModel;
  final String? candidateBaseUrl;
  final List<PersonalEvalSuiteEntrySnapshot> entries;

  int get caseCount => entries.length;

  Iterable<String> get watchSignals sync* {
    for (final entry in entries) {
      for (final signal in entry.watchSignals) {
        yield '${entry.caseId}: $signal';
      }
    }
  }

  Iterable<String> get improvements sync* {
    for (final entry in entries) {
      for (final improvement in entry.improvements) {
        yield '${entry.caseId}: $improvement';
      }
    }
  }

  factory PersonalEvalSuiteReportSnapshot.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final schemaName = _asString(json['schemaName']);
    if (schemaName != _suiteReportSchemaName) {
      throw FormatException(
        'Invalid personal eval suite report schema in $path.',
      );
    }
    final incumbent = _asStringMap(json['incumbent']);
    final candidate = _asStringMap(json['candidate']);
    final rawEntries = _asList(json['entries']);
    final entries = <PersonalEvalSuiteEntrySnapshot>[];
    for (final rawEntry in rawEntries) {
      final entryJson = _asStringMap(rawEntry);
      if (entryJson == null) {
        throw FormatException('Invalid suite report entry in $path.');
      }
      entries.add(PersonalEvalSuiteEntrySnapshot.fromJson(entryJson));
    }
    if (incumbent == null || candidate == null) {
      throw FormatException('Incomplete personal eval suite report in $path.');
    }
    return PersonalEvalSuiteReportSnapshot(
      generatedAt: _requiredString(json, 'generatedAt', path),
      label: _requiredString(json, 'label', path),
      result: _requiredString(json, 'result', path),
      recommendation: _requiredString(json, 'recommendation', path),
      hardRegressionCount: _asNonNegativeInt(json['hardRegressionCount']) ?? 0,
      watchSignalCount: _asNonNegativeInt(json['watchSignalCount']) ?? 0,
      improvementCount: _asNonNegativeInt(json['improvementCount']) ?? 0,
      incumbentPassRate: _asDouble(incumbent['passRate']) ?? 0,
      candidatePassRate: _asDouble(candidate['passRate']) ?? 0,
      candidateModel: _trimToNull(_asString(candidate['model'])),
      candidateBaseUrl: _trimToNull(_asString(candidate['baseUrl'])),
      entries: List.unmodifiable(entries),
    );
  }
}

final class PersonalEvalSuiteEntrySnapshot {
  const PersonalEvalSuiteEntrySnapshot({
    required this.caseId,
    required this.watchSignals,
    required this.improvements,
  });

  final String caseId;
  final List<String> watchSignals;
  final List<String> improvements;

  factory PersonalEvalSuiteEntrySnapshot.fromJson(Map<String, dynamic> json) {
    return PersonalEvalSuiteEntrySnapshot(
      caseId: _asString(json['caseId']) ?? 'unknown',
      watchSignals: _stringList(json['watchSignals']),
      improvements: _stringList(json['improvements']),
    );
  }
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  final decoded = jsonDecode(await file.readAsString());
  final object = _asStringMap(decoded);
  if (object == null) {
    throw FormatException('Expected a JSON object in ${file.path}.');
  }
  return object;
}

String? _buildProfileId({
  required String provider,
  required String? baseUrl,
  required String? model,
}) {
  final normalizedBaseUrl = _trimToNull(baseUrl);
  final normalizedModel = _trimToNull(model);
  if (normalizedBaseUrl == null || normalizedModel == null) {
    return null;
  }
  final endpoint = provider == 'appleFoundationModels'
      ? 'apple-foundation-models://local'
      : normalizedBaseUrl.toLowerCase();
  return '$provider|$endpoint|$normalizedModel';
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

List<String> _stringList(Object? value) {
  return _asList(value)
      .map(_asString)
      .nonNulls
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _asString(Object? value) => value is String ? value : null;

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = _trimToNull(_asString(json[key]));
  if (value == null) {
    throw FormatException('Missing `$key` in $path.');
  }
  return value;
}

int? _asNonNegativeInt(Object? value) {
  if (value is int && value >= 0) {
    return value;
  }
  return null;
}

double? _asDouble(Object? value) {
  if (value is int) {
    return value.toDouble();
  }
  if (value is double) {
    return value;
  }
  return null;
}

void _writeList(StringBuffer buffer, String title, List<String> values) {
  buffer
    ..writeln()
    ..writeln('## $title')
    ..writeln();
  if (values.isEmpty) {
    buffer.writeln('- None');
    return;
  }
  for (final value in values) {
    buffer.writeln('- $value');
  }
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
