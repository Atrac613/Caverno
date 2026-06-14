import 'dart:convert';
import 'dart:io';

import 'personal_eval_case_manifest.dart';
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
      '--out-dir PATH [--label LABEL] '
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
  );
  final reportJsonFile = File('${outDir.path}/personal_eval_suite_report.json');
  final reportMarkdownFile = File(
    '${outDir.path}/personal_eval_suite_report.md',
  );
  await _writeJsonFile(reportJsonFile, report.toJson());
  await reportMarkdownFile.writeAsString(report.toMarkdown());

  return PersonalEvalSuitePipelineResult(
    incumbentRun: incumbentRun,
    candidateRun: candidateRun,
    report: report,
    incumbentRunFile: incumbentRunFile,
    candidateRunFile: candidateRunFile,
    reportJsonFile: reportJsonFile,
    reportMarkdownFile: reportMarkdownFile,
  );
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
    required this.incumbentRunFile,
    required this.candidateRunFile,
    required this.reportJsonFile,
    required this.reportMarkdownFile,
  });

  final replay.PersonalEvalReplayRunArtifact incumbentRun;
  final replay.PersonalEvalReplayRunArtifact candidateRun;
  final suite.PersonalEvalSuiteReport report;
  final File incumbentRunFile;
  final File candidateRunFile;
  final File reportJsonFile;
  final File reportMarkdownFile;
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
