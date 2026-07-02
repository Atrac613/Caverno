import 'dart:convert';

import '../../../../core/utils/logger.dart';
import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import '../entities/tool_call_info.dart';

typedef PlanningResearchToolRunner =
    Future<McpToolResult> Function(ToolCallInfo toolCall);
typedef PlanningResearchPlainTextExtractor = String Function(String content);

final class PlanningResearchFileNote {
  const PlanningResearchFileNote({
    required this.path,
    required this.highlights,
  });

  final String path;
  final List<String> highlights;
}

final class PlanningResearchContext {
  const PlanningResearchContext({
    this.rootEntries = const <String>[],
    this.keyFiles = const <String>[],
    this.matchedLines = const <String>[],
    this.fileNotes = const <PlanningResearchFileNote>[],
    this.risks = const <String>[],
  });

  final List<String> rootEntries;
  final List<String> keyFiles;
  final List<String> matchedLines;
  final List<PlanningResearchFileNote> fileNotes;
  final List<String> risks;

  bool get hasContent {
    return rootEntries.isNotEmpty ||
        keyFiles.isNotEmpty ||
        matchedLines.isNotEmpty ||
        fileNotes.isNotEmpty ||
        risks.isNotEmpty;
  }

  String toPromptBlock() {
    final buffer = StringBuffer();

    if (rootEntries.isNotEmpty) {
      buffer.writeln('Project root snapshot:');
      for (final entry in rootEntries) {
        buffer.writeln('- $entry');
      }
    }

    if (keyFiles.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Relevant files discovered:');
      for (final path in keyFiles) {
        buffer.writeln('- $path');
      }
    }

    if (matchedLines.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Relevant code or text matches:');
      for (final line in matchedLines) {
        buffer.writeln('- $line');
      }
    }

    if (fileNotes.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('File highlights:');
      for (final note in fileNotes) {
        buffer.writeln('- ${note.path}');
        for (final highlight in note.highlights) {
          buffer.writeln('  $highlight');
        }
      }
    }

    if (risks.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Research risks:');
      for (final risk in risks) {
        buffer.writeln('- $risk');
      }
    }

    return buffer.toString().trimRight();
  }
}

class PlanningResearchCollector {
  const PlanningResearchCollector({
    required PlanningResearchToolRunner runTool,
    PlanningResearchPlainTextExtractor? extractPlainText,
  }) : _runTool = runTool,
       _extractPlainText = extractPlainText ?? _defaultPlainTextExtractor;

  final PlanningResearchToolRunner _runTool;
  final PlanningResearchPlainTextExtractor _extractPlainText;

  static const Set<String> _planningResearchStopWords = {
    'about',
    'after',
    'before',
    'build',
    'coding',
    'current',
    'feature',
    'first',
    'generate',
    'implementation',
    'implement',
    'mode',
    'next',
    'project',
    'proposal',
    'review',
    'saved',
    'should',
    'slice',
    'start',
    'task',
    'tasks',
    'that',
    'them',
    'there',
    'these',
    'this',
    'thread',
    'update',
    'using',
    'workflow',
    'would',
  };

