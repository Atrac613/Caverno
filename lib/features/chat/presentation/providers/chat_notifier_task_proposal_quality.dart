// Same-library extension on [ChatNotifier]: task / workflow proposal quality
// gate — plausibility checks, task sanitization and normalization, fallback
// builders, retry / duplicate heuristics, and task reordering. Pure relocation
// from chat_notifier.dart (F5), no behavior change.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierTaskProposalQuality on ChatNotifier {
  bool _isReasoningWorkflowProposalPlausible(WorkflowProposalDraft proposal) {
    final fields = <String>[
      proposal.workflowSpec.goal,
      ...proposal.workflowSpec.constraints,
      ...proposal.workflowSpec.acceptanceCriteria,
      ...proposal.workflowSpec.openQuestions,
    ].map((item) => item.trim()).where((item) => item.isNotEmpty);

    if (proposal.workflowSpec.goal.trim().length > 220) {
      return false;
    }

    final suspiciousPattern = RegExp(
      "(recent context|current state|self-correction|(?:kind|workflowstage|acceptancecriteria|openquestions|decisions)\\s*:|[`'\\\"]\\s*(kind|workflowstage|goal|constraints|acceptancecriteria|openquestions|decisions)\\s*[`'\\\"]\\s*:)",
      caseSensitive: false,
    );
    for (final field in fields) {
      if (field.length > 280 || suspiciousPattern.hasMatch(field)) {
        return false;
      }
    }
    return true;
  }

  bool _isReasoningTaskProposalPlausible(WorkflowTaskProposalDraft proposal) {
    final suspiciousPattern = RegExp(
      "(recent context|current state|self-correction|the prompt says|saved task|task id|(?:title|targetfiles|validationcommand|notes|tasks)\\s*:|[`'\\\"]\\s*(title|targetfiles|validationcommand|notes|tasks)\\s*[`'\\\"]\\s*:)",
      caseSensitive: false,
    );
    for (final task in proposal.tasks) {
      if (task.title.trim().isEmpty ||
          task.title.length > 180 ||
          suspiciousPattern.hasMatch(task.title)) {
        return false;
      }
      if (task.validationCommand.length > 240 ||
          suspiciousPattern.hasMatch(task.validationCommand) ||
          task.notes.length > 320 ||
          suspiciousPattern.hasMatch(task.notes)) {
        return false;
      }
      if (task.targetFiles.any(
        (path) => path.length > 220 || suspiciousPattern.hasMatch(path),
      )) {
        return false;
      }
    }
    return proposal.tasks.isNotEmpty;
  }

  WorkflowTaskProposalDraft? _preferTaskProposalRetryCandidate({
    required WorkflowTaskProposalDraft? current,
    required WorkflowTaskProposalDraft candidate,
  }) {
    if (current == null) {
      return candidate;
    }

    final currentScore = _scoreTaskProposalRetryCandidate(current);
    final candidateScore = _scoreTaskProposalRetryCandidate(candidate);
    if (candidateScore > currentScore) {
      return candidate;
    }
    return current;
  }

  int _scoreTaskProposalRetryCandidate(WorkflowTaskProposalDraft proposal) {
    var score = proposal.tasks.length * 20;
    for (final task in proposal.tasks) {
      final implementationTargets = task.targetFiles
          .where(_looksLikeImplementationTargetFile)
          .toList(growable: false);
      if (!_looksLikeGenericScaffoldOnlyTask(task)) {
        score += 12;
      }
      if (implementationTargets.isNotEmpty) {
        score += 8;
      }
      if (!_hasWeakImplementationValidationCommand(
        task.validationCommand,
        implementationTargets,
      )) {
        score += 6;
      }
    }
    return score;
  }

  List<ConversationWorkflowTask> _buildHeuristicTaskProposalFallbackTasks({
    required List<String> contextLines,
    required bool projectLooksEmpty,
  }) {
    final context = contextLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ')
        .toLowerCase();
    final looksLikePython =
        context.contains('python') ||
        context.contains('pyproject') ||
        context.contains('requirements.txt') ||
        context.contains('argparse') ||
        context.contains('.py');
    if (!looksLikePython) {
      return const <ConversationWorkflowTask>[];
    }

    final supportsContinuous =
        context.contains('continuous') ||
        context.contains('loop') ||
        context.contains('infinite');
    final supportsJson = context.contains('json');
    final supportsMultiHost =
        context.contains('multiple hosts') ||
        context.contains('multi-host') ||
        context.contains('host list') ||
        context.contains('file-based host');

    final tasks = <ConversationWorkflowTask>[];
    if (projectLooksEmpty) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: 'Initialize project structure and requirements.txt',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['requirements.txt', 'README.md'],
          validationCommand: 'ls',
          notes: 'Create the initial project files for the CLI script.',
        ),
      );
    }

    tasks.add(
      ConversationWorkflowTask(
        id: _uuid.v4(),
        title: 'Implement core ping functionality and CLI arguments in main.py',
        status: ConversationWorkflowTaskStatus.pending,
        targetFiles: const ['main.py'],
        validationCommand: 'python3 main.py --help',
        notes: 'Use subprocess to call the system ping command.',
      ),
    );

    if (supportsMultiHost) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: 'Add multi-host input handling in main.py',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['main.py'],
          validationCommand: 'python3 main.py --help',
          notes: 'Support host lists or repeated host arguments.',
        ),
      );
    }

    if (supportsContinuous) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: 'Add continuous ping loop and interval options in main.py',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['main.py'],
          validationCommand: 'python3 main.py --help',
          notes: 'Add loop control flags without changing future tasks.',
        ),
      );
    }

    if (supportsJson) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: 'Add JSON output support in main.py',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['main.py'],
          validationCommand: 'python3 main.py --help',
          notes: 'Keep machine-readable output behind a flag.',
        ),
      );
    }

    if (tasks.length < 2) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title:
              'Add error handling for invalid or unreachable hosts in main.py',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['main.py'],
          validationCommand: 'python3 main.py --help',
          notes: 'Handle invalid host input and ping failures gracefully.',
        ),
      );
    }

    return tasks.take(4).toList(growable: false);
  }

  WorkflowTaskProposalDraft _finalizeTaskProposalDraft(
    WorkflowTaskProposalDraft proposal, {
    required _PlanningResearchContext researchContext,
  }) {
    final sanitizedTasks = _sanitizeTaskProposalTasks(proposal.tasks);
    final reorderedTasks = _reorderTaskProposalTasks(
      sanitizedTasks,
      projectLooksEmpty: _projectLooksEmptyForTaskPlanning(researchContext),
    );
    return WorkflowTaskProposalDraft(tasks: reorderedTasks);
  }

  List<ConversationWorkflowTask> _sanitizeTaskProposalTasks(
    Iterable<ConversationWorkflowTask> tasks,
  ) {
    final sanitizedTasks = <ConversationWorkflowTask>[];
    final emittedTitles = <String>{};

    for (final task in tasks) {
      final normalizedTitle = _normalizeTaskProposalTitle(task.title);
      if (normalizedTitle.isEmpty ||
          _isTaskProposalObservationTitle(normalizedTitle) ||
          _isTaskProposalLowQualityTitle(normalizedTitle)) {
        continue;
      }
      final normalizedTargetFiles = _normalizeTaskProposalTargetFiles(
        task.targetFiles,
      );
      final normalizedValidationCommand =
          _normalizeTaskProposalValidationCommandForTargets(
            task.validationCommand,
            normalizedTargetFiles,
          );
      final normalizedNotes = _normalizeTaskProposalTextField(task.notes);
      if (_looksLikeImplementationTaskTitle(normalizedTitle) &&
          task.targetFiles.isNotEmpty &&
          normalizedTargetFiles.isEmpty) {
        continue;
      }
      final dedupeKey = normalizedTitle.toLowerCase();
      if (!emittedTitles.add(dedupeKey)) {
        continue;
      }
      final normalizedTask = task.copyWith(
        title: normalizedTitle,
        targetFiles: normalizedTargetFiles,
        validationCommand: normalizedValidationCommand,
        notes: normalizedNotes,
      );
      if (sanitizedTasks.any(
        (existingTask) =>
            _taskProposalTasksLookNearDuplicate(existingTask, normalizedTask),
      )) {
        continue;
      }
      sanitizedTasks.add(normalizedTask);
      if (sanitizedTasks.length == 6) {
        break;
      }
    }

    return sanitizedTasks.toList(growable: false);
  }

  String _normalizeTaskProposalTitle(String value) {
    var candidate = value
        .trim()
        .replaceAll(RegExp('^[`"\']+|[`"\']+\$'), '')
        .replaceAll('`', '')
        .replaceAll('"', '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (candidate.isEmpty) {
      return '';
    }

    candidate = candidate.replaceFirst(
      RegExp(r'^(?:task\s*\d+\s*[:.-]\s*)', caseSensitive: false),
      '',
    );
    candidate = candidate.replaceFirst(
      RegExp(r'^(?:next step\s*[:.-]\s*)', caseSensitive: false),
      '',
    );
    candidate = candidate.replaceFirst(
      RegExp(r'^(?:i need to|need to)\s+', caseSensitive: false),
      '',
    );
    candidate = candidate.replaceFirst(
      RegExp(r'^(?:we need to|please)\s+', caseSensitive: false),
      '',
    );
    candidate = candidate.replaceFirst(
      RegExp(
        r'^(?:subsequent|following|next)\s+tasks?\s+(?:should|must|will)\s+(?:involve|include|cover)\s*:?\s*',
        caseSensitive: false,
      ),
      '',
    );
    candidate = candidate.replaceFirst(RegExp(r'[.。]+$'), '').trim();
    if (candidate.isEmpty) {
      return '';
    }

    final firstCharacter = candidate[0];
    if (RegExp(r'[a-z]').hasMatch(firstCharacter)) {
      candidate = '${firstCharacter.toUpperCase()}${candidate.substring(1)}';
    }
    return candidate;
  }

  bool _isTaskProposalObservationTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    if (_isTaskProposalPlaceholderTitle(normalized)) {
      return true;
    }

    const blockedPrefixes = <String>[
      'the project root seems ',
      'the project root is ',
      'the workspace seems ',
      'the workspace is ',
      'the repository seems ',
      'the repository is ',
      'current state:',
      'current state ',
      'recent context:',
      'recent context ',
      'research context:',
      'research context ',
      'there is ',
      'there are ',
    ];
    if (blockedPrefixes.any(normalized.startsWith)) {
      return true;
    }

    const blockedFragments = <String>[
      'based on research context',
      'current state',
      'recent context',
      'research context',
      'proposal image',
      'looks empty',
      'seems empty',
    ];
    return blockedFragments.any(normalized.contains);
  }

  bool _isTaskProposalLowQualityTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    if (title.contains('?') || title.contains('？')) {
      return true;
    }
    if (title.endsWith(':') || title.endsWith('：')) {
      return true;
    }

    const blockedPrefixes = <String>[
      'should ',
      'which ',
      'what ',
      'how ',
      'why ',
      'when ',
      'where ',
      'who ',
    ];
    if (blockedPrefixes.any(normalized.startsWith)) {
      return true;
    }

    const blockedFragments = <String>[
      "i'll assume",
      'if i were implementing',
      'for simplicity',
      'or just pick one',
      'what would you like to do next',
      'i will assume',
      'the prompt says',
      'saved task',
      'task id',
    ];
    return blockedFragments.any(normalized.contains);
  }

  List<String> _normalizeTaskProposalTargetFiles(Iterable<String> paths) {
    final normalizedPaths = <String>[];
    final emitted = <String>{};

    for (final rawPath in paths) {
      final normalizedPath = _normalizeTaskProposalTargetFile(rawPath);
      if (normalizedPath.isEmpty) {
        continue;
      }
      final dedupeKey = normalizedPath.toLowerCase();
      if (!emitted.add(dedupeKey)) {
        continue;
      }
      normalizedPaths.add(normalizedPath);
    }

    return normalizedPaths.toList(growable: false);
  }

  String _normalizeTaskProposalTargetFile(String value) {
    var candidate = value.trim().replaceAll('\\', '/');
    if (candidate.isEmpty) {
      return '';
    }
    if (_looksLikePlaceholderTaskProposalValue(candidate)) {
      return '';
    }

    candidate = candidate.replaceFirst(RegExp(r'^\./'), '');
    if (!_looksLikeTaskProposalTargetPath(candidate)) {
      return '';
    }
    final lowerCandidate = candidate.toLowerCase();
    if (lowerCandidate == 'readme.py' ||
        lowerCandidate.endsWith('/readme.py')) {
      return candidate.replaceFirst(
        RegExp(r'readme\.py$', caseSensitive: false),
        'README.md',
      );
    }
    return candidate;
  }

  bool _looksLikeTaskProposalTargetPath(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty || candidate.length > 180) {
      return false;
    }

    final lowerCandidate = candidate.toLowerCase();
    if (RegExp(r'\s').hasMatch(candidate)) {
      return false;
    }
    if (lowerCandidate.startsWith('ls-') ||
        lowerCandidate.startsWith('cat-') ||
        lowerCandidate.startsWith('python-') ||
        lowerCandidate.startsWith('python3-')) {
      return false;
    }

    const knownRootFiles = <String>{
      '.dockerignore',
      '.gitignore',
      'dockerfile',
      'license',
      'makefile',
      'package.json',
      'pyproject.toml',
      'readme',
      'readme.md',
      'requirements.txt',
      'pubspec.yaml',
    };
    if (knownRootFiles.contains(lowerCandidate)) {
      return true;
    }
    if (candidate.contains('/')) {
      return true;
    }
    return RegExp(
      r'^[A-Za-z0-9_.-]+\.[A-Za-z][A-Za-z0-9_.-]{0,15}$',
    ).hasMatch(candidate);
  }

  String _normalizeTaskProposalTextField(String value) {
    final candidate = value.trim();
    if (_looksLikePlaceholderTaskProposalValue(candidate)) {
      return '';
    }
    return candidate;
  }

  String _normalizeTaskProposalValidationCommand(String value) {
    final candidate = _normalizeTaskProposalTextField(value);
    if (candidate.isEmpty) {
      return '';
    }

    final portablePython = candidate.replaceFirst(
      RegExp(r'^python(\s+|$)'),
      'python3 ',
    );
    final portableLs = portablePython.replaceFirst(
      RegExp(r'^ls\s+-F(\s+|$)'),
      'ls ',
    );
    final normalized = portableLs.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_looksLikeUnboundedPingValidationCommand(normalized)) {
      return '$normalized -c 1';
    }
    return normalized;
  }

  String _normalizeTaskProposalValidationCommandForTargets(
    String value,
    List<String> targetFiles,
  ) {
    final normalized = _normalizeTaskProposalValidationCommand(value);
    if (_looksLikeRequirementsAstValidationCommand(normalized, targetFiles)) {
      return 'ls requirements.txt';
    }
    return normalized;
  }

  bool _looksLikeRequirementsAstValidationCommand(
    String validationCommand,
    List<String> targetFiles,
  ) {
    final normalized = validationCommand.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (!normalized.startsWith('python3 -c ') &&
        !normalized.startsWith('python -c ')) {
      return false;
    }
    if (!normalized.contains('ast.parse') ||
        !normalized.contains('requirements.txt')) {
      return false;
    }
    return targetFiles.any((path) {
      final normalizedPath = path.trim().replaceAll('\\', '/').toLowerCase();
      return normalizedPath == 'requirements.txt' ||
          normalizedPath.endsWith('/requirements.txt');
    });
  }

  bool _looksLikePlaceholderTaskProposalValue(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'string' ||
        normalized == 'todo' ||
        normalized == 'tbd' ||
        normalized == 'n/a';
  }

  bool _taskProposalNeedsRetry(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
  ) {
    if (finalized.tasks.isEmpty) {
      return true;
    }

    final removedCount = original.tasks.length - finalized.tasks.length;
    if (removedCount >= 2 && finalized.tasks.length <= 1) {
      return true;
    }

    if (projectLooksEmpty && finalized.tasks.length < 2) {
      return true;
    }

    if (projectLooksEmpty &&
        !_taskProposalHasImplementationFollowUp(finalized.tasks)) {
      return true;
    }

    if (projectLooksEmpty &&
        _taskProposalHasWeakImplementationValidation(finalized.tasks)) {
      return true;
    }

    if (projectLooksEmpty &&
        _taskProposalHasUnsupportedPythonVerificationValidation(
          finalized.tasks,
        )) {
      return true;
    }

    if (projectLooksEmpty &&
        _taskProposalHasThirdPartyPythonRuntimeDependencyRisk(
          finalized.tasks,
        )) {
      return true;
    }

    if (projectLooksEmpty &&
        _taskProposalHasFragmentedSingleFileImplementation(finalized.tasks)) {
      return true;
    }

    if (_taskProposalHasUnboundedPingVerificationValidation(finalized.tasks)) {
      return true;
    }

    if (_taskProposalHasDuplicateVerificationTasks(finalized.tasks)) {
      return true;
    }

    if (_taskProposalHasNearDuplicateTasks(finalized.tasks)) {
      return true;
    }

    if (finalized.tasks.length == 1 &&
        _looksLikeGenericScaffoldOnlyTask(finalized.tasks.first)) {
      return true;
    }

    return false;
  }

  bool _taskProposalNeedsRetryForWorkflow(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
    ConversationWorkflowSpec workflowSpec,
  ) {
    final violatesExplicitFirstSlice =
        _taskProposalViolatesExplicitFirstSliceTargets(
          finalized.tasks,
          workflowSpec,
          projectLooksEmpty: projectLooksEmpty,
        );
    if (violatesExplicitFirstSlice) {
      return true;
    }

    if (!_taskProposalNeedsRetry(original, finalized, projectLooksEmpty)) {
      return false;
    }
    if (_workflowAllowsExplicitSingleTaskProposal(
      finalized,
      workflowSpec,
      projectLooksEmpty: projectLooksEmpty,
    )) {
      return false;
    }
    return !_workflowAllowsSingleReadmeTask(finalized, workflowSpec);
  }

  bool _workflowAllowsExplicitSingleTaskProposal(
    WorkflowTaskProposalDraft finalized,
    ConversationWorkflowSpec workflowSpec, {
    required bool projectLooksEmpty,
  }) {
    if (!projectLooksEmpty ||
        finalized.tasks.length != 1 ||
        !_workflowPrefersExplicitSingleTask(workflowSpec)) {
      return false;
    }

    final task = finalized.tasks.single;
    if (_looksLikeVerificationTaskProposal(task) ||
        _looksLikeGenericScaffoldOnlyTask(task) ||
        task.validationCommand.trim().isEmpty) {
      return false;
    }

    final targets = task.targetFiles
        .map((path) => path.trim().replaceAll('\\', '/').toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    if (targets.isEmpty) {
      return false;
    }

    final requiredTargets = _explicitSingleTaskTargetFiles(workflowSpec);
    if (requiredTargets.isNotEmpty &&
        requiredTargets.any((target) => !targets.contains(target))) {
      return false;
    }

    return task.targetFiles.any(_looksLikeImplementationTargetFile);
  }

  bool _workflowPrefersExplicitSingleTask(
    ConversationWorkflowSpec workflowSpec,
  ) {
    final context = _workflowSpecText(workflowSpec);
    if (context.isEmpty) {
      return false;
    }

    final exactTaskConstraint =
        context.contains('exactly one implementation task') ||
        context.contains('exactly one task') ||
        context.contains('single implementation task') ||
        context.contains('single approved task') ||
        context.contains('one implementation task');
    if (exactTaskConstraint) {
      return true;
    }

    final singleFileConstraint =
        context.contains('single-file') ||
        context.contains('single file') ||
        context.contains('only create') ||
        context.contains('create only') ||
        context.contains('no other files') ||
        context.contains('root-level');
    return singleFileConstraint &&
        _explicitSingleTaskTargetFiles(workflowSpec).isNotEmpty;
  }

  Set<String> _explicitSingleTaskTargetFiles(
    ConversationWorkflowSpec workflowSpec,
  ) {
    final context = _workflowSpecText(workflowSpec);
    if (context.isEmpty) {
      return const <String>{};
    }

    const knownSingleTaskFiles = <String>{
      'ping_cli.py',
      'main.py',
      'health_check.py',
      'health_checker.py',
    };
    return knownSingleTaskFiles.where((path) => context.contains(path)).toSet();
  }

  String _workflowSpecText(ConversationWorkflowSpec workflowSpec) {
    return [
      workflowSpec.goal,
      ...workflowSpec.constraints,
      ...workflowSpec.acceptanceCriteria,
      ...workflowSpec.openQuestions,
    ].join(' ').toLowerCase();
  }

  bool _taskProposalViolatesExplicitFirstSliceTargets(
    List<ConversationWorkflowTask> tasks,
    ConversationWorkflowSpec workflowSpec, {
    required bool projectLooksEmpty,
  }) {
    if (!projectLooksEmpty || tasks.isEmpty) {
      return false;
    }

    final requiredTargets = _explicitFirstSliceTargetFiles(workflowSpec);
    if (requiredTargets.isEmpty) {
      return false;
    }

    final firstTask = tasks.first;
    if (_looksLikeVerificationTaskProposal(firstTask)) {
      return true;
    }

    final firstTaskTargets = firstTask.targetFiles
        .map((path) => path.trim().replaceAll('\\', '/').toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    return requiredTargets.any((target) => !firstTaskTargets.contains(target));
  }

  Set<String> _explicitFirstSliceTargetFiles(
    ConversationWorkflowSpec workflowSpec,
  ) {
    final context = [
      workflowSpec.goal,
      ...workflowSpec.constraints,
      ...workflowSpec.acceptanceCriteria,
      ...workflowSpec.openQuestions,
    ].join(' ').toLowerCase();
    if (context.isEmpty) {
      return const <String>{};
    }

    final mentionsFirstSlice =
        context.contains('first slice') ||
        context.contains('initial slice') ||
        context.contains('first implementation slice') ||
        context.contains('initial implementation slice');
    final constrainsSlice =
        mentionsFirstSlice &&
        (context.contains(' only') ||
            context.contains('limited to') ||
            context.contains('create only') ||
            context.contains('contain exactly') ||
            context.contains('must contain'));
    final requiresReadmeAndRequirements =
        context.contains('requirements.txt') &&
        (context.contains('readme.md') || context.contains('readme'));
    if (!constrainsSlice && !requiresReadmeAndRequirements) {
      return const <String>{};
    }

    const knownFirstSliceFiles = <String>{
      'requirements.txt',
      'readme.md',
      'pyproject.toml',
      '.gitignore',
      'main.py',
      'ping_cli.py',
    };
    return knownFirstSliceFiles.where((path) => context.contains(path)).toSet();
  }

  bool _workflowAllowsSingleReadmeTask(
    WorkflowTaskProposalDraft finalized,
    ConversationWorkflowSpec workflowSpec,
  ) {
    if (finalized.tasks.length != 1) {
      return false;
    }

    final task = finalized.tasks.single;
    final targetFiles = task.targetFiles
        .map((path) => path.trim().toLowerCase())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (targetFiles.isEmpty ||
        !targetFiles.every((path) => path == 'readme.md')) {
      return false;
    }

    final context = [
      workflowSpec.goal,
      ...workflowSpec.constraints,
      ...workflowSpec.acceptanceCriteria,
      ...workflowSpec.openQuestions,
    ].join(' ').toLowerCase();
    final explicitlyReadmeOnly =
        context.contains('readme.md only') ||
        context.contains('limited to readme.md') ||
        context.contains('readme first slice') ||
        context.contains('exactly one task') ||
        context.contains('single task') ||
        context.contains('no python source files') ||
        context.contains('no source files');
    return explicitlyReadmeOnly && task.validationCommand.trim().isNotEmpty;
  }

  bool _taskProposalHasImplementationFollowUp(
    List<ConversationWorkflowTask> tasks,
  ) {
    return tasks.any((task) => !_looksLikeGenericScaffoldOnlyTask(task));
  }

  bool _taskProposalHasDuplicateVerificationTasks(
    List<ConversationWorkflowTask> tasks,
  ) {
    final seenSignatures = <String>{};
    final seenValidationSignatures = <String>{};
    for (final task in tasks) {
      if (!_looksLikeVerificationTaskProposal(task)) {
        continue;
      }
      final signature = _verificationTaskSignature(task);
      if (signature.isNotEmpty && !seenSignatures.add(signature)) {
        return true;
      }
      final validationSignature = _verificationTaskValidationSignature(task);
      if (validationSignature.isNotEmpty &&
          !seenValidationSignatures.add(validationSignature)) {
        return true;
      }
    }
    return false;
  }

  bool _taskProposalHasUnsupportedPythonVerificationValidation(
    List<ConversationWorkflowTask> tasks,
  ) {
    for (final task in tasks) {
      if (!_looksLikeVerificationTaskProposal(task)) {
        continue;
      }
      final normalizedValidation = task.validationCommand.trim().toLowerCase();
      if (normalizedValidation.startsWith('pytest') ||
          normalizedValidation.startsWith('python -m pytest') ||
          normalizedValidation.startsWith('python3 -m pytest')) {
        return true;
      }
    }
    return false;
  }

  bool _taskProposalHasUnboundedPingVerificationValidation(
    List<ConversationWorkflowTask> tasks,
  ) {
    for (final task in tasks) {
      final normalizedContext = '${task.title.trim()} ${task.notes.trim()}'
          .toLowerCase();
      if (!normalizedContext.contains('ping')) {
        continue;
      }

      final normalizedValidation = task.validationCommand.trim().toLowerCase();
      if (normalizedValidation.isEmpty) {
        continue;
      }
      if (_looksLikeBoundedPingValidationCommand(normalizedValidation)) {
        continue;
      }
      if (_looksLikeUnboundedPingValidationCommand(normalizedValidation)) {
        return true;
      }
    }
    return false;
  }

  bool _taskProposalHasThirdPartyPythonRuntimeDependencyRisk(
    List<ConversationWorkflowTask> tasks,
  ) {
    const riskyFragments = <String>[
      'ping3',
      'icmplib',
      'ping library',
      'third-party',
      'external dependency',
      'external package',
    ];

    for (final task in tasks) {
      if (!_looksLikeImplementationTaskTitle(task.title)) {
        continue;
      }

      final hasPythonTarget = task.targetFiles.any(
        (path) => path.trim().toLowerCase().endsWith('.py'),
      );
      if (!hasPythonTarget) {
        continue;
      }

      final hasDependencyManifestTarget = task.targetFiles.any((path) {
        final normalizedPath = path.trim().toLowerCase();
        return normalizedPath.endsWith('requirements.txt') ||
            normalizedPath.endsWith('pyproject.toml') ||
            normalizedPath.endsWith('setup.py') ||
            normalizedPath.endsWith('setup.cfg');
      });
      if (hasDependencyManifestTarget) {
        continue;
      }

      final normalizedContext = '${task.title.trim()} ${task.notes.trim()}'
          .toLowerCase();
      if (riskyFragments.any(normalizedContext.contains)) {
        return true;
      }
    }

    return false;
  }

  bool _taskProposalHasFragmentedSingleFileImplementation(
    List<ConversationWorkflowTask> tasks,
  ) {
    final implementationCounts = <String, int>{};

    for (final task in tasks) {
      if (_looksLikeVerificationTaskProposal(task) ||
          !_looksLikeImplementationTaskTitle(task.title)) {
        continue;
      }

      final normalizedTargets = _taskProposalDuplicateTargets(task)
          .map((path) => path.toLowerCase())
          .where(_looksLikeImplementationTargetFile)
          .toSet();
      if (normalizedTargets.length != 1) {
        continue;
      }

      final target = normalizedTargets.first;
      implementationCounts.update(
        target,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (implementationCounts[target]! >= 2) {
        return true;
      }
    }

    return false;
  }

  bool _taskProposalHasNearDuplicateTasks(
    List<ConversationWorkflowTask> tasks,
  ) {
    for (var index = 0; index < tasks.length; index += 1) {
      for (
        var nextIndex = index + 1;
        nextIndex < tasks.length;
        nextIndex += 1
      ) {
        if (_taskProposalTasksLookNearDuplicate(
          tasks[index],
          tasks[nextIndex],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _taskProposalTasksLookNearDuplicate(
    ConversationWorkflowTask left,
    ConversationWorkflowTask right,
  ) {
    if (_looksLikeVerificationTaskProposal(left) ||
        _looksLikeVerificationTaskProposal(right)) {
      return false;
    }

    final leftTargets = _taskProposalDuplicateTargets(left)
        .map((path) => path.toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    final rightTargets = _taskProposalDuplicateTargets(right)
        .map((path) => path.toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    if (leftTargets.isEmpty || rightTargets.isEmpty) {
      return false;
    }

    final sharedTargets = leftTargets.intersection(rightTargets);
    if (sharedTargets.isEmpty) {
      return false;
    }

    final leftTokens = _taskProposalSemanticTitleTokens(left.title);
    final rightTokens = _taskProposalSemanticTitleTokens(right.title);
    if (leftTokens.length < 2 || rightTokens.length < 2) {
      return false;
    }

    final overlap = leftTokens.intersection(rightTokens);
    if (overlap.length < 2) {
      return false;
    }

    final smallerTokenCount = leftTokens.length <= rightTokens.length
        ? leftTokens.length
        : rightTokens.length;
    if (smallerTokenCount < 2) {
      return false;
    }

    return overlap.length == smallerTokenCount ||
        overlap.length / smallerTokenCount >= 0.75;
  }

  Iterable<String> _taskProposalDuplicateTargets(
    ConversationWorkflowTask task,
  ) {
    final normalizedTargets = _normalizeTaskProposalTargetFiles(
      task.targetFiles,
    );
    if (normalizedTargets.isNotEmpty) {
      return normalizedTargets;
    }
    return _extractTaskProposalTitleTargetHints(task.title);
  }

  Iterable<String> _extractTaskProposalTitleTargetHints(String title) {
    final matches = RegExp(
      r'(?:(?:^|[\s`"(]))([A-Za-z0-9_./-]+\.[A-Za-z][A-Za-z0-9]{0,7}|__init__\.py|\.gitignore)(?=$|[\s`)",.:;])',
    ).allMatches(title);
    final paths = <String>[];
    for (final match in matches) {
      final value = match.group(1)?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      final normalized = _normalizeTaskProposalTargetFiles(<String>[value]);
      if (normalized.isEmpty) {
        continue;
      }
      paths.addAll(normalized);
    }
    return paths;
  }

  Set<String> _taskProposalSemanticTitleTokens(String title) {
    const ignoredTokens = <String>{
      'a',
      'an',
      'and',
      'add',
      'build',
      'core',
      'create',
      'file',
      'files',
      'for',
      'functionality',
      'implement',
      'implementation',
      'in',
      'interface',
      'main',
      'module',
      'on',
      'script',
      'task',
      'the',
      'to',
      'tool',
      'update',
      'with',
      'write',
    };
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty && !ignoredTokens.contains(token))
        .toSet();
  }

  bool _taskProposalHasWeakImplementationValidation(
    List<ConversationWorkflowTask> tasks,
  ) {
    for (final task in tasks) {
      if (_looksLikeScaffoldTask(task)) {
        continue;
      }
      final implementationTargets = task.targetFiles
          .where(_looksLikeImplementationTargetFile)
          .toList(growable: false);
      if (implementationTargets.isEmpty) {
        continue;
      }
      if (_hasWeakImplementationValidationCommand(
        task.validationCommand,
        implementationTargets,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikeGenericScaffoldOnlyTask(ConversationWorkflowTask task) {
    if (!_looksLikeScaffoldTask(task)) {
      return false;
    }

    final normalizedTitle = task.title.trim().toLowerCase();
    const genericSignals = <String>[
      'initialize project structure',
      'initialize project scaffolding',
      'initialize the project structure',
      'initialize the project scaffolding',
      'set up project structure',
      'setup project structure',
      'create initial project structure',
      'create project scaffolding',
      'project structure',
      'project scaffolding',
    ];
    if (genericSignals.contains(normalizedTitle)) {
      return true;
    }

    return !task.targetFiles.any(_looksLikeImplementationTargetFile);
  }

  bool _looksLikeVerificationTaskProposal(ConversationWorkflowTask task) {
    final normalized = '${task.title.trim()} ${task.notes.trim()}'
        .toLowerCase();
    const titleSignals = <String>[
      'verify ',
      'verification',
      'real host',
      'live host',
      'smoke test',
      'manual test',
    ];
    return titleSignals.any(normalized.contains);
  }

  String _verificationTaskSignature(ConversationWorkflowTask task) {
    final normalizedTitle = task.title.trim().toLowerCase();
    if (normalizedTitle.isEmpty) {
      return '';
    }
    final canonicalTitle = normalizedTitle
        .replaceAll(RegExp(r'\b(real|live|actual)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .where(
          (token) =>
              token.isNotEmpty &&
              !const <String>{
                'verify',
                'verification',
                'validate',
                'validating',
                'with',
                'a',
                'an',
                'the',
                'for',
                'using',
                'execution',
                'functionality',
                'output',
                'outputs',
                'result',
                'results',
              }.contains(token),
        )
        .join(' ');
    final targetKey = _taskProposalDuplicateTargets(task)
        .map((path) => path.toLowerCase())
        .where((path) => path.isNotEmpty)
        .join('|');
    if (canonicalTitle.isEmpty) {
      return targetKey;
    }
    return '$canonicalTitle::$targetKey';
  }

  String _verificationTaskValidationSignature(ConversationWorkflowTask task) {
    final targetKey = _taskProposalDuplicateTargets(task)
        .map((path) => path.toLowerCase())
        .where((path) => path.isNotEmpty)
        .join('|');
    final validationKey = _normalizeTaskProposalValidationCommand(
      task.validationCommand,
    ).toLowerCase();
    if (targetKey.isEmpty || validationKey.isEmpty) {
      return '';
    }
    return '$targetKey::$validationKey';
  }

  bool _looksLikeImplementationTargetFile(String path) {
    final normalizedPath = path.trim().toLowerCase();
    if (normalizedPath.isEmpty) {
      return false;
    }

    if (normalizedPath == 'readme.md' ||
        normalizedPath == '.gitignore' ||
        normalizedPath == 'requirements.txt' ||
        normalizedPath == 'pyproject.toml') {
      return false;
    }

    if (normalizedPath.endsWith('/__init__.py')) {
      return false;
    }

    return normalizedPath.endsWith('.py') ||
        normalizedPath.endsWith('.dart') ||
        normalizedPath.endsWith('.ts') ||
        normalizedPath.endsWith('.tsx') ||
        normalizedPath.endsWith('.js') ||
        normalizedPath.endsWith('.jsx') ||
        normalizedPath.endsWith('.rs') ||
        normalizedPath.endsWith('.go') ||
        normalizedPath.endsWith('.java') ||
        normalizedPath.endsWith('.kt');
  }

  bool _looksLikeImplementationTaskTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const signals = <String>[
      'implement ',
      'build ',
      'create cli',
      'add cli',
      'core ',
      'functionality',
      'entrypoint',
    ];
    return signals.any(normalized.contains);
  }

  bool _hasWeakImplementationValidationCommand(
    String validationCommand,
    List<String> implementationTargets,
  ) {
    final normalized = validationCommand.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    if (normalized.contains('module importable') ||
        normalized.contains('sys.path.append(') ||
        normalized.contains('sys.path.insert(')) {
      return true;
    }
    if (normalized.startsWith('ls ') ||
        normalized == 'ls' ||
        normalized.startsWith('find ') ||
        normalized.startsWith('cat ') ||
        normalized.startsWith('test -f ') ||
        normalized.startsWith('test -d ')) {
      return true;
    }

    final targetSignals = implementationTargets
        .map((path) => path.trim().toLowerCase())
        .where((path) => path.isNotEmpty)
        .expand(
          (path) => <String>{
            path,
            path.split('/').last,
            path.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          },
        )
        .where((signal) => signal.isNotEmpty)
        .toSet();
    if (targetSignals.any(normalized.contains)) {
      return false;
    }

    const acceptablePrefixes = <String>[
      'pytest',
      'python -m pytest',
      'python3 -m pytest',
      'dart test',
      'flutter test',
      'cargo test',
      'go test',
      'npm test',
      'pnpm test',
      'yarn test',
    ];
    if (acceptablePrefixes.any(normalized.startsWith)) {
      return false;
    }

    return true;
  }

  bool _looksLikeBoundedPingValidationCommand(String normalizedValidation) {
    return normalizedValidation.contains('--help') ||
        RegExp(r'(^|\s)-c(\s|$)').hasMatch(normalizedValidation) ||
        RegExp(r'(^|\s)--count(?:=|\s)').hasMatch(normalizedValidation) ||
        normalizedValidation.contains('unittest') ||
        normalizedValidation.contains('test_') ||
        normalizedValidation.contains('verify_');
  }

  bool _looksLikeUnboundedPingValidationCommand(String normalizedValidation) {
    final launchesPythonEntryPoint = RegExp(
      r'^(python|python3)\s+\S+\.py(?:\s|$)',
    ).hasMatch(normalizedValidation);
    if (!launchesPythonEntryPoint) {
      return false;
    }

    final includesHostTarget =
        normalizedValidation.contains('127.0.0.1') ||
        normalizedValidation.contains('localhost') ||
        RegExp(
          r'(^|\s)(?:\d{1,3}\.){3}\d{1,3}(\s|$)',
        ).hasMatch(normalizedValidation) ||
        RegExp(
          r'(^|\s)[a-z0-9.-]+\.[a-z]{2,}(\s|$)',
        ).hasMatch(normalizedValidation);
    if (!includesHostTarget) {
      return false;
    }

    return !normalizedValidation.contains('--help');
  }

  bool _isTaskProposalPlaceholderTitle(String normalizedTitle) {
    const placeholderTitles = <String>[
      'subsequent tasks should involve',
      'subsequent tasks should include',
      'following tasks should involve',
      'following tasks should include',
      'next tasks should involve',
      'next tasks should include',
      'subsequent task should involve',
      'subsequent task should include',
    ];
    final compact = normalizedTitle.replaceAll(':', '').trim();
    if (placeholderTitles.contains(compact)) {
      return true;
    }
    return RegExp(
      r'^(?:subsequent|following|next)\s+tasks?\s+(?:should|must|will)\s+(?:involve|include|cover)(?::)?$',
      caseSensitive: false,
    ).hasMatch(normalizedTitle);
  }

  List<ConversationWorkflowTask> _reorderTaskProposalTasks(
    List<ConversationWorkflowTask> tasks, {
    required bool projectLooksEmpty,
  }) {
    if (!projectLooksEmpty || tasks.length < 2) {
      return tasks.toList(growable: false);
    }

    final scaffoldIndex = tasks.indexWhere(_looksLikeScaffoldTask);
    if (scaffoldIndex <= 0) {
      return tasks.toList(growable: false);
    }

    final reordered = <ConversationWorkflowTask>[
      tasks[scaffoldIndex],
      ...tasks.take(scaffoldIndex),
      ...tasks.skip(scaffoldIndex + 1),
    ];
    return reordered.take(6).toList(growable: false);
  }
}
