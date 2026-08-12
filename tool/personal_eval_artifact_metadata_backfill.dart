import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_authored_corpus.dart';
import 'package:crypto/crypto.dart';

import 'personal_eval_experiment_protocol.dart' as protocol;
import 'personal_eval_profile_handoff.dart' as profile;
import 'personal_eval_suite_report.dart' as suite;

const _replaySchemaName = 'caverno_personal_eval_replay_run';
const _replaySchemaVersion = 5;
const _reportFileName = 'personal_eval_suite_report.json';
const _protocolFileName = 'personal_eval_experiment_protocol.json';
const _incumbentFileName = 'incumbent_replay_run.json';
const _candidateFileName = 'candidate_replay_run.json';

Future<void> main(List<String> args) async {
  final options = PersonalEvalArtifactMetadataBackfillOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_artifact_metadata_backfill.dart '
      '--corpus PATH --suite-dir PATH --out-dir PATH',
    );
    exitCode = 64;
    return;
  }

  try {
    final result = await backfillPersonalEvalArtifactMetadata(
      corpusFile: File(options.corpusPath),
      sourceSuiteDirectory: Directory(options.suiteDirectoryPath),
      outputDirectory: Directory(options.outputDirectoryPath),
    );
    stdout.writeln(
      'Personal eval metadata backfill written to ${result.outputDirectory.path}',
    );
    stdout.writeln(
      'Backfilled ${result.caseCount} cases and ${result.executionCount} '
      'replay executions '
      'without changing scored outcomes.',
    );
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) stderr.writeln(error.path);
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  }
}

