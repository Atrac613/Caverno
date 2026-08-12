import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'personal_eval_case_manifest.dart';
import 'personal_eval_experiment_protocol.dart' as protocol;
import 'personal_eval_profile_handoff.dart' as profile;
import 'personal_eval_replay_run.dart' as replay;
import 'personal_eval_suite_report.dart' as suite;

Future<void> main(List<String> args) async {
  final options = PersonalEvalSuitePipelineOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_suite_pipeline.dart '
      '--manifest PATH [--manifest PATH ...] '
      '--incumbent-label LABEL --candidate-label LABEL '
      '--incumbent-case-log CASE_ID=PATH '
      '--candidate-case-log CASE_ID=PATH '
      '--incumbent-verification-result CASE_ID=passed|failed|inconclusive '
      '--candidate-verification-result CASE_ID=passed|failed|inconclusive '
      '--protocol PATH --out-dir PATH [--label LABEL] '
      '[--incumbent-model MODEL] [--candidate-model MODEL] '
      '[--incumbent-base-url URL] [--candidate-base-url URL]',
    );
    exitCode = 64;
    return;
  }

  final PersonalEvalSuitePipelineResult result;
  try {
    result = await runPersonalEvalSuitePipeline(
      manifestFiles: options.manifestPaths.map(File.new).toList(),
      incumbent: PersonalEvalSuitePipelineRunInput(
        label: options.incumbentLabel,
        caseLogFiles: options.incumbentCaseLogPaths.map(
          (caseId, path) => MapEntry(caseId, File(path)),
        ),
        verificationResults: options.incumbentVerificationResults,
        model: options.incumbentModel,
        baseUrl: options.incumbentBaseUrl,
      ),
      candidate: PersonalEvalSuitePipelineRunInput(
        label: options.candidateLabel,
        caseLogFiles: options.candidateCaseLogPaths.map(
          (caseId, path) => MapEntry(caseId, File(path)),
        ),
        verificationResults: options.candidateVerificationResults,
        model: options.candidateModel,
        baseUrl: options.candidateBaseUrl,
      ),
      outDir: Directory(options.outDir),
      label: options.label,
      protocolFile: options.protocolPath == null
          ? null
          : File(options.protocolPath!),
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

  stdout.writeln(
    'Personal eval suite pipeline written to ${result.reportJsonFile.path}',
  );
  stdout.writeln(
    'Personal eval profile handoff written to '
    '${result.profileHandoffJsonFile.path}',
  );
  if (result.protocolJsonFile != null) {
    stdout.writeln(
      'Validated experiment protocol written to '
      '${result.protocolJsonFile!.path}',
    );
  }
  stdout.writeln(result.report.toMarkdown());

  if (!result.report.isSuccessful) {
    exitCode = 1;
  }
}

Future<PersonalEvalSuitePipelineResult> runPersonalEvalSuitePipeline({
  required List<File> manifestFiles,
  required PersonalEvalSuitePipelineRunInput incumbent,
  required PersonalEvalSuitePipelineRunInput candidate,
  required Directory outDir,
  String? label,
  DateTime? generatedAt,
  File? protocolFile,
}) async {
  if (manifestFiles.isEmpty) {
    throw const FormatException('At least one eval case manifest is required.');
  }

  await outDir.create(recursive: true);
  final timestamp = generatedAt ?? DateTime.now();
  final incumbentRun = await replay.buildPersonalEvalReplayRun(
    label: incumbent.label,
    manifestFiles: manifestFiles,
    caseLogFiles: incumbent.caseLogFiles,
    verificationResults: incumbent.verificationResults,
    model: incumbent.model,
    baseUrl: incumbent.baseUrl,
    generatedAt: timestamp,
  );
  final candidateRun = await replay.buildPersonalEvalReplayRun(
    label: candidate.label,
    manifestFiles: manifestFiles,
    caseLogFiles: candidate.caseLogFiles,
    verificationResults: candidate.verificationResults,
    model: candidate.model,
    baseUrl: candidate.baseUrl,
    generatedAt: timestamp,
  );

  suite.PersonalEvalExperimentProtocolProvenance? protocolProvenance;
  File? protocolJsonFile;
  File? protocolMarkdownFile;
  if (protocolFile != null) {
    final experimentProtocol = await protocol
        .buildPersonalEvalExperimentProtocol(
          configFile: protocolFile,
          generatedAt: timestamp,
        );
    _validateExperimentProtocol(
      experimentProtocol: experimentProtocol,
      incumbentRun: incumbentRun,
      candidateRun: candidateRun,
    );
    protocolJsonFile = File(
      '${outDir.path}/personal_eval_experiment_protocol.json',
    );
    protocolMarkdownFile = File(
      '${outDir.path}/personal_eval_experiment_protocol.md',
    );
    final canonicalProtocol =
        '${const JsonEncoder.withIndent('  ').convert(experimentProtocol.toJson())}\n';
    await protocolJsonFile.writeAsString(canonicalProtocol);
    await protocolMarkdownFile.writeAsString(experimentProtocol.toMarkdown());
    protocolProvenance = suite.PersonalEvalExperimentProtocolProvenance(
      path: protocolJsonFile.path,
      sha256: sha256.convert(utf8.encode(canonicalProtocol)).toString(),
      label: experimentProtocol.label,
      validationStatus: 'validated',
      studyIntent: experimentProtocol.studyIntent.jsonValue,
      minimumEffectTaskCount:
          experimentProtocol.decisionCriteria?.minimumEffectTaskCount,
      minimumHeldOutEffectTaskCount:
          experimentProtocol.decisionCriteria?.minimumHeldOutEffectTaskCount,
      validatedTrialCount: experimentProtocol.trialOrders.length,
      validatedExecutionEventCount: experimentProtocol.trialOrders.length * 2,
    );
  }

  final incumbentRunFile = File('${outDir.path}/incumbent_replay_run.json');
  final candidateRunFile = File('${outDir.path}/candidate_replay_run.json');
  await _writeJsonFile(incumbentRunFile, incumbentRun.toJson());
  await _writeJsonFile(candidateRunFile, candidateRun.toJson());

  final report = await suite.buildPersonalEvalSuiteReport(
    manifestFiles: manifestFiles,
    incumbentResultFile: incumbentRunFile,
    candidateResultFile: candidateRunFile,
    label: label,
    generatedAt: timestamp,
    experimentProtocol: protocolProvenance,
  );
  final reportJsonFile = File('${outDir.path}/personal_eval_suite_report.json');
  final reportMarkdownFile = File(
    '${outDir.path}/personal_eval_suite_report.md',
  );
  await _writeJsonFile(reportJsonFile, report.toJson());
  await reportMarkdownFile.writeAsString(report.toMarkdown());

  final profileHandoff = await profile.buildPersonalEvalProfileHandoff(
    suiteReportFile: reportJsonFile,
    generatedAt: timestamp,
  );
  final profileHandoffJsonFile = File(
    '${outDir.path}/personal_eval_profile_handoff.json',
  );
  final profileHandoffMarkdownFile = File(
    '${outDir.path}/personal_eval_profile_handoff.md',
  );
  await _writeJsonFile(profileHandoffJsonFile, profileHandoff.toJson());
  await profileHandoffMarkdownFile.writeAsString(profileHandoff.toMarkdown());

  return PersonalEvalSuitePipelineResult(
    incumbentRun: incumbentRun,
    candidateRun: candidateRun,
    report: report,
    profileHandoff: profileHandoff,
    incumbentRunFile: incumbentRunFile,
    candidateRunFile: candidateRunFile,
    reportJsonFile: reportJsonFile,
    reportMarkdownFile: reportMarkdownFile,
    profileHandoffJsonFile: profileHandoffJsonFile,
    profileHandoffMarkdownFile: profileHandoffMarkdownFile,
    protocolJsonFile: protocolJsonFile,
    protocolMarkdownFile: protocolMarkdownFile,
  );
}

void _validateExperimentProtocol({
  required protocol.PersonalEvalExperimentProtocol experimentProtocol,
  required replay.PersonalEvalReplayRunArtifact incumbentRun,
  required replay.PersonalEvalReplayRunArtifact candidateRun,
}) {
  _validateProtocolRun(
    role: protocol.PersonalEvalModelRole.incumbent,
    expected: experimentProtocol.incumbent,
    run: incumbentRun,
    experimentProtocol: experimentProtocol,
  );
  _validateProtocolRun(
    role: protocol.PersonalEvalModelRole.candidate,
    expected: experimentProtocol.candidate,
    run: candidateRun,
    experimentProtocol: experimentProtocol,
  );

  final observedEvents = <_ObservedProtocolExecution>[];
  final incumbentByKey = {
    for (final entry in incumbentRun.cases)
      '${entry.caseId}#${entry.trialId}': entry,
  };
  final candidateByKey = {
    for (final entry in candidateRun.cases)
      '${entry.caseId}#${entry.trialId}': entry,
  };
  for (final order in experimentProtocol.trialOrders) {
    observedEvents
      ..add(
        _ObservedProtocolExecution(
          trialKey: order.trialKey,
          role: protocol.PersonalEvalModelRole.incumbent,
          startedAt: incumbentByKey[order.trialKey]!.startedAt!,
        ),
      )
      ..add(
        _ObservedProtocolExecution(
          trialKey: order.trialKey,
          role: protocol.PersonalEvalModelRole.candidate,
          startedAt: candidateByKey[order.trialKey]!.startedAt!,
        ),
      );
  }
  observedEvents.sort(
    (left, right) => left.startedAt.compareTo(right.startedAt),
  );
  for (var index = 1; index < observedEvents.length; index += 1) {
    if (observedEvents[index - 1].startedAt ==
        observedEvents[index].startedAt) {
      throw FormatException(
        'Protocol execution order is ambiguous at '
        '${observedEvents[index].startedAt.toIso8601String()}.',
      );
    }
  }
  final expectedEvents = <_ExpectedProtocolExecution>[
    for (final order in experimentProtocol.trialOrders) ...[
      _ExpectedProtocolExecution(trialKey: order.trialKey, role: order.first),
      _ExpectedProtocolExecution(trialKey: order.trialKey, role: order.second),
    ],
  ];
  for (var index = 0; index < expectedEvents.length; index += 1) {
    final expected = expectedEvents[index];
    final observed = observedEvents[index];
    if (expected.trialKey != observed.trialKey ||
        expected.role != observed.role) {
      throw FormatException(
        'Protocol execution order mismatch at position ${index + 1}: '
        'expected ${expected.trialKey}/${expected.role.jsonValue}, observed '
        '${observed.trialKey}/${observed.role.jsonValue}.',
      );
    }
  }
}

void _validateProtocolRun({
  required protocol.PersonalEvalModelRole role,
  required protocol.PersonalEvalProtocolModel expected,
  required replay.PersonalEvalReplayRunArtifact run,
  required protocol.PersonalEvalExperimentProtocol experimentProtocol,
}) {
  if (run.model != expected.model) {
    throw FormatException(
      'Protocol ${role.jsonValue} model mismatch: expected '
      '${expected.model}, observed ${run.model ?? 'missing'}.',
    );
  }
  if (expected.baseUrl != null && run.baseUrl != expected.baseUrl) {
    throw FormatException(
      'Protocol ${role.jsonValue} base URL mismatch: expected '
      '${expected.baseUrl}, observed ${run.baseUrl ?? 'missing'}.',
    );
  }

  final expectedKeys = experimentProtocol.trialOrders
      .map((order) => order.trialKey)
      .toSet();
  final observedKeys = run.cases
      .map((entry) => '${entry.caseId}#${entry.trialId}')
      .toSet();
  final missing = expectedKeys.difference(observedKeys).toList()..sort();
  final unexpected = observedKeys.difference(expectedKeys).toList()..sort();
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    throw FormatException(
      'Protocol ${role.jsonValue} trial set mismatch: '
      'missing=${missing.join(',')}, unexpected=${unexpected.join(',')}.',
    );
  }

  for (final entry in run.cases) {
    final trialKey = '${entry.caseId}#${entry.trialId}';
    if (entry.startedAt == null) {
      throw FormatException(
        'Protocol ${role.jsonValue} trial $trialKey has no observable start time.',
      );
    }
    final budget = experimentProtocol.executionBudget;
    if (entry.durationMs > budget.maxDurationMs ||
        entry.turnCount > budget.maxTurns ||
        entry.toolCallCount > budget.maxToolCalls) {
      throw FormatException(
        'Protocol ${role.jsonValue} trial $trialKey exceeded its execution budget.',
      );
    }
  }
}