  Future<PlanningResearchContext> collect({
    required Conversation currentConversation,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) async {
    final rootEntries = await _collectPlanningResearchRootEntries();
    final manifestFiles = await _collectPlanningResearchImportantFiles();
    final queryTerms = _buildPlanningResearchQueries(
      currentConversation: currentConversation,
      workflowStageOverride: workflowStageOverride,
      workflowSpecOverride: workflowSpecOverride,
    );
    final matchedFiles = await _collectPlanningResearchNamedMatches(queryTerms);
    final matchedLines = await _collectPlanningResearchTextMatches(queryTerms);

    final candidatePaths = <String>[
      ...manifestFiles,
      ...matchedFiles,
      ...matchedLines
          .map(_extractPlanningResearchPathFromMatch)
          .whereType<String>(),
    ].where((path) => path.trim().isNotEmpty).toSet().toList(growable: false);

    final fileNotes = await _collectPlanningResearchFileNotes(
      candidatePaths: candidatePaths,
      queryTerms: queryTerms,
    );
    final risks = _buildPlanningResearchRisks(
      rootEntries: rootEntries,
      keyFiles: manifestFiles,
      matchedFiles: matchedFiles,
      matchedLines: matchedLines,
      fileNotes: fileNotes,
      queryTerms: queryTerms,
    );

    return PlanningResearchContext(
      rootEntries: rootEntries,
      keyFiles: {
        ...manifestFiles,
        ...matchedFiles,
      }.take(6).toList(growable: false),
      matchedLines: matchedLines.take(6).toList(growable: false),
      fileNotes: fileNotes.take(3).toList(growable: false),
      risks: risks.take(3).toList(growable: false),
    );
  }

  Future<List<String>> _collectPlanningResearchRootEntries() async {
    final decoded = await _runPlanningResearchTool(
      name: 'list_directory',
      arguments: const {'path': '', 'recursive': false},
    );
    final entries = decoded?['entries'];
    if (entries is! List) {
      return const <String>[];
    }
    return entries
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  Future<List<String>> _collectPlanningResearchImportantFiles() async {
    const patterns = <String>[
      'pubspec.yaml',
      'README*',
      'analysis_options.yaml',
      'package.json',
      'Cargo.toml',
      'pyproject.toml',
      'requirements*.txt',
    ];
    final matches = <String>{};

    for (final pattern in patterns) {
      final decoded = await _runPlanningResearchTool(
        name: 'find_files',
        arguments: {'path': '', 'pattern': pattern, 'recursive': false},
      );
      final rawMatches = decoded?['matches'];
      if (rawMatches is! List) {
        continue;
      }
      for (final match in rawMatches.whereType<String>()) {
        if (matches.length >= 4) {
          break;
        }
        final trimmed = match.trim();
        if (trimmed.isNotEmpty) {
          matches.add(trimmed);
        }
      }
      if (matches.length >= 4) {
        break;
      }
    }

    return matches.toList(growable: false);
  }

  List<String> _buildPlanningResearchQueries({
    required Conversation currentConversation,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    final workflowSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    final seedTexts = <String>[
      ...currentConversation.messages.reversed
          .where((message) => message.role == MessageRole.user)
          .map((message) => _extractPlainText(message.content))
          .where((text) => text.isNotEmpty)
          .take(2),
      workflowSpec.goal,
      ...workflowSpec.acceptanceCriteria.take(1),
      ...workflowSpec.openQuestions.take(2),
      if (workflowStageOverride != null) workflowStageOverride.name,
    ];

    final phraseQueries = <String>[];
    final keywordQueries = <String>[];
    final seen = <String>{};

    for (final seed in seedTexts) {
      final words = seed
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_/\\ -]'), ' ')
          .split(RegExp(r'\s+'))
          .map((word) => word.trim())
          .where(
            (word) =>
                word.length >= 4 &&
                !_planningResearchStopWords.contains(word) &&
                !RegExp(r'^\d+$').hasMatch(word),
          )
          .toList(growable: false);

      for (var index = 0; index < words.length - 1; index++) {
        if (phraseQueries.length >= 2) {
          break;
        }
        final phrase = '${words[index]} ${words[index + 1]}';
        if (seen.add(phrase)) {
          phraseQueries.add(phrase);
        }
      }

      for (final word in words) {
        if (keywordQueries.length >= 4) {
          break;
        }
        if (seen.add(word)) {
          keywordQueries.add(word);
        }
      }

      if (phraseQueries.length >= 2 && keywordQueries.length >= 4) {
        break;
      }
    }

    return [
      ...phraseQueries,
      ...keywordQueries,
    ].take(4).toList(growable: false);
  }

  Future<List<String>> _collectPlanningResearchNamedMatches(
    List<String> queryTerms,
  ) async {
    final matches = <String>{};
    for (final term in queryTerms) {
      if (term.contains(' ') || term.length < 5) {
        continue;
      }
      final decoded = await _runPlanningResearchTool(
        name: 'find_files',
        arguments: {'path': '', 'pattern': '*$term*', 'recursive': true},
      );
      final rawMatches = decoded?['matches'];
      if (rawMatches is! List) {
        continue;
      }
      for (final match in rawMatches.whereType<String>()) {
        if (matches.length >= 4) {
          break;
        }
        final trimmed = match.trim();
        if (trimmed.isNotEmpty) {
          matches.add(trimmed);
        }
      }
      if (matches.length >= 4) {
        break;
      }
    }
    return matches.toList(growable: false);
  }

  Future<List<String>> _collectPlanningResearchTextMatches(
    List<String> queryTerms,
  ) async {
    final matches = <String>{};
    for (final query in queryTerms.take(2)) {
      final decoded = await _runPlanningResearchTool(
        name: 'search_files',
        arguments: {'path': '', 'query': query, 'case_sensitive': false},
      );
      final rawMatches = decoded?['matches'];
      if (rawMatches is! List) {
        continue;
      }
      for (final match in rawMatches.whereType<String>()) {
        if (matches.length >= 6) {
          break;
        }
        final compact = _compactPlanningResearchLine(match);
        if (compact.isNotEmpty) {
          matches.add(compact);
        }
      }
      if (matches.length >= 6) {
        break;
      }
    }
    return matches.toList(growable: false);
  }

  Future<List<PlanningResearchFileNote>> _collectPlanningResearchFileNotes({
    required List<String> candidatePaths,
    required List<String> queryTerms,
  }) async {
    final notes = <PlanningResearchFileNote>[];
    for (final path in candidatePaths.take(3)) {
      final decoded = await _runPlanningResearchTool(
        name: 'read_file',
        arguments: {'path': path},
      );
      final content = (decoded?['content'] as String?)?.trim();
      if (content == null || content.isEmpty) {
        continue;
      }
      final highlights = _extractPlanningResearchHighlights(
        content,
        queryTerms: queryTerms,
      );
      if (highlights.isEmpty) {
        continue;
      }
      notes.add(
        PlanningResearchFileNote(
          path: path,
          highlights: highlights.take(3).toList(growable: false),
        ),
      );
    }
    return notes;
  }

  Future<Map<String, dynamic>?> _runPlanningResearchTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final result = await _runTool(
      ToolCallInfo(
        id: 'planning_research_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        arguments: arguments,
      ),
    );

    if (!result.isSuccess || result.result.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(result.result);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      appLog('[Workflow] Planning research tool $name returned non-JSON text');
    }
    return null;
  }

  String _compactPlanningResearchLine(String value, {int maxLength = 140}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }

  String? _extractPlanningResearchPathFromMatch(String match) {
    final lineMatch = RegExp(r'^(.+?):\d+:').firstMatch(match.trim());
    final path = lineMatch?.group(1)?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    return path;
  }

  List<String> _extractPlanningResearchHighlights(
    String content, {
    required List<String> queryTerms,
  }) {
    final normalizedQueryTerms = queryTerms
        .map((term) => term.toLowerCase())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    final lines = const LineSplitter()
        .convert(content)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return const <String>[];
    }

    final highlights = <String>[];
    final seen = <String>{};

    void addLine(String line) {
      final compact = _compactPlanningResearchLine(line, maxLength: 120);
      if (compact.isNotEmpty && seen.add(compact)) {
        highlights.add(compact);
      }
    }

    for (final line in lines) {
      final lowerLine = line.toLowerCase();
      if (normalizedQueryTerms.any(lowerLine.contains)) {
        addLine(line);
      }
      if (highlights.length >= 3) {
        return highlights;
      }
    }

    for (final line in lines) {
      if (RegExp(
            r'^(name|description|dependencies|environment)\s*:',
            caseSensitive: false,
          ).hasMatch(line) ||
          RegExp(
            r'^(class|abstract class|enum|mixin|typedef|extension)\s+',
            caseSensitive: false,
          ).hasMatch(line) ||
          RegExp(
            r'^(void|Future<|Future\s|Widget\s)',
            caseSensitive: false,
          ).hasMatch(line)) {
        addLine(line);
      }
      if (highlights.length >= 3) {
        return highlights;
      }
    }

    for (final line in lines) {
      if (line.startsWith('//') ||
          line.startsWith('/*') ||
          line.startsWith('*')) {
        continue;
      }
      addLine(line);
      if (highlights.length >= 3) {
        return highlights;
      }
    }

    return highlights;
  }

  List<String> _buildPlanningResearchRisks({
    required List<String> rootEntries,
    required List<String> keyFiles,
    required List<String> matchedFiles,
    required List<String> matchedLines,
    required List<PlanningResearchFileNote> fileNotes,
    required List<String> queryTerms,
  }) {
    final risks = <String>[];

    if (rootEntries.isEmpty) {
      risks.add(
        'The selected project root looked empty during planning, so the first slice may need a new scaffold.',
      );
    }

    if (queryTerms.isNotEmpty &&
        matchedFiles.isEmpty &&
        matchedLines.isEmpty &&
        fileNotes.isEmpty) {
      risks.add(
        'No existing files matched the main request keywords, so the plan may rely on net-new files or inferred architecture.',
      );
    }

    if (keyFiles.isEmpty) {
      risks.add(
        'No common manifest or README was found at the project root, so setup and validation commands may need manual verification.',
      );
    }

    return risks;
  }

  static String _defaultPlainTextExtractor(String content) {
    return content.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
