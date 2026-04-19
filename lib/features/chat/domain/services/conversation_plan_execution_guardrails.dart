import 'dart:convert';

import '../../data/datasources/chat_remote_datasource.dart';
import '../entities/conversation_workflow.dart';

class ConversationPlanExecutionDriftAssessment {
  const ConversationPlanExecutionDriftAssessment({
    required this.touchedTargetFiles,
    required this.unrelatedTouchedPaths,
    required this.scaffoldCommands,
    required this.benignSupportCommands,
    required this.repeatedTargetFiles,
    required this.remainingTargetFiles,
  });

  final List<String> touchedTargetFiles;
  final List<String> unrelatedTouchedPaths;
  final List<String> scaffoldCommands;
  final List<String> benignSupportCommands;
  final List<String> repeatedTargetFiles;
  final List<String> remainingTargetFiles;

  bool get hasDrift =>
      (touchedTargetFiles.isEmpty &&
          (unrelatedTouchedPaths.isNotEmpty || scaffoldCommands.isNotEmpty)) ||
      (repeatedTargetFiles.isNotEmpty && remainingTargetFiles.isNotEmpty);
}

class ConversationPlanExecutionCompletionAssessment {
  const ConversationPlanExecutionCompletionAssessment({
    required this.requiresValidation,
    required this.hasTargetFiles,
    required this.hasFailure,
    required this.touchedTargetFiles,
    required this.untouchedTargetFiles,
    required this.unrelatedTouchedPaths,
    required this.scaffoldCommands,
    required this.benignSupportCommands,
    required this.successfulValidationCommands,
    required this.failedValidationCommands,
    required this.allowsLightValidationCompletion,
  });

  final bool requiresValidation;
  final bool hasTargetFiles;
  final bool hasFailure;
  final List<String> touchedTargetFiles;
  final List<String> untouchedTargetFiles;
  final List<String> unrelatedTouchedPaths;
  final List<String> scaffoldCommands;
  final List<String> benignSupportCommands;
  final List<String> successfulValidationCommands;
  final List<String> failedValidationCommands;
  final bool allowsLightValidationCompletion;

  bool get touchedAllTargetFiles =>
      !hasTargetFiles || untouchedTargetFiles.isEmpty;

  bool get completedFromSuccessfulValidation =>
      !hasFailure &&
      unrelatedTouchedPaths.isEmpty &&
      scaffoldCommands.isEmpty &&
      successfulValidationCommands.isNotEmpty &&
      (touchedTargetFiles.isNotEmpty || !hasTargetFiles);

  bool get completedFromTargetCoverage =>
      !hasFailure &&
      touchedAllTargetFiles &&
      unrelatedTouchedPaths.isEmpty &&
      scaffoldCommands.isEmpty &&
      (!requiresValidation || allowsLightValidationCompletion);

  bool get hasCompletionEvidenceIgnoringFailures =>
      ((successfulValidationCommands.isNotEmpty &&
              (touchedTargetFiles.isNotEmpty || !hasTargetFiles)) ||
          (touchedAllTargetFiles &&
              (!requiresValidation || allowsLightValidationCompletion))) &&
      unrelatedTouchedPaths.isEmpty &&
      scaffoldCommands.isEmpty;

  bool get shouldMarkCompleted {
    return completedFromSuccessfulValidation || completedFromTargetCoverage;
  }
}

class ConversationPlanExecutionGuardrails {
  ConversationPlanExecutionGuardrails._();

