import '../../../../project_farm/domain/roadmap_next_task_contract.dart';
import '../../../data/datasources/git_tools.dart';
import '../../entities/tool_call_info.dart';
import '../file_mutation_evidence_policy.dart';
import '../project_task/saved_task_target_scope_guard.dart';
import '../tool_loop/tool_call_execution_policy.dart';

/// Compares captured executions against the owning turn's saved validation.
final class SavedValidationEvidence {
  const SavedValidationEvidence();
  static const _toolCallExecutionPolicy = ToolCallExecutionPolicy();
  static const _fileMutationEvidencePolicy = FileMutationEvidencePolicy();
  bool containsOnlyPreviouslySuccessfulCalls(
    List<ToolCallInfo> toolCalls,
    List<ToolResultInfo> previousToolResults,
    String? validationCommand,
  ) {
    if (toolCalls.isEmpty || previousToolResults.isEmpty) {
      return false;
    }
    if (validationCommand == null) return false;
    final normalizedValidationCommand = _normalizeToolCommandForComparison(
      validationCommand,
    );

    return toolCalls.every((toolCall) {
      if (toolCall.name == 'run_tests') {
        final testPath = _runTestsPathArgument(toolCall.arguments);
        return previousToolResults.any((result) {
          if (result.name != toolCall.name ||
              _runTestsPathArgument(result.arguments) != testPath ||
              !_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
            return false;
          }
          return _runTestsMatchesSavedValidation(
            arguments: result.arguments,
            normalizedValidationCommand: normalizedValidationCommand,
          );
        });
      }
      if (!_toolCallExecutionPolicy.isCommandExecutionTool(toolCall.name)) {
        return false;
      }
      final command = _toolCallExecutionPolicy.toolCommandArgument(
        toolCall.arguments,
      );
      if (command == null) return false;
      final normalizedCommand = _normalizeToolCommandForComparison(command);
      return previousToolResults.any((result) {
        if (result.name != toolCall.name ||
            !_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
          return false;
        }
        final resultCommand = _toolCallExecutionPolicy.toolCommandArgument(
          result.arguments,
        );
        if (resultCommand == null ||
            _normalizeToolCommandForComparison(resultCommand) !=
                normalizedCommand) {
          return false;
        }
        return _toolCommandMatchesSavedValidation(
          result: result,
          command: command,
          normalizedValidationCommand: normalizedValidationCommand,
        );
      });
    });
  }

  bool hasSuccessfulResult(
    List<ToolResultInfo> toolResults,
    String? validationCommand,
    String? ownerProjectRoot,
  ) {
    if (validationCommand == null) {
      return false;
    }
    final normalizedValidationCommand = _normalizeToolCommandForComparison(
      validationCommand,
    );
    return toolResults.any((result) {
      if (_readFileMatchesSavedCatValidation(
        result: result,
        validationCommand: validationCommand,
        ownerProjectRoot: ownerProjectRoot,
      )) {
        return true;
      }
      if (!_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
        return false;
      }
      if (result.name == 'run_tests') {
        return _runTestsMatchesSavedValidation(
          arguments: result.arguments,
          normalizedValidationCommand: normalizedValidationCommand,
        );
      }
      final command = _toolCallExecutionPolicy.toolCommandArgument(
        result.arguments,
      );
      if (command == null) return false;
      return _toolCommandMatchesSavedValidation(
        result: result,
        command: command,
        normalizedValidationCommand: normalizedValidationCommand,
      );
    });
  }

  bool _readFileMatchesSavedCatValidation({
    required ToolResultInfo result,
    required String validationCommand,
    required String? ownerProjectRoot,
  }) {
    if (result.name != 'read_file') return false;
    final validationArgs = GitTools.splitArgs(validationCommand.trim());
    if (validationArgs.length != 2 ||
        validationArgs.first.split('/').last.toLowerCase() != 'cat') {
      return false;
    }
    final decoded = decodeJsonObject(result.result);
    if (decoded == null || decoded['error'] != null) return false;
    if (decoded['content'] is! String) return false;
    final actualPath = _fileMutationEvidencePolicy.pathForResult(result);
    if (actualPath == null) return false;
    final normalizedActualPath = const SavedTaskTargetScopeGuard()
        .normalizePath(actualPath, projectRoot: ownerProjectRoot);
    final normalizedValidationPath = const SavedTaskTargetScopeGuard()
        .normalizePath(validationArgs[1], projectRoot: ownerProjectRoot);
    return normalizedActualPath != null &&
        normalizedActualPath == normalizedValidationPath;
  }

  bool _toolCommandMatchesSavedValidation({
    required ToolResultInfo result,
    required String command,
    required String normalizedValidationCommand,
  }) => _toolCallExecutionPolicy.toolCommandMatchesSavedValidation(
    result: result,
    command: command,
    normalizedValidationCommand: normalizedValidationCommand,
  );

  String _normalizeToolCommandForComparison(String command) =>
      _toolCallExecutionPolicy.normalizeToolCommandForComparison(command);
  String? _runTestsPathArgument(Map<String, dynamic> arguments) =>
      _toolCallExecutionPolicy.runTestsPathArgument(arguments);
  bool _runTestsMatchesSavedValidation({
    required Map<String, dynamic> arguments,
    required String normalizedValidationCommand,
  }) => _toolCallExecutionPolicy.runTestsMatchesSavedValidation(
    arguments: arguments,
    normalizedValidationCommand: normalizedValidationCommand,
  );
}
