import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

part 'll37_routine_history_export_json.dart';
part 'll37_routine_history_export_support.dart';

const _selectionSchemaName = 'caverno_ll37_routine_history_selection';
const _caseSchemaName = 'caverno_ll37_verifier_fidelity_case';
const _manifestSchemaName = 'caverno_personal_eval_case_manifest';
const _selectionSchemaVersion = 1;
const _caseSchemaVersion = 2;
const _manifestSchemaVersion = 1;

Future<void> main(List<String> args) async {
  try {
    final options = Ll37RoutineHistoryExportOptions.parse(args);
    if (options.showHelp) {
      stdout.writeln(Ll37RoutineHistoryExportOptions.usage);
      return;
    }
    final result = await exportLl37RoutineHistoryEvidence(
      routinesFile: File(options.routinesPath!),
      selectionFile: File(options.selectionPath!),
      outputDirectory: Directory(options.outputDirectoryPath!),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) stderr.writeln(error.path);
    exitCode = 66;
  }
}

Future<Ll37RoutineHistoryExportResult> exportLl37RoutineHistoryEvidence({
  required File routinesFile,
  required File selectionFile,
  required Directory outputDirectory,
  DateTime? generatedAt,
}) async {
  final routines = _decodeObjectList(
    await routinesFile.readAsString(),
    routinesFile.path,
  );
  final selection = _RoutineHistorySelection.fromJson(
    _decodeObject(await selectionFile.readAsString(), selectionFile.path),
    selectionFile.path,
  );
  final routine = _findById(
    routines,
    selection.routineId,
    collectionName: 'routine',
  );
  final runs = _objectList(routine['runs'], 'routine runs');
  final correctRun = _findById(
    runs,
    selection.correctRunId,
    collectionName: 'routine run',
  );
  final brokenRun = _findById(
    runs,
    selection.brokenRunId,
    collectionName: 'routine run',
  );
  if (selection.correctRunId == selection.brokenRunId) {
    throw const FormatException('Routine evidence runs must be distinct.');
  }
  _validateRun(correctRun, label: 'candidate A');
  _validateRun(brokenRun, label: 'candidate B');
  final correctMechanical = _validatedMechanicalVerification(
    correctRun,
    label: 'candidate A',
  );
  final brokenMechanical = _validatedMechanicalVerification(
    brokenRun,
    label: 'candidate B',
  );
  if (correctMechanical.command != brokenMechanical.command) {
    throw const FormatException(
      'Routine evidence arms must use the same mechanical verification command.',
    );
  }

  final correctTools = _toolNames(correctRun);
  final brokenTools = _toolNames(brokenRun);
  final correctMissing = selection.requiredTools
      .where((tool) => !correctTools.contains(tool))
      .toList(growable: false);
  if (correctMissing.isNotEmpty) {
    throw FormatException(
      'Candidate A lacks required tools: ${correctMissing.join(', ')}.',
    );
  }
  if (selection.requiredTools.every(brokenTools.contains)) {
    throw const FormatException(
      'Candidate B must omit at least one required objective tool.',
    );
  }

  final redactor = _RoutineEvidenceRedactor.fromRuns(
    [correctRun, brokenRun],
    workspaceDirectory: _requiredString(
      routine,
      'workspaceDirectory',
      'routine',
    ),
  );
  final correctFiles = _changedFiles(correctRun, routine, redactor);
  if (correctFiles.isEmpty) {
    throw const FormatException(
      'Candidate A must contain a captured write_file mutation.',
    );
  }
  final pair = [
    _ExportCandidate(
      suffix: 'candidate-a',
      title: 'Recorded routine candidate A',
      expectedVerdict: 'not_refuted',
      run: correctRun,
      mechanicalVerification: correctMechanical,
      changedFiles: correctFiles,
    ),
    _ExportCandidate(
      suffix: 'candidate-b',
      title: 'Recorded routine candidate B',
      expectedVerdict: 'refuted',
      run: brokenRun,
      mechanicalVerification: brokenMechanical,
      changedFiles: _changedFiles(brokenRun, routine, redactor),
    ),
  ];
  final timestamp = (generatedAt ?? DateTime.now()).toUtc();

  if (outputDirectory.existsSync()) {
    throw FileSystemException(
      'Refusing to replace an existing evidence directory.',
      outputDirectory.path,
    );
  }
  await outputDirectory.parent.create(recursive: true);
  final stagedDirectory = await outputDirectory.parent.createTemp(
    '.ll37_routine_export_',
  );
  final casePaths = <String>[];
  try {
    for (final candidate in pair) {
      final caseId = '${selection.pairId}-${candidate.suffix}';
      final manifestName = '${candidate.suffix}_manifest.json';
      final caseName = '${candidate.suffix}_case.json';
      await _writeJson(
        File('${stagedDirectory.path}/$manifestName'),
        _manifestJson(
          caseId: caseId,
          title: candidate.title,
          routine: routine,
          run: candidate.run,
          mechanicalVerification: candidate.mechanicalVerification,
          expectedVerdict: candidate.expectedVerdict,
          generatedAt: timestamp,
          redactor: redactor,
        ),
      );
      await _writeJson(
        File('${stagedDirectory.path}/$caseName'),
        _caseJson(
          caseId: caseId,
          pairId: selection.pairId,
          title: candidate.title,
          expectedVerdict: candidate.expectedVerdict,
          manifestName: manifestName,
          acceptanceCriteria: selection.acceptanceCriteria
              .map(redactor.redact)
              .toList(growable: false),
          changedFiles: candidate.changedFiles,
          run: candidate.run,
          mechanicalVerification: candidate.mechanicalVerification,
          redactor: redactor,
        ),
      );
      casePaths.add('${outputDirectory.path}/$caseName');
    }
    await stagedDirectory.rename(outputDirectory.path);
  } catch (_) {
    if (stagedDirectory.existsSync()) {
      await stagedDirectory.delete(recursive: true);
    }
    rethrow;
  }
  return Ll37RoutineHistoryExportResult(
    pairId: selection.pairId,
    sourceSurface: 'routine',
    casePaths: casePaths,
  );
}
