import '../entities/tool_call_info.dart';

enum ContextSurgeryBlockKind {
  systemPrompt,
  repoMap,
  agentsMarkdown,
  memory,
  planDocument,
  workflowProjection,
  toolResult,
  fileReadToolResult,
  fileSearchToolResult,
  commandToolResult,
  sideEffectToolResult,
}

class ContextSurgeryBlockObservation {
  const ContextSurgeryBlockObservation({
    required this.kind,
    required this.label,
    required this.charCount,
    this.sourceIndex,
    this.identifier,
  });

  final ContextSurgeryBlockKind kind;
  final String label;
  final int charCount;
  final int? sourceIndex;
  final String? identifier;

  int get estimatedTokens {
    if (charCount <= 0) return 0;
    return (charCount / 4).ceil();
  }
}

enum ContextSurgeryCandidateReason { supersededFileRead, supersededFileSearch }

class ContextSurgeryToolResultCandidate {
  const ContextSurgeryToolResultCandidate({
    required this.index,
    required this.replacedByIndex,
    required this.toolName,
    required this.reason,
    required this.identifier,
    required this.charCount,
    required this.replacementStub,
  });

  final int index;
  final int replacedByIndex;
  final String toolName;
  final ContextSurgeryCandidateReason reason;
  final String identifier;
  final int charCount;
  final String replacementStub;
}

class ContextSurgerySectionSummary {
  const ContextSurgerySectionSummary({
    required this.kind,
    required this.label,
    required this.blockCount,
    required this.charCount,
  });

  final ContextSurgeryBlockKind kind;
  final String label;
  final int blockCount;
  final int charCount;

  int get estimatedTokens {
    if (charCount <= 0) return 0;
    return (charCount / 4).ceil();
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ContextSurgerySectionSummary &&
            other.kind == kind &&
            other.label == label &&
            other.blockCount == blockCount &&
            other.charCount == charCount;
  }

  @override
  int get hashCode => Object.hash(kind, label, blockCount, charCount);
}

class ContextSurgeryObservationSnapshot {
  const ContextSurgeryObservationSnapshot({
    this.sections = const [],
    this.staleToolResultCandidateCount = 0,
    this.staleToolResultEstimatedTokens = 0,
  });

  static const empty = ContextSurgeryObservationSnapshot();

  final List<ContextSurgerySectionSummary> sections;
  final int staleToolResultCandidateCount;
  final int staleToolResultEstimatedTokens;

  bool get hasData =>
      sections.isNotEmpty ||
      staleToolResultCandidateCount > 0 ||
      staleToolResultEstimatedTokens > 0;

  ContextSurgerySectionSummary? section(ContextSurgeryBlockKind kind) {
    for (final section in sections) {
      if (section.kind == kind) return section;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ContextSurgeryObservationSnapshot &&
            other.staleToolResultCandidateCount ==
                staleToolResultCandidateCount &&
            other.staleToolResultEstimatedTokens ==
                staleToolResultEstimatedTokens &&
            _listEquals(other.sections, sections);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(sections),
    staleToolResultCandidateCount,
    staleToolResultEstimatedTokens,
  );
}

class ContextSurgeryObservationService {
  ContextSurgeryObservationService._();

  static const Set<String> _fileReadToolNames = {'read_file', 'inspect_file'};
  static const Set<String> _fileSearchToolNames = {
    'find_files',
    'search_files',
    'list_directory',
  };
  static const Set<String> _commandToolNames = {
    'local_execute_command',
    'run_tests',
    'git_execute_command',
  };
  static const Set<String> _sideEffectToolNames = {
    'write_file',
    'edit_file',
    'rollback_last_file_change',
    'process_start',
    'process_cancel',
    'browser_click',
    'browser_fill',
    'browser_select',
    'browser_submit',
    'browser_press_key',
    'browser_navigate',
  };

  static List<ContextSurgeryBlockObservation> observeSystemPrompt(
    String prompt,
  ) {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) return const [];

    final observations = <ContextSurgeryBlockObservation>[
      ContextSurgeryBlockObservation(
        kind: ContextSurgeryBlockKind.systemPrompt,
        label: 'system_prompt',
        charCount: trimmedPrompt.length,
      ),
    ];
    observations.addAll(
      _taggedBlockObservations(
        prompt,
        tag: 'repo_map',
        kind: ContextSurgeryBlockKind.repoMap,
      ),
    );
    observations.addAll(
      _taggedBlockObservations(
        prompt,
        tag: 'agents_md',
        kind: ContextSurgeryBlockKind.agentsMarkdown,
      ),
    );
    observations.addAll(
      _sectionObservation(
        prompt,
        startMarker: 'Use the following context from past conversations',
        label: 'memory_context',
        kind: ContextSurgeryBlockKind.memory,
      ),
    );
    observations.addAll(
      _sectionObservation(
        prompt,
        startMarker: 'Approved plan document for this coding thread',
        label: 'approved_plan_document',
        kind: ContextSurgeryBlockKind.planDocument,
      ),
    );
    observations.addAll(
      _sectionObservation(
        prompt,
        startMarker: 'Current plan document draft for this coding thread',
        label: 'planning_plan_document',
        kind: ContextSurgeryBlockKind.planDocument,
      ),
    );
    observations.addAll(
      _sectionObservation(
        prompt,
        startMarker: 'Current workflow stage for this coding thread',
        label: 'workflow_projection',
        kind: ContextSurgeryBlockKind.workflowProjection,
      ),
    );
    return observations;
  }