  static ConversationPlanExecutionDriftAssessment assessTaskDrift({
    required ConversationWorkflowTask task,
    required List<ToolResultInfo> toolResults,
  }) {
    final isScaffoldTask = _isScaffoldLikeTask(task);
    final normalizedTargets = task.targetFiles
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toSet();
    final targetDirectories = _targetDirectories(normalizedTargets);
    final touchedTargetFiles = <String>{};
    final targetTouchCounts = <String, int>{};
    final unrelatedTouchedPaths = <String>{};
    final scaffoldCommands = <String>{};
    final benignSupportCommands = <String>{};

    for (final toolResult in toolResults) {
      if (toolResult.name == 'write_file' || toolResult.name == 'edit_file') {
        final path = _normalizePath(toolResult.arguments['path']?.toString());
        if (path.isEmpty) {
          continue;
        }
        if (_matchesTarget(path, normalizedTargets)) {
          touchedTargetFiles.add(path);
          targetTouchCounts.update(
            path,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        } else if (isScaffoldTask && _isScaffoldSupportPath(path)) {
          continue;
        } else {
          unrelatedTouchedPaths.add(path);
        }
        continue;
      }

      if (toolResult.name == 'local_execute_command' ||
          toolResult.name == 'git_execute_command') {
        final command =
            toolResult.arguments['command']?.toString().trim() ?? '';
        if (command.isEmpty) {
          continue;
        }
        final normalizedCommand = command.toLowerCase();
        final referencesTarget = normalizedTargets.any(
          (target) => normalizedCommand.contains(target.toLowerCase()),
        );
        final referencesValidation =
            task.validationCommand.trim().isNotEmpty &&
            normalizedCommand.contains(task.validationCommand.toLowerCase());
        final referencesTargetDirectory = targetDirectories.any(
          (directory) => normalizedCommand.contains(directory.toLowerCase()),
        );
        if (!referencesTarget &&
            !referencesValidation &&
            _looksLikeScaffoldCommand(normalizedCommand)) {
          if (referencesTargetDirectory) {
            benignSupportCommands.add(command);
          } else {
            scaffoldCommands.add(command);
          }
        }
      }
    }

    final repeatedTargetFiles = targetTouchCounts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toList(growable: false);
    final remainingTargetFiles = normalizedTargets
        .where((target) => !touchedTargetFiles.contains(target))
        .toList(growable: false);

    return ConversationPlanExecutionDriftAssessment(
      touchedTargetFiles: touchedTargetFiles.toList(growable: false),
      unrelatedTouchedPaths: unrelatedTouchedPaths.toList(growable: false),
      scaffoldCommands: scaffoldCommands.toList(growable: false),
      benignSupportCommands: benignSupportCommands.toList(growable: false),
      repeatedTargetFiles: repeatedTargetFiles,
      remainingTargetFiles: remainingTargetFiles,
    );
  }

  static ConversationPlanExecutionCompletionAssessment assessTaskCompletion({
    required ConversationWorkflowTask task,
    required List<ToolResultInfo> toolResults,
  }) {
    final isScaffoldTask = _isScaffoldLikeTask(task);
    final normalizedTargets = task.targetFiles
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toSet();
    final targetDirectories = _targetDirectories(normalizedTargets);
    final touchedTargetFiles = <String>{};
    final unrelatedTouchedPaths = <String>{};
    final scaffoldCommands = <String>{};
    final benignSupportCommands = <String>{};
    final successfulValidationCommands = <String>{};
    final failedValidationCommands = <String>{};
    var hasFailure = false;

    for (final toolResult in toolResults) {
      if (_looksLikeFailureResult(toolResult.result)) {
        hasFailure = true;
      }

      if (toolResult.name == 'write_file' ||
          toolResult.name == 'edit_file' ||
          toolResult.name == 'rollback_last_file_change') {
        final path = _normalizePath(toolResult.arguments['path']?.toString());
        if (path.isEmpty) {
          continue;
        }
        if (_matchesTarget(path, normalizedTargets)) {
          touchedTargetFiles.add(path);
        } else if (isScaffoldTask && _isScaffoldSupportPath(path)) {
          continue;
        } else {
          unrelatedTouchedPaths.add(path);
        }
        continue;
      }

      if (toolResult.name == 'local_execute_command' ||
          toolResult.name == 'git_execute_command' ||
          toolResult.name == 'ssh_execute_command') {
        final command = _extractCommand(toolResult);
        if (_matchesValidationCommand(command, task.validationCommand)) {
          final exitCode = _extractExitCode(toolResult.result);
          final succeeded = exitCode == null
              ? !_looksLikeFailureResult(toolResult.result)
              : exitCode == 0;
          if (succeeded) {
            successfulValidationCommands.add(command);
          } else {
            failedValidationCommands.add(command);
            hasFailure = true;
          }
        } else if ((toolResult.name == 'local_execute_command' ||
                toolResult.name == 'git_execute_command') &&
            command.isNotEmpty) {
          final normalizedCommand = command.toLowerCase();
          final referencesTarget = normalizedTargets.any(
            (target) => normalizedCommand.contains(target.toLowerCase()),
          );
          final referencesValidation =
              task.validationCommand.trim().isNotEmpty &&
              normalizedCommand.contains(task.validationCommand.toLowerCase());
          final referencesTargetDirectory = targetDirectories.any(
            (directory) => normalizedCommand.contains(directory.toLowerCase()),
          );
          if (!referencesTarget &&
              !referencesValidation &&
              _looksLikeScaffoldCommand(normalizedCommand)) {
            if (referencesTargetDirectory) {
              benignSupportCommands.add(command);
            } else {
              scaffoldCommands.add(command);
            }
          }
        }
        continue;
      }

      if (toolResult.name == 'run_tests') {
        final testPath = _normalizeText(
          toolResult.arguments['test_path'] ?? toolResult.arguments['path'],
        );
        if (!_matchesRunTestsValidation(task.validationCommand, testPath)) {
          continue;
        }
        final resultSummary = testPath == null
            ? 'run_tests'
            : 'run_tests $testPath';
        final exitCode = _extractExitCode(toolResult.result);
        final succeeded = exitCode == null
            ? !_looksLikeFailureResult(toolResult.result)
            : exitCode == 0;
        if (succeeded) {
          successfulValidationCommands.add(resultSummary);
        } else {
          failedValidationCommands.add(resultSummary);
          hasFailure = true;
        }
      }
    }

    final untouchedTargetFiles = normalizedTargets
        .where((target) => !touchedTargetFiles.contains(target))
        .toList(growable: false);

    return ConversationPlanExecutionCompletionAssessment(
      requiresValidation: task.validationCommand.trim().isNotEmpty,
      hasTargetFiles: normalizedTargets.isNotEmpty,
      hasFailure: hasFailure,
      touchedTargetFiles: touchedTargetFiles.toList(growable: false),
      untouchedTargetFiles: untouchedTargetFiles,
      unrelatedTouchedPaths: unrelatedTouchedPaths.toList(growable: false),
      scaffoldCommands: scaffoldCommands.toList(growable: false),
      benignSupportCommands: benignSupportCommands.toList(growable: false),
      successfulValidationCommands: successfulValidationCommands.toList(
        growable: false,
      ),
      failedValidationCommands: failedValidationCommands.toList(
        growable: false,
      ),
      allowsLightValidationCompletion: _looksLikeLightValidationCommand(
        task.validationCommand,
      ),
    );
  }

  static List<String> unavailableToolNames(List<ToolResultInfo> toolResults) {
    final names = <String>{};
    for (final toolResult in toolResults) {
      final normalizedResult = toolResult.result.toLowerCase();
      final decoded = _tryDecodeMap(toolResult.result);
      final code = _normalizeText(decoded?['code'])?.toLowerCase();
      if (code == 'tool_not_available' ||
          normalizedResult.contains('no matching tool available')) {
        names.add(
          _normalizeText(decoded?['toolName']) ?? toolResult.name.trim(),
        );
      }
    }
    return names.where((name) => name.isNotEmpty).toList(growable: false);
  }

  static List<String> editMismatchPaths(List<ToolResultInfo> toolResults) {
    final paths = <String>{};
    for (final toolResult in toolResults) {
      final normalizedResult = toolResult.result.toLowerCase();
      final decoded = _tryDecodeMap(toolResult.result);
      final code = _normalizeText(decoded?['code'])?.toLowerCase();
      if (code != 'edit_mismatch' &&
          !normalizedResult.contains(
            'old_text was not found in the target file',
          )) {
        continue;
      }
      final path = _normalizePath(
        _normalizeText(decoded?['path']) ??
            _normalizeText(toolResult.arguments['path']),
      );
      if (path.isNotEmpty) {
        paths.add(path);
      }
    }
    return paths.toList(growable: false);
  }

  static bool hasOnlyRecoverableMalformedFailures(
    List<ToolResultInfo> toolResults,
  ) {
    var sawFailure = false;
    for (final toolResult in toolResults) {
      if (!_looksLikeFailureResult(toolResult.result)) {
        continue;
      }
      sawFailure = true;
      if (!_isRecoverableMalformedFailure(toolResult)) {
        return false;
      }
    }
    return sawFailure;
  }

  static List<String> missingWorkspaceTargetFiles({
    required ConversationWorkflowTask task,
    required Iterable<String> existingTargetPaths,
  }) {
    final normalizedTargets = task.targetFiles
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final normalizedExisting = existingTargetPaths
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toSet();
    return normalizedTargets
        .where((target) => !normalizedExisting.contains(target))
        .toList(growable: false);
  }

  static bool looksLikeScaffoldTask(ConversationWorkflowTask task) {
    return _isScaffoldLikeTask(task);
  }

  static bool canFinalizeScaffoldFromWorkspaceTargets({
    required ConversationWorkflowTask task,
    required Iterable<String> existingTargetPaths,
  }) {
    if (!_isScaffoldLikeTask(task)) {
      return false;
    }
    final missingTargets = missingWorkspaceTargetFiles(
      task: task,
      existingTargetPaths: existingTargetPaths,
    );
    if (missingTargets.isNotEmpty) {
      return false;
    }
    final validationCommand = task.validationCommand.trim();
    return validationCommand.isEmpty ||
        _looksLikeLightValidationCommand(validationCommand);
  }

  static String? blockedPythonImportModule(List<ToolResultInfo> toolResults) {
    final importPattern = RegExp(
      "No module named ['\\\"]([^'\\\"]+)['\\\"]",
      caseSensitive: false,
    );
    for (final toolResult in toolResults) {
      final match = importPattern.firstMatch(toolResult.result);
      if (match != null) {
        return match.group(1)?.trim();
      }
    }
    return null;
  }

  static String? missingTargetFileFromValidationFailure({
    required ConversationWorkflowTask task,
    required List<ToolResultInfo> toolResults,
  }) {
    final normalizedTargets = task.targetFiles
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (normalizedTargets.isEmpty) {
      return null;
    }

    for (final toolResult in toolResults) {
      if (toolResult.name != 'local_execute_command' &&
          toolResult.name != 'git_execute_command' &&
          toolResult.name != 'ssh_execute_command') {
        continue;
      }
      final command = _extractCommand(toolResult);
      if (!_matchesValidationCommand(command, task.validationCommand)) {
        continue;
      }
      final normalizedResult = toolResult.result.toLowerCase();
      final looksLikeMissingPathFailure =
          normalizedResult.contains('no such file or directory') ||
          normalizedResult.contains("can't open file") ||
          normalizedResult.contains('cannot open') ||
          normalizedResult.contains('not found');
      if (!looksLikeMissingPathFailure) {
        continue;
      }

      for (final target in normalizedTargets) {
        final targetBasename = target.split('/').last.toLowerCase();
        if (targetBasename.isNotEmpty &&
            normalizedResult.contains(targetBasename)) {
          return target;
        }
      }

      if (normalizedTargets.length == 1) {
        return normalizedTargets.first;
      }
    }
    return null;
  }

  static String? failedPythonValidationCommand({
    required ConversationWorkflowTask task,
    required List<ToolResultInfo> toolResults,
  }) {
    for (final toolResult in toolResults) {
      if (toolResult.name != 'local_execute_command' &&
          toolResult.name != 'git_execute_command' &&
          toolResult.name != 'ssh_execute_command') {
        continue;
      }
      final command = _extractCommand(toolResult);
      if (!_matchesValidationCommand(command, task.validationCommand)) {
        continue;
      }
      final normalizedResult = toolResult.result.toLowerCase();
      if (normalizedResult.contains('modulenotfounderror') ||
          normalizedResult.contains('no module named')) {
        return command;
      }
    }
    return null;
  }

  static String? suggestPythonSrcLayoutRetryCommand({
    required ConversationWorkflowTask task,
    required String failedCommand,
  }) {
    final command = failedCommand.trim();
    if (command.isEmpty) {
      return null;
    }
    final normalizedTargets = task.targetFiles
        .map(_normalizePath)
        .where((path) => path.startsWith('src/'))
        .toList(growable: false);
    if (normalizedTargets.isEmpty) {
      return null;
    }
    final normalizedCommand = command.toLowerCase();
    final isPythonCommand =
        normalizedCommand.startsWith('python ') ||
        normalizedCommand.startsWith('python3 ') ||
        normalizedCommand.startsWith('python -') ||
        normalizedCommand.startsWith('python3 -');
    if (!isPythonCommand) {
      return null;
    }
    if (normalizedCommand.contains('pythonpath=') ||
        normalizedCommand.startsWith('cd src &&') ||
        normalizedCommand.startsWith('(cd src')) {
      return null;
    }
    return 'PYTHONPATH=src $command';
  }

  static bool _matchesTarget(String path, Set<String> normalizedTargets) {
    if (normalizedTargets.contains(path)) {
      return true;
    }
    return normalizedTargets.any(
      (target) => path.endsWith('/$target') || path.endsWith(target),
    );
  }

  static bool _matchesValidationCommand(
    String command,
    String validationCommand,
  ) {
    final normalizedCommand = command.trim().toLowerCase();
    final normalizedValidation = validationCommand.trim().toLowerCase();
    if (normalizedCommand.isEmpty || normalizedValidation.isEmpty) {
      return false;
    }
    return normalizedCommand == normalizedValidation ||
        normalizedCommand.contains(normalizedValidation) ||
        normalizedValidation.contains(normalizedCommand);
  }

  static bool _matchesRunTestsValidation(
    String validationCommand,
    String? testPath,
  ) {
    final normalizedValidation = validationCommand.trim().toLowerCase();
    final normalizedTestPath = testPath?.trim().toLowerCase() ?? '';
    if (normalizedValidation.isEmpty || normalizedTestPath.isEmpty) {
      return false;
    }
    return normalizedValidation.contains(normalizedTestPath) ||
        normalizedValidation.contains('run_tests');
  }

  static String _normalizePath(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return '';
    }
    return raw.replaceAll('\\', '/');
  }