Future<PersonalEvalArtifactMetadataBackfillResult>
backfillPersonalEvalArtifactMetadata({
  required File corpusFile,
  required Directory sourceSuiteDirectory,
  required Directory outputDirectory,
  DateTime? generatedAt,
}) async {
  if (!corpusFile.existsSync()) {
    throw FileSystemException(
      'Authored corpus file not found.',
      corpusFile.path,
    );
  }
  if (!sourceSuiteDirectory.existsSync()) {
    throw FileSystemException(
      'Source suite directory not found.',
      sourceSuiteDirectory.path,
    );
  }
  if (sourceSuiteDirectory.absolute.path == outputDirectory.absolute.path) {
    throw const FormatException(
      'Output directory must differ from the source suite directory.',
    );
  }
  final sourceReportFile = File(
    '${sourceSuiteDirectory.path}/$_reportFileName',
  );
  final sourceProtocolFile = File(
    '${sourceSuiteDirectory.path}/$_protocolFileName',
  );
  final sourceIncumbentFile = File(
    '${sourceSuiteDirectory.path}/$_incumbentFileName',
  );
  final sourceCandidateFile = File(
    '${sourceSuiteDirectory.path}/$_candidateFileName',
  );
  for (final file in [
    sourceReportFile,
    sourceProtocolFile,
    sourceIncumbentFile,
    sourceCandidateFile,
  ]) {
    if (!file.existsSync()) {
      throw FileSystemException('Source suite artifact not found.', file.path);
    }
  }

  final corpus = PersonalEvalAuthoredCorpus.parse(
    await corpusFile.readAsString(),
  );
  final metadataByCaseId = {
    for (final evalCase in corpus.cases)
      evalCase.caseId: _CaseMetadata(
        split: evalCase.split.name,
        tier: evalCase.tier,
        promptStyle: evalCase.promptStyle.name,
      ),
  };
  final sourceReport = await _readJsonObject(sourceReportFile);
  _requireValidatedProtocol(sourceReport, sourceReportFile.path);
  final rawManifestPaths = sourceReport['manifestPaths'];
  if (rawManifestPaths is! List || rawManifestPaths.isEmpty) {
    throw FormatException(
      'Source suite report has no manifest paths: ${sourceReportFile.path}',
    );
  }

  await outputDirectory.create(recursive: true);
  final manifestDirectory = Directory('${outputDirectory.path}/manifests');
  await manifestDirectory.create(recursive: true);
  final outputManifests = <File>[];
  for (final rawPath in rawManifestPaths) {
    if (rawPath is! String || rawPath.trim().isEmpty) {
      throw FormatException(
        'Source suite report contains an invalid manifest path.',
      );
    }
    final sourceManifestFile = File(rawPath);
    final manifest = await _readJsonObject(sourceManifestFile);
    final caseId = _requiredString(manifest, 'caseId', sourceManifestFile.path);
    final metadata = metadataByCaseId[caseId];
    if (metadata == null) {
      throw FormatException(
        'Authored corpus has no metadata for source case $caseId.',
      );
    }
    _applyMetadata(
      target: manifest,
      metadata: metadata,
      path: sourceManifestFile.path,
    );
    final outputManifest = File(
      '${manifestDirectory.path}/$caseId.case_manifest.json',
    );
    await _writeJsonObject(outputManifest, manifest);
    outputManifests.add(outputManifest);
  }

  final outputIncumbentFile = File(
    '${outputDirectory.path}/$_incumbentFileName',
  );
  final outputCandidateFile = File(
    '${outputDirectory.path}/$_candidateFileName',
  );
  final incumbent = await _backfillReplayRun(
    source: sourceIncumbentFile,
    output: outputIncumbentFile,
    metadataByCaseId: metadataByCaseId,
    manifestPaths: outputManifests.map((file) => file.path).toList(),
  );
  final candidate = await _backfillReplayRun(
    source: sourceCandidateFile,
    output: outputCandidateFile,
    metadataByCaseId: metadataByCaseId,
    manifestPaths: outputManifests.map((file) => file.path).toList(),
  );
  _validateTrialKeys(incumbent, candidate);

  final sourceProtocol = await _readJsonObject(sourceProtocolFile);
  final protocolConfig = Map<String, dynamic>.from(sourceProtocol)
    ..['schemaVersion'] = 2
    ..['studyIntent'] = 'corpus_design'
    ..remove('decisionCriteria');
  final protocolConfigFile = File(
    '${outputDirectory.path}/protocol_config.json',
  );
  await _writeJsonObject(protocolConfigFile, protocolConfig);
  final experimentProtocol = await protocol.buildPersonalEvalExperimentProtocol(
    configFile: protocolConfigFile,
    generatedAt: generatedAt,
  );
  _validateProtocolTrialKeys(experimentProtocol, incumbent, candidate);
  final canonicalProtocol =
      '${const JsonEncoder.withIndent('  ').convert(experimentProtocol.toJson())}\n';
  final outputProtocolFile = File('${outputDirectory.path}/$_protocolFileName');
  await outputProtocolFile.writeAsString(canonicalProtocol);
  await File(
    '${outputDirectory.path}/personal_eval_experiment_protocol.md',
  ).writeAsString(experimentProtocol.toMarkdown());

  final reportTimestamp = generatedAt ?? _sourceGeneratedAt(sourceReport);
  final report = await suite.buildPersonalEvalSuiteReport(
    manifestFiles: outputManifests,
    incumbentResultFile: outputIncumbentFile,
    candidateResultFile: outputCandidateFile,
    label: sourceReport['label'] as String?,
    generatedAt: reportTimestamp,
    experimentProtocol: suite.PersonalEvalExperimentProtocolProvenance(
      path: outputProtocolFile.path,
      sha256: sha256.convert(utf8.encode(canonicalProtocol)).toString(),
      label: experimentProtocol.label,
      validationStatus: 'validated',
      studyIntent: experimentProtocol.studyIntent.jsonValue,
      minimumEffectTaskCount: null,
      minimumHeldOutEffectTaskCount: null,
      validatedTrialCount: experimentProtocol.trialOrders.length,
      validatedExecutionEventCount: experimentProtocol.trialOrders.length * 2,
    ),
  );
  _validateOutcomeFingerprint(sourceReport, report.toJson());

  final reportFile = File('${outputDirectory.path}/$_reportFileName');
  await _writeJsonObject(reportFile, report.toJson());
  await File(
    '${outputDirectory.path}/personal_eval_suite_report.md',
  ).writeAsString(report.toMarkdown());
  final handoff = await profile.buildPersonalEvalProfileHandoff(
    suiteReportFile: reportFile,
    generatedAt: reportTimestamp,
  );
  await _writeJsonObject(
    File('${outputDirectory.path}/personal_eval_profile_handoff.json'),
    handoff.toJson(),
  );
  await File(
    '${outputDirectory.path}/personal_eval_profile_handoff.md',
  ).writeAsString(handoff.toMarkdown());

  return PersonalEvalArtifactMetadataBackfillResult(
    outputDirectory: outputDirectory,
    reportFile: reportFile,
    caseCount: outputManifests.length,
    executionCount:
        (incumbent['cases'] as List).length +
        (candidate['cases'] as List).length,
  );
}

