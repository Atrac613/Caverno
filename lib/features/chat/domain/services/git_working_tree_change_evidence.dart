// ChatNotifier decomposition collaborator: git-working-tree-change-evidence

import '../entities/tool_call_info.dart';
import 'tool_call_execution_policy.dart';

/// Whether Git itself has already reported the paths a command targets as
/// changed in the working tree.
///
/// [UnexecutedFileMutationBeforeCommandGuard] asks "did the claimed save
/// actually happen?", and a prose claim is a poor way to answer that when a
/// `git status` / `git diff` in the same turn answers it directly. Session
/// d904b342 lost a whole turn to the gap: the files were written in the
/// previous turn, `git status --short` and `git diff` both listed them, and
/// `git add pubspec.yaml docs/...` was still blocked for want of a same-turn
/// `edit_file` — the user had to re-ask.
///
/// Deliberately narrow: only a Git command, only the exact paths it names, and
/// only against a successful status/diff result. An unnamed target (a bare
/// `git commit`) or a wildcard (`git add .`) proves nothing and still blocks.
final class GitWorkingTreeChangeEvidence {
  const GitWorkingTreeChangeEvidence();

  static const ToolCallExecutionPolicy _executionPolicy =
      ToolCallExecutionPolicy();

  bool covers(
    ToolCallInfo toolCall,
    List<ToolResultInfo> executedToolResults,
  ) {
    if (toolCall.name.trim().toLowerCase() != 'git_execute_command') {
      return false;
    }
    final command = _executionPolicy.toolCommandArgument(toolCall.arguments);
    if (command == null) return false;
    final paths = _pathArguments(command);
    if (paths.isEmpty) return false;

    final reports = executedToolResults
        .where(_isWorkingTreeInspection)
        .map((result) => result.result)
        .toList(growable: false);
    if (reports.isEmpty) return false;

    return paths.every(
      (path) => reports.any((report) => report.contains(path)),
    );
  }

  bool _isWorkingTreeInspection(ToolResultInfo result) {
    if (result.name.trim().toLowerCase() != 'git_execute_command') {
      return false;
    }
    if (!_executionPolicy.toolResultHasSuccessfulExit(result)) return false;
    final command = _executionPolicy.toolCommandArgument(result.arguments);
    if (command == null) return false;
    final arguments = _argumentsOf(command);
    if (arguments.isEmpty) return false;
    return arguments.first == 'status' || arguments.first == 'diff';
  }

  /// The file paths a Git command names, ignoring the subcommand and flags.
  ///
  /// A wildcard target (`git add .`, `git add '*'`) names nothing in
  /// particular: matching it against a status report would prove only that
  /// *something* changed, so it yields no evidence at all.
  List<String> _pathArguments(String command) {
    final targets = _argumentsOf(command)
        .skip(1)
        .where((argument) => !argument.startsWith('-'))
        .toList(growable: false);
    final isWildcard = targets.any(
      (target) => target == '.' || target == '..' || target.contains('*'),
    );
    return isWildcard ? const <String>[] : targets;
  }

  List<String> _argumentsOf(String command) {
    var normalized = command.trim();
    if (normalized.toLowerCase().startsWith('git ')) {
      normalized = normalized.substring(4).trimLeft();
    }
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }
}