  static bool _looksLikeScaffoldCommand(String normalizedCommand) {
    const scaffoldPatterns = <String>[
      'mkdir ',
      'mkdir -p',
      'poetry init',
      'poetry add',
      'pip install',
      'uv init',
      'uv add',
      'npm init',
      'yarn init',
      'pnpm init',
      'cargo init',
      'flutter create',
      'touch ',
    ];
    return scaffoldPatterns.any(normalizedCommand.contains);
  }

  static bool _looksLikeLightValidationCommand(String validationCommand) {
    final normalized = validationCommand.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return normalized.startsWith('ls ') ||
        normalized == 'ls' ||
        normalized.startsWith('find ') ||
        normalized.startsWith('test -f ') ||
        normalized.startsWith('test -d ') ||
        normalized.startsWith('stat ');
  }

  static Set<String> _targetDirectories(Set<String> normalizedTargets) {
    final directories = <String>{};
    for (final target in normalizedTargets) {
      final separatorIndex = target.lastIndexOf('/');
      if (separatorIndex <= 0) {
        continue;
      }
      final directory = target.substring(0, separatorIndex).trim();
      if (directory.isNotEmpty) {
        directories.add(directory);
      }
    }
    return directories;
  }

  static String _extractCommand(ToolResultInfo toolResult) {
    final directCommand = _normalizeText(toolResult.arguments['command']);
    if (directCommand != null) {
      return directCommand;
    }
    final decoded = _tryDecodeMap(toolResult.result);
    return _normalizeText(decoded?['command']) ?? '';
  }