Future<Map<String, dynamic>> _backfillReplayRun({
  required File source,
  required File output,
  required Map<String, _CaseMetadata> metadataByCaseId,
  required List<String> manifestPaths,
}) async {
  final run = await _readJsonObject(source);
  if (run['schemaName'] != _replaySchemaName) {
    throw FormatException('Invalid replay schema in ${source.path}.');
  }
  final cases = run['cases'];
  if (cases is! List || cases.isEmpty) {
    throw FormatException('Replay run has no cases: ${source.path}');
  }
  for (final rawCase in cases) {
    if (rawCase is! Map<String, dynamic>) {
      throw FormatException('Replay run has an invalid case: ${source.path}');
    }
    final caseId = _requiredString(rawCase, 'caseId', source.path);
    final metadata = metadataByCaseId[caseId];
    if (metadata == null) {
      throw FormatException('Authored corpus has no metadata for $caseId.');
    }
    _applyMetadata(target: rawCase, metadata: metadata, path: source.path);
  }
  run
    ..['schemaVersion'] = _replaySchemaVersion
    ..['manifestPaths'] = manifestPaths;
  await _writeJsonObject(output, run);
  return run;
}

void _applyMetadata({
  required Map<String, dynamic> target,
  required _CaseMetadata metadata,
  required String path,
}) {
  final caseId = _requiredString(target, 'caseId', path);
  final existingSplit = target['split'];
  if (existingSplit != null && existingSplit != metadata.split) {
    throw FormatException(
      'Split conflict for $caseId in $path: expected ${metadata.split}, '
      'got $existingSplit.',
    );
  }
  final existingTier = target['tier'];
  if (existingTier != null && existingTier != metadata.tier) {
    throw FormatException(
      'Tier conflict for $caseId in $path: expected ${metadata.tier}, '
      'got $existingTier.',
    );
  }
  final existingPromptStyle = target['promptStyle'];
  if (existingPromptStyle != null &&
      existingPromptStyle != metadata.promptStyle) {
    throw FormatException(
      'Prompt-style conflict for $caseId in $path: expected '
      '${metadata.promptStyle}, got $existingPromptStyle.',
    );
  }
  target
    ..['tier'] = metadata.tier
    ..['promptStyle'] = metadata.promptStyle;
}

void _requireValidatedProtocol(Map<String, dynamic> report, String path) {
  final provenance = report['experimentProtocol'];
  if (provenance is! Map<String, dynamic> ||
      provenance['validationStatus'] != 'validated') {
    throw FormatException(
      'Source suite report must carry validated protocol provenance: $path',
    );
  }
}

void _validateTrialKeys(
  Map<String, dynamic> incumbent,
  Map<String, dynamic> candidate,
) {
  final incumbentKeys = _trialKeys(incumbent);
  final candidateKeys = _trialKeys(candidate);
  if (incumbentKeys.length != candidateKeys.length ||
      !incumbentKeys.containsAll(candidateKeys)) {
    throw const FormatException(
      'Incumbent and candidate replay trial keys do not match.',
    );
  }
}

