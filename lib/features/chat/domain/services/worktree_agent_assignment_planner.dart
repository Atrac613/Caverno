import '../entities/worktree_agent_task.dart';

class WorktreeAgentAssignmentPlan {
  const WorktreeAgentAssignmentPlan({
    required this.title,
    required this.prompt,
    required this.codingProjectId,
    required this.baseBranch,
    required this.branchName,
    required this.worktreePath,
    required this.checkpointLineageId,
    required this.endpointId,
    required this.verificationCommand,
  });

  final String title;
  final String prompt;
  final String codingProjectId;
  final String baseBranch;
  final String branchName;
  final String worktreePath;
  final String checkpointLineageId;
  final String endpointId;
  final String verificationCommand;
}

class WorktreeAgentAssignmentPlanner {
  const WorktreeAgentAssignmentPlanner();

  static const defaultBranchPrefix = 'feature/ll13-';

  WorktreeAgentAssignmentPlan plan({
    required String title,
    required String prompt,
    required String projectRootPath,
    required Iterable<WorktreeAgentTask> existingTasks,
    String codingProjectId = '',
    String baseBranch = 'main',
    String branchPrefix = defaultBranchPrefix,
    String worktreeRootPath = '',
    String checkpointLineageId = '',
    String endpointId = '',
    String verificationCommand = '',
    Iterable<String> existingBranchNames = const <String>[],
    Iterable<String> existingWorktreePaths = const <String>[],
  }) {
    final slug = _slugFor(title.trim().isEmpty ? prompt : title);
    final normalizedBranchPrefix = _normalizeBranchPrefix(branchPrefix);
    final reservedBranches = {
      for (final task in existingTasks) task.branchName.trim(),
      for (final branch in existingBranchNames) branch.trim(),
    }..removeWhere((branch) => branch.isEmpty);
    final branchName = _uniqueValue(
      '$normalizedBranchPrefix$slug',
      reservedBranches,
    );

    final root = _resolveWorktreeRoot(
      projectRootPath: projectRootPath,
      worktreeRootPath: worktreeRootPath,
    );
    final reservedWorktreePaths = {
      for (final task in existingTasks)
        if (task.occupiesWorktree) task.normalizedWorktreePath,
      for (final path in existingWorktreePaths)
        WorktreeAgentTask.normalizeWorktreePath(path),
    }..removeWhere((path) => path.isEmpty);
    final worktreePath = _uniqueValue(
      _joinPath(root, slug),
      reservedWorktreePaths,
    );

    return WorktreeAgentAssignmentPlan(
      title: title.trim(),
      prompt: prompt.trim(),
      codingProjectId: codingProjectId.trim(),
      baseBranch: baseBranch.trim().isEmpty ? 'main' : baseBranch.trim(),
      branchName: branchName,
      worktreePath: worktreePath,
      checkpointLineageId: checkpointLineageId.trim(),
      endpointId: endpointId.trim(),
      verificationCommand: verificationCommand.trim(),
    );
  }

  String _slugFor(String source) {
    final lower = source.toLowerCase();
    final buffer = StringBuffer();
    var previousDash = false;
    for (final codeUnit in lower.codeUnits) {
      final isDigit = codeUnit >= 48 && codeUnit <= 57;
      final isLetter = codeUnit >= 97 && codeUnit <= 122;
      if (isDigit || isLetter) {
        buffer.writeCharCode(codeUnit);
        previousDash = false;
      } else if (!previousDash && buffer.isNotEmpty) {
        buffer.write('-');
        previousDash = true;
      }
    }

    var slug = buffer.toString();
    while (slug.endsWith('-')) {
      slug = slug.substring(0, slug.length - 1);
    }
    if (slug.isEmpty) return 'task';
    if (slug.length <= 48) return slug;
    slug = slug.substring(0, 48);
    while (slug.endsWith('-')) {
      slug = slug.substring(0, slug.length - 1);
    }
    return slug.isEmpty ? 'task' : slug;
  }

  String _normalizeBranchPrefix(String prefix) {
    final normalized = prefix.trim();
    if (normalized.isEmpty) return defaultBranchPrefix;
    return normalized.endsWith('/') || normalized.endsWith('-')
        ? normalized
        : '$normalized-';
  }

  String _resolveWorktreeRoot({
    required String projectRootPath,
    required String worktreeRootPath,
  }) {
    final explicit = WorktreeAgentTask.normalizeWorktreePath(worktreeRootPath);
    if (explicit.isNotEmpty) return explicit;

    final projectRoot = WorktreeAgentTask.normalizeWorktreePath(
      projectRootPath,
    );
    if (projectRoot.isEmpty) {
      throw ArgumentError('Project root path is required.');
    }

    final separator = _separatorFor(projectRoot);
    final lastSeparator = projectRoot.lastIndexOf(separator);
    if (lastSeparator <= 0 || lastSeparator == projectRoot.length - 1) {
      return '$projectRoot-worktrees';
    }

    final parent = projectRoot.substring(0, lastSeparator);
    final name = projectRoot.substring(lastSeparator + 1);
    return _joinPath(parent, '$name-worktrees');
  }

  String _joinPath(String root, String leaf) {
    final normalizedRoot = WorktreeAgentTask.normalizeWorktreePath(root);
    final normalizedLeaf = WorktreeAgentTask.normalizeWorktreePath(leaf);
    final separator = _separatorFor(normalizedRoot);
    if (normalizedRoot.isEmpty) return normalizedLeaf;
    if (normalizedLeaf.isEmpty) return normalizedRoot;
    return '$normalizedRoot$separator$normalizedLeaf';
  }

  String _separatorFor(String path) {
    return path.contains('\\') && !path.contains('/') ? '\\' : '/';
  }

  String _uniqueValue(String preferred, Set<String> reserved) {
    final normalizedPreferred = WorktreeAgentTask.normalizeWorktreePath(
      preferred,
    );
    if (!reserved.contains(normalizedPreferred)) {
      return normalizedPreferred;
    }

    var index = 2;
    while (true) {
      final candidate = '$normalizedPreferred-$index';
      if (!reserved.contains(candidate)) return candidate;
      index++;
    }
  }
}
