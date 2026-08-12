import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

part 'll37_worktree_agent_history_export_json.dart';
part 'll37_worktree_agent_history_export_support.dart';

const _selectionSchemaName = 'caverno_ll37_worktree_agent_history_selection';
const _caseSchemaName = 'caverno_ll37_verifier_fidelity_case';
const _manifestSchemaName = 'caverno_personal_eval_case_manifest';
const _selectionSchemaVersion = 1;
const _caseSchemaVersion = 2;
const _manifestSchemaVersion = 1;

Future<void> main(List<String> args) async {
  try {
    final options = Ll37WorktreeAgentHistoryExportOptions.parse(args);
    if (options.showHelp) {
      stdout.writeln(Ll37WorktreeAgentHistoryExportOptions.usage);
      return;
    }
    final result = await exportLl37WorktreeAgentHistoryEvidence(
      tasksFile: File(options.tasksPath!),
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

Future<Ll37WorktreeAgentHistoryExportResult>
exportLl37WorktreeAgentHistoryEvidence({
  required File tasksFile,
  required File selectionFile,
  required Directory outputDirectory,
  DateTime? generatedAt,
}) async {
  final tasks = _decodeObjectList(
    await tasksFile.readAsString(),
    tasksFile.path,
  );
  final selection = _WorktreeAgentHistorySelection.fromJson(
    _decodeObject(await selectionFile.readAsString(), selectionFile.path),
    selectionFile.path,
  );
  if (selection.correctTaskId == selection.brokenTaskId) {
    throw const FormatException(
      'Worktree-agent evidence tasks must be distinct.',
    );
  }

  final correctTask = _findById(tasks, selection.correctTaskId);
  final brokenTask = _findById(tasks, selection.brokenTaskId);
  _validateTask(correctTask, label: 'candidate A');
  _validateTask(brokenTask, label: 'candidate B');

  final correctPrompt = _requiredString(correctTask, 'prompt', 'candidate A');
  final brokenPrompt = _requiredString(brokenTask, 'prompt', 'candidate B');
  if (correctPrompt != brokenPrompt) {
    throw const FormatException(
      'Worktree-agent evidence tasks must share the same objective.',
    );
  }
  final correctCommand = _requiredString(
    correctTask,
    'verificationCommand',
    'candidate A',
  );
  final brokenCommand = _requiredString(
    brokenTask,
    'verificationCommand',
    'candidate B',
  );
  if (correctCommand != brokenCommand) {
    throw const FormatException(
      'Worktree-agent evidence tasks must share the verification command.',
    );
  }

  final redactor = _WorktreeAgentEvidenceRedactor.fromTasks([
    correctTask,
    brokenTask,
  ]);
  final correctFiles = _validatedChangedFiles(correctTask, redactor);
  final brokenFiles = _validatedChangedFiles(brokenTask, redactor);
  if (correctFiles.isEmpty) {
    throw const FormatException(
      'Candidate A must contain captured changed-file evidence.',
    );
  }

  final candidates = [
    _ExportCandidate(
      suffix: 'candidate-a',
      title: 'Recorded worktree-agent candidate A',
      expectedVerdict: 'not_refuted',
      captureProvenance: selection.correctCaptureProvenance,
      task: correctTask,
      changedFiles: correctFiles,
    ),
    _ExportCandidate(
      suffix: 'candidate-b',
      title: 'Recorded worktree-agent candidate B',
      expectedVerdict: 'refuted',
      captureProvenance: selection.brokenCaptureProvenance,
      task: brokenTask,
      changedFiles: brokenFiles,
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
    '.ll37_worktree_agent_export_',
  );
  final casePaths = <String>[];
  try {
    for (final candidate in candidates) {
      final caseId = '${selection.pairId}-${candidate.suffix}';
      final manifestName = '${candidate.suffix}_manifest.json';
      final caseName = '${candidate.suffix}_case.json';
      await _writeJson(
        File('${stagedDirectory.path}/$manifestName'),
        _manifestJson(
          caseId: caseId,
          title: candidate.title,
          task: candidate.task,
          expectedVerdict: candidate.expectedVerdict,
          evidenceClass: selection.evidenceClass,
          captureProvenance: candidate.captureProvenance,
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
          evidenceClass: selection.evidenceClass,
          captureProvenance: candidate.captureProvenance,
          manifestName: manifestName,
          acceptanceCriteria: selection.acceptanceCriteria
              .map(redactor.redact)
              .toList(growable: false),
          changedFiles: candidate.changedFiles,
          task: candidate.task,
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

  return Ll37WorktreeAgentHistoryExportResult(
    pairId: selection.pairId,
    sourceSurface: 'worktree_agent',
    casePaths: casePaths,
  );
}