final class _ExpectedProtocolExecution {
  const _ExpectedProtocolExecution({
    required this.trialKey,
    required this.role,
  });

  final String trialKey;
  final protocol.PersonalEvalModelRole role;
}

final class _ObservedProtocolExecution {
  const _ObservedProtocolExecution({
    required this.trialKey,
    required this.role,
    required this.startedAt,
  });

  final String trialKey;
  final protocol.PersonalEvalModelRole role;
  final DateTime startedAt;
}

Future<void> _writeJsonFile(File file, Map<String, dynamic> json) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
}

final class PersonalEvalSuitePipelineRunInput {
  const PersonalEvalSuitePipelineRunInput({
    required this.label,
    required this.caseLogFiles,
    required this.verificationResults,
    this.model,
    this.baseUrl,
  });

  final String label;
  final Map<String, File> caseLogFiles;
  final Map<String, PersonalEvalVerificationResult> verificationResults;
  final String? model;
  final String? baseUrl;
}

final class PersonalEvalSuitePipelineResult {
  const PersonalEvalSuitePipelineResult({
    required this.incumbentRun,
    required this.candidateRun,
    required this.report,
    required this.profileHandoff,
    required this.incumbentRunFile,
    required this.candidateRunFile,
    required this.reportJsonFile,
    required this.reportMarkdownFile,
    required this.profileHandoffJsonFile,
    required this.profileHandoffMarkdownFile,
    required this.protocolJsonFile,
    required this.protocolMarkdownFile,
  });