  static List<ContextSurgeryBlockObservation> observeToolResults(
    List<ToolResultInfo> toolResults,
  ) {
    return [
      for (var index = 0; index < toolResults.length; index += 1)
        ContextSurgeryBlockObservation(
          kind: _toolResultKind(toolResults[index].name),
          label: toolResults[index].name,
          charCount: toolResults[index].result.length,
          sourceIndex: index,
          identifier: _toolResultIdentifier(toolResults[index]),
        ),
    ];
  }

  static List<ContextSurgeryToolResultCandidate> findStaleToolResultCandidates(
    List<ToolResultInfo> toolResults, {
    Set<String> protectedPaths = const {},
  }) {
    final normalizedProtectedPaths = protectedPaths
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toSet();
    final latestIndexByKey = <String, int>{};
    for (var index = 0; index < toolResults.length; index += 1) {
      final key = _staleCandidateKey(toolResults[index]);
      if (key == null) continue;
      latestIndexByKey[key] = index;
    }

    final candidates = <ContextSurgeryToolResultCandidate>[];
    for (var index = 0; index < toolResults.length; index += 1) {
      final toolResult = toolResults[index];
      final key = _staleCandidateKey(toolResult);
      if (key == null) continue;
      final replacedByIndex = latestIndexByKey[key];
      if (replacedByIndex == null || replacedByIndex <= index) continue;
      final path = _primaryPath(toolResult);
      if (path != null &&
          normalizedProtectedPaths.contains(_normalizePath(path))) {
        continue;
      }
      final reason = _fileReadToolNames.contains(toolResult.name)
          ? ContextSurgeryCandidateReason.supersededFileRead
          : ContextSurgeryCandidateReason.supersededFileSearch;
      final identifier = _toolResultIdentifier(toolResult) ?? toolResult.name;
      candidates.add(
        ContextSurgeryToolResultCandidate(
          index: index,
          replacedByIndex: replacedByIndex,
          toolName: toolResult.name,
          reason: reason,
          identifier: identifier,
          charCount: toolResult.result.length,
          replacementStub: _replacementStub(
            toolResult: toolResult,
            identifier: identifier,
            replacedByIndex: replacedByIndex,
          ),
        ),
      );
    }
    return candidates;
  }

  static ContextSurgeryObservationSnapshot buildSnapshot({
    String? systemPrompt,
    List<ToolResultInfo> toolResults = const [],
    Set<String> protectedPaths = const {},
  }) {
    final observations = <ContextSurgeryBlockObservation>[
      if (systemPrompt != null) ...observeSystemPrompt(systemPrompt),
      ...observeToolResults(toolResults),
    ];
    final staleCandidates = findStaleToolResultCandidates(
      toolResults,
      protectedPaths: protectedPaths,
    );
    return ContextSurgeryObservationSnapshot(
      sections: _summarizeObservations(observations),
      staleToolResultCandidateCount: staleCandidates.length,
      staleToolResultEstimatedTokens: staleCandidates.fold<int>(
        0,
        (sum, candidate) => sum + _estimatedTokens(candidate.charCount),
      ),
    );
  }

  static List<ContextSurgerySectionSummary> _summarizeObservations(
    List<ContextSurgeryBlockObservation> observations,
  ) {
    final summariesByKind =
        <ContextSurgeryBlockKind, _MutableContextSurgerySectionSummary>{};
    for (final observation in observations) {
      final summary = summariesByKind.putIfAbsent(
        observation.kind,
        () => _MutableContextSurgerySectionSummary(
          kind: observation.kind,
          label: _sectionLabel(observation.kind, observation.label),
        ),
      );
      summary
        ..blockCount += 1
        ..charCount += observation.charCount;
    }
    return [
      for (final kind in ContextSurgeryBlockKind.values)
        if (summariesByKind[kind] case final summary?) summary.toImmutable(),
    ];
  }

  static List<ContextSurgeryBlockObservation> _taggedBlockObservations(
    String prompt, {
    required String tag,
    required ContextSurgeryBlockKind kind,
  }) {
    final pattern = RegExp(
      '<$tag>\\s*([\\s\\S]*?)\\s*</$tag>',
      caseSensitive: false,
    );
    return [
      for (final match in pattern.allMatches(prompt))
        ContextSurgeryBlockObservation(
          kind: kind,
          label: tag,
          charCount: (match.group(1) ?? '').trim().length,
        ),
    ];
  }