  static int? _extractExitCode(String rawResult) {
    final decoded = _tryDecodeMap(rawResult);
    final exitCode = decoded == null ? null : decoded['exit_code'];
    if (exitCode is int) {
      return exitCode;
    }
    if (exitCode is num) {
      return exitCode.toInt();
    }
    if (exitCode is String) {
      return int.tryParse(exitCode.trim());
    }
    return null;
  }

  static bool _looksLikeFailureResult(String rawResult) {
    final normalized = rawResult.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final exitCode = _extractExitCode(rawResult);
    if (exitCode != null && exitCode != 0) {
      return true;
    }
    final decoded = _tryDecodeMap(rawResult);
    final successValue = decoded == null ? null : decoded['success'];
    if (successValue == false) {
      return true;
    }
    final isSuccessValue = decoded == null ? null : decoded['isSuccess'];
    if (isSuccessValue == false) {
      return true;
    }
    return normalized.startsWith('error:') ||
        normalized.contains('failed to') ||
        normalized.contains('no matching tool available') ||
        normalized.contains('"issuccess":false') ||
        normalized.contains('"success":false') ||
        normalized.contains('"errormessage"') ||
        normalized.contains('"status":"failed"') ||
        normalized.contains('"status":"error"') ||
        normalized.contains('traceback') ||
        normalized.contains('exception');
  }

