import '../../data/datasources/chat_remote_datasource.dart';
import '../entities/conversation_workflow.dart';

class ConversationPlanExecutionDriftAssessment {
  const ConversationPlanExecutionDriftAssessment({
    required this.touchedTargetFiles,
    required this.unrelatedTouchedPaths,
    required this.scaffoldCommands,
  });

  final List<String> touchedTargetFiles;
  final List<String> unrelatedTouchedPaths;
  final List<String> scaffoldCommands;

  bool get hasDrift =>
      touchedTargetFiles.isEmpty &&
      (unrelatedTouchedPaths.isNotEmpty || scaffoldCommands.isNotEmpty);
}

class ConversationPlanExecutionGuardrails {
  ConversationPlanExecutionGuardrails._();

  static ConversationPlanExecutionDriftAssessment assessTaskDrift({
    required ConversationWorkflowTask task,
    required List<ToolResultInfo> toolResults,
  }) {
    final normalizedTargets = task.targetFiles
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toSet();
    final touchedTargetFiles = <String>{};
    final unrelatedTouchedPaths = <String>{};
    final scaffoldCommands = <String>{};

    for (final toolResult in toolResults) {
      switch (toolResult.name) {
        case 'write_file':
        case 'edit_file':
          final path = _normalizePath(toolResult.arguments['path']?.toString());
          if (path.isEmpty) {
            continue;
          }
          if (_matchesTarget(path, normalizedTargets)) {
            touchedTargetFiles.add(path);
          } else {
            unrelatedTouchedPaths.add(path);
          }
        case 'local_execute_command':
        case 'git_execute_command':
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
          if (!referencesTarget &&
              !referencesValidation &&
              _looksLikeScaffoldCommand(normalizedCommand)) {
            scaffoldCommands.add(command);
          }
      }
    }

    return ConversationPlanExecutionDriftAssessment(
      touchedTargetFiles: touchedTargetFiles.toList(growable: false),
      unrelatedTouchedPaths: unrelatedTouchedPaths.toList(growable: false),
      scaffoldCommands: scaffoldCommands.toList(growable: false),
    );
  }

  static bool _matchesTarget(String path, Set<String> normalizedTargets) {
    if (normalizedTargets.contains(path)) {
      return true;
    }
    return normalizedTargets.any(
      (target) => path.endsWith('/$target') || path.endsWith(target),
    );
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
}