void _validateProtocolTrialKeys(
  protocol.PersonalEvalExperimentProtocol experimentProtocol,
  Map<String, dynamic> incumbent,
  Map<String, dynamic> candidate,
) {
  final expected = experimentProtocol.trialOrders
      .map((order) => order.trialKey)
      .toSet();
  for (final entry in [incumbent, candidate]) {
    final actual = _trialKeys(entry);
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw const FormatException(
        'Replay trial keys do not match the experiment protocol.',
      );
    }
  }
}

Set<String> _trialKeys(Map<String, dynamic> run) {
  final cases = run['cases'];
  if (cases is! List) return const {};
  return {
    for (final rawCase in cases)
      if (rawCase is Map<String, dynamic>)
        '${rawCase['caseId']}#${rawCase['trialId'] ?? 'trial-1'}',
  };
}

void _validateOutcomeFingerprint(
  Map<String, dynamic> sourceReport,
  Map<String, dynamic> outputReport,
) {
  const keys = ['hardRegressionCount', 'watchSignalCount', 'improvementCount'];
  for (final key in keys) {
    if (sourceReport[key] != outputReport[key]) {
      throw FormatException(
        'Metadata backfill changed scored outcome $key: '
        '${sourceReport[key]} -> ${outputReport[key]}.',
      );
    }
  }
  final sourceStatistics = sourceReport['pairedStatistics'];
  final outputStatistics = outputReport['pairedStatistics'];
  if (jsonEncode(sourceStatistics) != jsonEncode(outputStatistics)) {
    throw const FormatException(
      'Metadata backfill changed the paired statistics.',
    );
  }
}

DateTime _sourceGeneratedAt(Map<String, dynamic> report) {
  final raw = report['generatedAt'];
  final parsed = raw is String ? DateTime.tryParse(raw) : null;
  if (parsed == null) {
    throw const FormatException(
      'Source suite report has an invalid generatedAt value.',
    );
  }
  return parsed;
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  if (!file.existsSync()) {
    throw FileSystemException('JSON file not found.', file.path);
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in ${file.path}.');
  }
  return decoded;
}

Future<void> _writeJsonObject(File file, Map<String, dynamic> value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key in $path.');
  }
  return value.trim();
}

final class _CaseMetadata {
  const _CaseMetadata({
    required this.split,
    required this.tier,
    required this.promptStyle,
  });

  final String split;
  final int tier;
  final String promptStyle;
}

final class PersonalEvalArtifactMetadataBackfillResult {
  const PersonalEvalArtifactMetadataBackfillResult({
    required this.outputDirectory,
    required this.reportFile,
    required this.caseCount,
    required this.executionCount,
  });

  final Directory outputDirectory;
  final File reportFile;
  final int caseCount;
  final int executionCount;
}

final class PersonalEvalArtifactMetadataBackfillOptions {
  const PersonalEvalArtifactMetadataBackfillOptions({
    required this.corpusPath,
    required this.suiteDirectoryPath,
    required this.outputDirectoryPath,
  });

  final String corpusPath;
  final String suiteDirectoryPath;
  final String outputDirectoryPath;

  static PersonalEvalArtifactMetadataBackfillOptions? parse(List<String> args) {
    String? corpusPath;
    String? suiteDirectoryPath;
    String? outputDirectoryPath;
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      if (index + 1 >= args.length) return null;
      final value = args[++index];
      if (value.startsWith('--')) return null;
      switch (argument) {
        case '--corpus':
          corpusPath = value;
        case '--suite-dir':
          suiteDirectoryPath = value;
        case '--out-dir':
          outputDirectoryPath = value;
        default:
          return null;
      }
    }
    if (corpusPath == null ||
        suiteDirectoryPath == null ||
        outputDirectoryPath == null) {
      return null;
    }
    return PersonalEvalArtifactMetadataBackfillOptions(
      corpusPath: corpusPath,
      suiteDirectoryPath: suiteDirectoryPath,
      outputDirectoryPath: outputDirectoryPath,
    );
  }
}