  static List<ContextSurgeryBlockObservation> _sectionObservation(
    String prompt, {
    required String startMarker,
    required String label,
    required ContextSurgeryBlockKind kind,
  }) {
    final start = prompt.indexOf(startMarker);
    if (start < 0) return const [];
    final nextBlankLine = prompt.indexOf('\n\n', start);
    final end = nextBlankLine < 0 ? prompt.length : nextBlankLine;
    return [
      ContextSurgeryBlockObservation(
        kind: kind,
        label: label,
        charCount: prompt.substring(start, end).trim().length,
      ),
    ];
  }

  static ContextSurgeryBlockKind _toolResultKind(String toolName) {
    if (_fileReadToolNames.contains(toolName)) {
      return ContextSurgeryBlockKind.fileReadToolResult;
    }
    if (_fileSearchToolNames.contains(toolName)) {
      return ContextSurgeryBlockKind.fileSearchToolResult;
    }
    if (_commandToolNames.contains(toolName)) {
      return ContextSurgeryBlockKind.commandToolResult;
    }
    if (_sideEffectToolNames.contains(toolName)) {
      return ContextSurgeryBlockKind.sideEffectToolResult;
    }
    return ContextSurgeryBlockKind.toolResult;
  }

  static String? _staleCandidateKey(ToolResultInfo toolResult) {
    if (_fileReadToolNames.contains(toolResult.name)) {
      final path = _primaryPath(toolResult);
      if (path == null) return null;
      return 'read:${toolResult.name}:${_normalizePath(path)}';
    }
    if (_fileSearchToolNames.contains(toolResult.name)) {
      final key = _stableArgumentsKey(toolResult.arguments);
      if (key.isEmpty) return null;
      return 'search:${toolResult.name}:$key';
    }
    return null;
  }

  static String? _toolResultIdentifier(ToolResultInfo toolResult) {
    return _primaryPath(toolResult) ??
        _stableArgumentsKey(toolResult.arguments);
  }

  static String? _primaryPath(ToolResultInfo toolResult) {
    for (final key in const [
      'path',
      'filePath',
      'file_path',
      'relativePath',
      'relative_path',
      'directory',
      'root',
    ]) {
      final value = toolResult.arguments[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static String _stableArgumentsKey(Map<String, dynamic> arguments) {
    if (arguments.isEmpty) return '';
    final entries = arguments.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return entries
        .map((entry) => '${entry.key}=${_stableValue(entry.value)}')
        .join('&');
  }

  static String _stableValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((left, right) => '${left.key}'.compareTo('${right.key}'));
      return '{${entries.map((entry) => '${entry.key}:${_stableValue(entry.value)}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_stableValue).join(',')}]';
    }
    return '$value';
  }

  static String _normalizePath(String path) {
    return path.trim().replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
  }

  static String _replacementStub({
    required ToolResultInfo toolResult,
    required String identifier,
    required int replacedByIndex,
  }) {
    return '[stale tool result omitted: a newer ${toolResult.name} result for '
        '$identifier is retained at tool result index $replacedByIndex.]';
  }

  static int _estimatedTokens(int charCount) {
    if (charCount <= 0) return 0;
    return (charCount / 4).ceil();
  }

  static String _sectionLabel(
    ContextSurgeryBlockKind kind,
    String fallbackLabel,
  ) {
    return switch (kind) {
      ContextSurgeryBlockKind.systemPrompt => 'System prompt',
      ContextSurgeryBlockKind.repoMap => 'Repo map',
      ContextSurgeryBlockKind.agentsMarkdown => 'AGENTS.md',
      ContextSurgeryBlockKind.memory => 'Memory',
      ContextSurgeryBlockKind.planDocument => 'Plan document',
      ContextSurgeryBlockKind.workflowProjection => 'Workflow',
      ContextSurgeryBlockKind.toolResult => fallbackLabel,
      ContextSurgeryBlockKind.fileReadToolResult => 'File reads',
      ContextSurgeryBlockKind.fileSearchToolResult => 'File search',
      ContextSurgeryBlockKind.commandToolResult => 'Commands',
      ContextSurgeryBlockKind.sideEffectToolResult => 'Side effects',
    };
  }
}

class _MutableContextSurgerySectionSummary {
  _MutableContextSurgerySectionSummary({
    required this.kind,
    required this.label,
  });

  final ContextSurgeryBlockKind kind;
  final String label;
  int blockCount = 0;
  int charCount = 0;

  ContextSurgerySectionSummary toImmutable() {
    return ContextSurgerySectionSummary(
      kind: kind,
      label: label,
      blockCount: blockCount,
      charCount: charCount,
    );
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