  final replay.PersonalEvalReplayRunArtifact incumbentRun;
  final replay.PersonalEvalReplayRunArtifact candidateRun;
  final suite.PersonalEvalSuiteReport report;
  final profile.PersonalEvalProfileHandoff profileHandoff;
  final File incumbentRunFile;
  final File candidateRunFile;
  final File reportJsonFile;
  final File reportMarkdownFile;
  final File profileHandoffJsonFile;
  final File profileHandoffMarkdownFile;
  final File? protocolJsonFile;
  final File? protocolMarkdownFile;
}

final class PersonalEvalSuitePipelineOptions {
  const PersonalEvalSuitePipelineOptions({
    required this.manifestPaths,
    required this.incumbentLabel,
    required this.candidateLabel,
    required this.incumbentCaseLogPaths,
    required this.candidateCaseLogPaths,
    required this.incumbentVerificationResults,
    required this.candidateVerificationResults,
    required this.outDir,
    this.label,
    this.incumbentModel,
    this.candidateModel,
    this.incumbentBaseUrl,
    this.candidateBaseUrl,
    this.protocolPath,
  });

  final List<String> manifestPaths;
  final String incumbentLabel;
  final String candidateLabel;
  final Map<String, String> incumbentCaseLogPaths;
  final Map<String, String> candidateCaseLogPaths;
  final Map<String, PersonalEvalVerificationResult>
  incumbentVerificationResults;
  final Map<String, PersonalEvalVerificationResult>
  candidateVerificationResults;
  final String outDir;
  final String? label;
  final String? incumbentModel;
  final String? candidateModel;
  final String? incumbentBaseUrl;
  final String? candidateBaseUrl;
  final String? protocolPath;