  static bool _isRecoverableMalformedFailure(ToolResultInfo toolResult) {
    final normalizedResult = toolResult.result.trim().toLowerCase();
    if (normalizedResult.isEmpty) {
      return false;
    }
    if (toolResult.name != 'write_file' && toolResult.name != 'edit_file') {
      return false;
    }
    final decoded = _tryDecodeMap(toolResult.result);
    final failureCode = _normalizeText(decoded?['code'])?.toLowerCase();
    if (failureCode == 'invalid_arguments') {
      return true;
    }
    return normalizedResult.contains('path is required') ||
        normalizedResult.contains('content is required') ||
        normalizedResult.contains('old_text is required') ||
        normalizedResult.contains('new_text is required') ||
        normalizedResult.contains('invalid arguments');
  }

  static bool _isScaffoldLikeTask(ConversationWorkflowTask task) {
    final normalized = '${task.title.trim()} ${task.notes.trim()}'
        .toLowerCase();
    const keywords = <String>[
      'scaffold',
      'initial',
      'initialize',
      'bootstrap',
      'project structure',
      'requirements',
      'dependency',
      'dependencies',
      'pyproject',
      'package layout',
      'file creation',
    ];
    return keywords.any(normalized.contains);
  }

  static bool _isScaffoldSupportPath(String path) {
    final normalized = path.toLowerCase();
    final basename = normalized.split('/').last;
    const rootSupportFiles = <String>{
      'requirements.txt',
      'requirements-dev.txt',
      'requirements-test.txt',
      'pyproject.toml',
      'poetry.lock',
      'setup.py',
      'setup.cfg',
      'readme.md',
      'readme.txt',
      '.gitignore',
      'main.py',
    };
    if (rootSupportFiles.contains(basename)) {
      return true;
    }
    return normalized.endsWith('/__init__.py') ||
        normalized == '__init__.py' ||
        normalized == 'src/main.py';
  }

  static Map<String, dynamic>? _tryDecodeMap(String rawResult) {
    try {
      final decoded = jsonDecode(rawResult);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? _normalizeText(Object? value) {
    final trimmed = value?.toString().trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