  static PersonalEvalSuitePipelineOptions? parse(List<String> args) {
    final manifests = <String>[];
    String? incumbentLabel;
    String? candidateLabel;
    final incumbentCaseLogs = <String, String>{};
    final candidateCaseLogs = <String, String>{};
    final incumbentVerificationResults =
        <String, PersonalEvalVerificationResult>{};
    final candidateVerificationResults =
        <String, PersonalEvalVerificationResult>{};
    String? outDir;
    String? label;
    String? incumbentModel;
    String? candidateModel;
    String? incumbentBaseUrl;
    String? candidateBaseUrl;
    String? protocolPath;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--manifest':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          manifests.add(value);
        case '--incumbent-label':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          incumbentLabel = value;
        case '--candidate-label':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          candidateLabel = value;
        case '--incumbent-case-log':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = _parseKeyValue(value);
          if (parsed == null) return null;
          incumbentCaseLogs[parsed.key] = parsed.value;
        case '--candidate-case-log':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = _parseKeyValue(value);
          if (parsed == null) return null;
          candidateCaseLogs[parsed.key] = parsed.value;
        case '--incumbent-verification-result':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = _parseVerificationResult(value);
          if (parsed == null) return null;
          incumbentVerificationResults[parsed.key] = parsed.value;
        case '--candidate-verification-result':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = _parseVerificationResult(value);
          if (parsed == null) return null;
          candidateVerificationResults[parsed.key] = parsed.value;
        case '--out-dir':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          outDir = value;
        case '--label':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          label = value;
        case '--incumbent-model':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          incumbentModel = value;
        case '--candidate-model':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          candidateModel = value;
        case '--incumbent-base-url':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          incumbentBaseUrl = value;
        case '--candidate-base-url':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          candidateBaseUrl = value;
        case '--protocol':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          protocolPath = value;
        default:
          return null;
      }
    }

    if (manifests.isEmpty ||
        incumbentLabel == null ||
        candidateLabel == null ||
        incumbentCaseLogs.isEmpty ||
        candidateCaseLogs.isEmpty ||
        incumbentVerificationResults.isEmpty ||
        candidateVerificationResults.isEmpty ||
        protocolPath == null ||
        outDir == null) {
      return null;
    }

    return PersonalEvalSuitePipelineOptions(
      manifestPaths: List.unmodifiable(manifests),
      incumbentLabel: incumbentLabel,
      candidateLabel: candidateLabel,
      incumbentCaseLogPaths: Map.unmodifiable(incumbentCaseLogs),
      candidateCaseLogPaths: Map.unmodifiable(candidateCaseLogs),
      incumbentVerificationResults: Map.unmodifiable(
        incumbentVerificationResults,
      ),
      candidateVerificationResults: Map.unmodifiable(
        candidateVerificationResults,
      ),
      outDir: outDir,
      label: label,
      incumbentModel: incumbentModel,
      candidateModel: candidateModel,
      incumbentBaseUrl: incumbentBaseUrl,
      candidateBaseUrl: candidateBaseUrl,
      protocolPath: protocolPath,
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

MapEntry<String, PersonalEvalVerificationResult>? _parseVerificationResult(
  String value,
) {
  final parsed = _parseKeyValue(value);
  if (parsed == null) {
    return null;
  }
  final result = PersonalEvalVerificationResult.parse(parsed.value);
  if (result == null) {
    return null;
  }
  return MapEntry(parsed.key, result);
}

MapEntry<String, String>? _parseKeyValue(String value) {
  final separator = value.indexOf('=');
  if (separator <= 0 || separator == value.length - 1) {
    return null;
  }
  final key = value.substring(0, separator).trim();
  final parsedValue = value.substring(separator + 1).trim();
  if (key.isEmpty || parsedValue.isEmpty) {
    return null;
  }
  return MapEntry(key, parsedValue);
}
