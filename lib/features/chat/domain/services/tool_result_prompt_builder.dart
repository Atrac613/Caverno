import 'dart:convert';
import 'dart:math' as math;

import '../../../../core/constants/system_prompt_constants.dart';
import '../entities/tool_call_info.dart';
import 'context_surgery_observation_service.dart';

enum ToolResultPromptBudgetMode { normal, compact }

enum GoalEvidenceProgress { improved, noProgress }

class UnresolvedErrorDiagnostic {
  const UnresolvedErrorDiagnostic({
    required this.path,
    required this.code,
    required this.message,
  });

  final String path;
  final String code;
  final String message;
}

class ToolResultCompletionEvidence {
  const ToolResultCompletionEvidence({
    this.boundedToolLoopExhausted = false,
    this.unexecutedToolNames = const <String>[],
    this.unresolvedErrorCount = 0,
    this.unresolvedErrorPaths = const <String>[],
    this.unresolvedErrorDiagnostics = const <UnresolvedErrorDiagnostic>[],
    this.unverifiedChangePaths = const <String>[],
    this.mutatedWithoutExecutionVerification = false,
    this.hasExecutionVerification = false,
    this.hasSuccessfulExecutionVerification = false,
    this.hasAuthoritativeDiagnosticSnapshot = false,
    this.hasUnexecutedActionClaim = false,
    this.diagnosticSignature = '',
  });

  final bool boundedToolLoopExhausted;
  final List<String> unexecutedToolNames;
  final int unresolvedErrorCount;
  final List<String> unresolvedErrorPaths;
  final List<UnresolvedErrorDiagnostic> unresolvedErrorDiagnostics;
  final List<String> unverifiedChangePaths;
  final bool mutatedWithoutExecutionVerification;
  final bool hasExecutionVerification;
  final bool hasSuccessfulExecutionVerification;
  final bool hasAuthoritativeDiagnosticSnapshot;
  final bool hasUnexecutedActionClaim;
  final String diagnosticSignature;

  bool get hasIncompleteEvidence =>
      boundedToolLoopExhausted ||
      unresolvedErrorCount > 0 ||
      unverifiedChangePaths.isNotEmpty ||
      mutatedWithoutExecutionVerification ||
      hasUnexecutedActionClaim;

  bool get hasBlockingEvidence =>
      boundedToolLoopExhausted || unresolvedErrorCount > 0;

  bool get hasDiagnosticEvidence => unresolvedErrorCount > 0;

  bool get hasPendingExecutionVerification => unexecutedToolNames.any(
    (name) =>
        name.trim().toLowerCase() == 'local_execute_command' ||
        name.trim().toLowerCase() == 'run_tests',
  );

  bool get requiresValidationContinuation =>
      hasPendingExecutionVerification || mutatedWithoutExecutionVerification;

  String get summary {
    final parts = <String>[];
    if (unresolvedErrorCount > 0) {
      final pathSuffix = unresolvedErrorPaths.isEmpty
          ? ''
          : ' in ${unresolvedErrorPaths.join(', ')}';
      parts.add(
        '$unresolvedErrorCount unresolved Error diagnostic(s)$pathSuffix',
      );
    }
    if (boundedToolLoopExhausted) {
      final tools = unexecutedToolNames.isEmpty
          ? 'a requested tool call'
          : unexecutedToolNames.join(', ');
      parts.add('bounded tool loop stopped before executing $tools');
    }
    if (unverifiedChangePaths.isNotEmpty) {
      parts.add(
        'unverified file change(s) in ${unverifiedChangePaths.join(', ')}',
      );
    }
    if (mutatedWithoutExecutionVerification) {
      parts.add('files were modified without execution-class verification');
    }
    if (hasUnexecutedActionClaim) {
      parts.add('claimed file or command actions were not executed');
    }
    return parts.isEmpty ? 'no incomplete evidence' : parts.join('; ');
  }

  GoalEvidenceProgress compareProgress(ToolResultCompletionEvidence previous) {
    if (hasDiagnosticEvidence || previous.hasDiagnosticEvidence) {
      if (hasDiagnosticEvidence && previous.hasDiagnosticEvidence) {
        return unresolvedErrorCount < previous.unresolvedErrorCount
            ? GoalEvidenceProgress.improved
            : GoalEvidenceProgress.noProgress;
      }
      return hasDiagnosticEvidence
          ? GoalEvidenceProgress.noProgress
          : GoalEvidenceProgress.improved;
    }

    final currentPaths = unverifiedChangePaths.toSet();
    final previousPaths = previous.unverifiedChangePaths.toSet();
    return currentPaths.isNotEmpty &&
            previousPaths.isNotEmpty &&
            (currentPaths.length != previousPaths.length ||
                !currentPaths.containsAll(previousPaths))
        ? GoalEvidenceProgress.improved
        : GoalEvidenceProgress.noProgress;
  }

  ToolResultCompletionEvidence carryForwardIncompleteFrom(
    ToolResultCompletionEvidence previous,
  ) {
    if (!previous.hasIncompleteEvidence || hasSuccessfulExecutionVerification) {
      return this;
    }

    final carryDiagnostics =
        !hasAuthoritativeDiagnosticSnapshot &&
        unresolvedErrorCount == 0 &&
        previous.unresolvedErrorCount > 0;
    final carryPriorMutationEvidence = !hasExecutionVerification;
    final carriedUnverifiedPaths = <String>{
      if (carryPriorMutationEvidence) ...previous.unverifiedChangePaths,
      ...unverifiedChangePaths,
    }.toList(growable: false);
    return ToolResultCompletionEvidence(
      boundedToolLoopExhausted: boundedToolLoopExhausted,
      unexecutedToolNames: unexecutedToolNames,
      unresolvedErrorCount: carryDiagnostics
          ? previous.unresolvedErrorCount
          : unresolvedErrorCount,
      unresolvedErrorPaths: carryDiagnostics
          ? previous.unresolvedErrorPaths
          : unresolvedErrorPaths,
      unresolvedErrorDiagnostics: carryDiagnostics
          ? previous.unresolvedErrorDiagnostics
          : unresolvedErrorDiagnostics,
      unverifiedChangePaths: carriedUnverifiedPaths,
      mutatedWithoutExecutionVerification:
          mutatedWithoutExecutionVerification ||
          (carryPriorMutationEvidence &&
              previous.mutatedWithoutExecutionVerification),
      hasExecutionVerification: hasExecutionVerification,
      hasSuccessfulExecutionVerification: hasSuccessfulExecutionVerification,
      hasAuthoritativeDiagnosticSnapshot: hasAuthoritativeDiagnosticSnapshot,
      hasUnexecutedActionClaim:
          hasUnexecutedActionClaim || previous.hasUnexecutedActionClaim,
      diagnosticSignature: carryDiagnostics
          ? previous.diagnosticSignature
          : diagnosticSignature,
    );
  }

  ToolResultCompletionEvidence settleForExecutionGenerations({
    required int mutationGeneration,
    required int verificationGeneration,
  }) {
    if (verificationGeneration < 0 ||
        verificationGeneration != mutationGeneration) {
      return this;
    }
    return ToolResultCompletionEvidence(
      boundedToolLoopExhausted:
          boundedToolLoopExhausted && unexecutedToolNames.isNotEmpty,
      unexecutedToolNames: unexecutedToolNames,
      hasExecutionVerification: true,
      hasSuccessfulExecutionVerification: true,
      hasUnexecutedActionClaim: hasUnexecutedActionClaim,
    );
  }
}

class _ToolResultPromptBudget {
  const _ToolResultPromptBudget({
    required this.maxTotalResultChars,
    required this.maxSingleResultChars,
    required this.maxStringValueChars,
    required this.maxReadFileContentChars,
    required this.maxCommandOutputChars,
    required this.maxListItems,
    required this.maxImageAttachments,
  });

  final int maxTotalResultChars;
  final int maxSingleResultChars;
  final int maxStringValueChars;
  final int maxReadFileContentChars;
  final int maxCommandOutputChars;
  final int maxListItems;
  final int maxImageAttachments;
}

class ToolResultPromptBuilder {
  ToolResultPromptBuilder._();

  static const String exactPreservationToolResultInstruction =
      SystemPromptConstants.toolResultExactPreservationInstruction;

  static const _normalBudget = _ToolResultPromptBudget(
    maxTotalResultChars: 48000,
    maxSingleResultChars: 20000,
    maxStringValueChars: 12000,
    maxReadFileContentChars: 12000,
    maxCommandOutputChars: 8000,
    maxListItems: 120,
    maxImageAttachments: 2,
  );

  static const _compactBudget = _ToolResultPromptBudget(
    maxTotalResultChars: 16000,
    maxSingleResultChars: 8000,
    maxStringValueChars: 4000,
    maxReadFileContentChars: 4000,
    maxCommandOutputChars: 3000,
    maxListItems: 40,
    maxImageAttachments: 1,
  );

  static List<Map<String, dynamic>> dedupeToolsByName(
    List<Map<String, dynamic>> tools,
  ) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final tool in tools) {
      final name = (tool['function'] as Map?)?['name'];
      if (name is! String || name.isEmpty) {
        continue;
      }
      if (seen.add(name)) {
        deduped.add(tool);
      }
    }
    return deduped;
  }

  static List<ToolResultInfo> budgetToolResults(
    List<ToolResultInfo> toolResults, {
    ToolResultPromptBudgetMode mode = ToolResultPromptBudgetMode.normal,
    Set<String> protectedPaths = const {},
  }) {
    if (toolResults.isEmpty) {
      return const [];
    }

    final sourceToolResults = mode == ToolResultPromptBudgetMode.compact
        ? ContextSurgeryObservationService.applyStaleToolResultStubs(
            toolResults,
            protectedPaths: protectedPaths,
          )
        : toolResults;
    final budget = _budgetForMode(mode);
    final imageResultIndexes = <int>[];
    for (var index = 0; index < sourceToolResults.length; index += 1) {
      final decoded = _tryDecodeJsonMap(sourceToolResults[index].result);
      if (decoded?['imageBase64'] is String) {
        imageResultIndexes.add(index);
      }
    }
    final keptImageIndexes = imageResultIndexes
        .skip(
          math.max(0, imageResultIndexes.length - budget.maxImageAttachments),
        )
        .toSet();

    final budgeted = <ToolResultInfo>[];
    for (var index = 0; index < sourceToolResults.length; index += 1) {
      final toolResult = sourceToolResults[index];
      final result = _budgetToolResultPayload(
        toolResult,
        budget: budget,
        keepImagePayload: keptImageIndexes.contains(index),
      );
      budgeted.add(
        ToolResultInfo(
          id: toolResult.id,
          name: toolResult.name,
          arguments: toolResult.arguments,
          result: result,
        ),
      );
    }

    final totalChars = budgeted.fold<int>(
      0,
      (count, toolResult) => count + toolResult.result.length,
    );
    if (totalChars <= budget.maxTotalResultChars) {
      return budgeted;
    }

    final perResultTarget = math.max(
      1200,
      (budget.maxTotalResultChars / budgeted.length).floor(),
    );
    return budgeted
        .map(
          (toolResult) => ToolResultInfo(
            id: toolResult.id,
            name: toolResult.name,
            arguments: toolResult.arguments,
            result: _truncateTextWithMiddle(
              toolResult.result,
              maxChars: perResultTarget,
              reason:
                  'Tool result was further reduced to fit the prompt budget.',
            ),
          ),
        )
        .toList(growable: false);
  }

  static bool hasAdditionalCompactBudgetReduction(
    List<ToolResultInfo> toolResults, {
    Set<String> protectedPaths = const {},
  }) {
    final normal = budgetToolResults(toolResults);
    final compact = budgetToolResults(
      toolResults,
      mode: ToolResultPromptBudgetMode.compact,
      protectedPaths: protectedPaths,
    );
    if (normal.length != compact.length) {
      return true;
    }
    for (var index = 0; index < normal.length; index += 1) {
      if (normal[index].result != compact[index].result) {
        return true;
      }
    }
    return false;
  }

  static String buildAnswerPrompt(
    List<ToolResultInfo> toolResults, {
    Map<String, String> descriptionsByName = const {},
    ToolResultCompletionEvidence? completionEvidence,
  }) {
    final completionBlockers = completionBlockerInstructions(
      toolResults,
      completionEvidence: completionEvidence,
    );
    final buffer = StringBuffer()
      ..writeln(
        'Please answer the user\'s question based on the following tool results.',
      )
      ..writeln();
    if (completionBlockers.isNotEmpty) {
      for (final blocker in completionBlockers) {
        buffer.writeln(blocker);
      }
      buffer.writeln();
    }
    buffer
      ..writeln(
        'Interpret each tool name, description, arguments, and result together.',
      )
      ..writeln(
        'Preserve the entity roles implied by the tool and the payload.',
      )
      ..writeln(
        'Do not guess that an opaque identifier is an end-user device. '
        'It may instead refer to infrastructure such as a router, gateway, '
        'access point, interface, or monitored node.',
      )
      ..writeln(
        'If the role of an identifier is not explicit in the payload, say it '
        'is ambiguous instead of guessing.',
      )
      ..writeln(
        'Prefer explicit fields such as role, type, kind, category, or '
        'interpretation_hint over heuristics based on how an identifier looks.',
      )
      ..writeln(exactPreservationToolResultInstruction)
      ..writeln(
        'Only claim that a local file was created, edited, saved, moved, or '
        'deleted when the provided tool results include a successful tool '
        'result for that side effect, such as write_file, edit_file, '
        'rollback_last_file_change, or an explicit file-operation tool. If the '
        'user requested local file changes but no such successful result is '
        'provided, or a tool result reports code=unexecuted_file_save, say the '
        'files were not created yet instead of implying they exist.',
      )
      ..writeln(
        'When a write_file result includes "created": false, state that an '
        'existing file was updated or overwritten rather than newly created. '
        'When it includes "created": true, state that a new file was created. '
        'Do not hide this distinction when summarizing saved files.',
      )
      ..writeln(
        'If local file changes are still needed and all required content is '
        'known but no successful file-operation tool result is provided, say '
        'the files were not created yet and name the exact missing action '
        'instead of emitting tool-call tags.',
      )
      ..writeln(
        'Only say a local command, dry run, test, validation, git operation, or '
        'release script ran when the corresponding command-execution tool '
        'result succeeded. If a tool result reports '
        'code=unexecuted_command_action, state that the requested command '
        'remains unexecuted.',
      )
      ..writeln(
        'When browser_snapshot returns page elements, include the relevant '
        'element refs, labels, and roles needed for likely follow-up browser '
        'actions. State that refs are valid only for the current page snapshot. '
        'Do not invent or renumber browser refs.',
      )
      ..writeln(
        'When a browser_fill, browser_click, or browser_submit result reports '
        'element_not_found or a stale target, say the browser needs a fresh '
        'browser_snapshot before retrying rather than guessing another ref.',
      )
      ..writeln(
        'Only say a browser action such as open, click, fill, submit, or '
        'navigation completed when the corresponding browser tool result '
        'succeeded. If the latest result only lists a browser_snapshot or '
        'reports code=unexecuted_browser_action, state that the requested '
        'browser action remains unexecuted.',
      )
      ..writeln(
        'For browser_click results, verify the returned target label, name, '
        'role, href, url, title, and navigated fields before claiming the '
        'requested click, search, or navigation completed. If the clicked '
        'target or resulting page does not match the user request, say what '
        'was actually clicked and that the requested browser action still '
        'needs a fresh browser_snapshot or browser_submit retry.',
      )
      ..writeln(
        'For discovery tools such as find_files and search_files, zero '
        'matches only proves that the exact pattern or query matched nothing. '
        'Before saying a requested file or content is absent, verify with a '
        'broader search, a direct path read, or list_directory on likely '
        'parent directories.',
      )
      ..writeln(
        'When browser_save_data succeeds, report the saved file path from the '
        'tool result path field exactly. If the requested filename in the tool '
        'arguments differs from the returned filename or path, trust the result '
        'path and mention the returned filename only.',
      )
      ..writeln(
        'This final answer request cannot call tools. Do not output JSON '
        'command arrays, function-call payloads, or tool-call shaped text as '
        'a substitute for tool execution. If additional tool execution is '
        'required, state that it remains unexecuted and name the missing '
        'action briefly in prose.',
      )
      ..writeln(
        'Do not restate an investigation plan, checklist, or future action '
        'such as "I will inspect" as the final answer. Either answer from the '
        'executed tool results or give a concise blocker that names the exact '
        'unexecuted action.',
      )
      ..writeln(
        'When the provided tool results already satisfy the user\'s requested '
        'local action or saved coding goal, end after the concise completion '
        'evidence. Do not add optional follow-up questions, offers, or '
        'suggestions after that completion evidence.',
      )
      ..writeln(
        'When a load_skill result contains explicit output constraints, follow '
        'those constraints exactly. Do not add optional follow-up questions, '
        'permission requests, or offers to execute extra checks unless the '
        'loaded skill explicitly asks for them.',
      )
      ..writeln(
        'Do not convert a missing source file, repository, permission, runtime '
        'data, or external dependency into a confirmed root cause. If the '
        'executed results show that required evidence is unavailable, preserve '
        'that blocker and separate any inference from verified facts.',
      )
      ..writeln(
        'Treat search_past_conversations and recall_memory results as '
        'historical context, not verified evidence about the current '
        'workspace, filesystem, network, runtime, or external dependencies. '
        'Use them to choose what to verify next. Mark their claims as prior '
        'and unverified unless current application-executed tool results or '
        'direct user statements support them.',
      )
      ..writeln(
        'Do not treat finishReason=stream_end, finishReason=stop, or another '
        'finish reason by itself as proof of an LLM server, network, timeout, '
        'or transport failure. If streamed content contains an unfinished '
        'tool-call tag, report the verified incomplete assistant tool request '
        'and keep server or network causes explicitly unverified unless the '
        'tool results include a concrete transport error.',
      )
      ..writeln(
        'When interpreting Caverno LLM session logs, separate the user-facing '
        'chat turn from background secondary calls. Entries whose request '
        'messages are memory_extractor_system or memory_extractor_user are '
        'post-response memory extraction calls. Do not cite their model-load, '
        'transport, or JSON errors as the cause of the user-facing chat turn '
        'stopping unless the provided log evidence explicitly shows that the '
        'secondary call aborted that chat turn. Determine the chat outcome '
        'from the latest non-memory-extraction chat entry using its '
        'response.finishReason, response.toolCalls, response.error, and '
        'response.content.',
      )
      ..writeln(
        'If the current investigation turn itself reports '
        'code=tool_call_not_executed or reason=bounded_tool_loop_exhausted, '
        'do not cite that harness diagnostic as the stop reason for the '
        'session log being analyzed. Keep the current-turn execution gap '
        'separate from the target log evidence.',
      )
      ..writeln()
      ..write(
        formatToolResults(toolResults, descriptionsByName: descriptionsByName),
      );
    return buffer.toString().trimRight();
  }

  /// Detect tool results that prove the requested task is unfinished so the
  /// final answer cannot falsely claim completion.
  ///
  /// Two signals are surfaced as explicit, high-priority guardrails:
  /// - A bounded tool loop that exhausted its iteration budget and dropped a
  ///   requested tool call (`code=tool_call_not_executed`).
  /// - Analyzer/test feedback that still reports unresolved `Error`-severity
  ///   diagnostics after the latest edits.
  ///
  /// Analyzer feedback is only treated as current when the same file was not
  /// mutated by a later successful write_file/edit_file in the same result
  /// sequence. The analyzer is not re-run after a subsequent edit, so a stale
  /// pre-fix diagnostic must not be reported as an unresolved error — that
  /// would push the model into a false "not complete" claim.
  ///
  /// These appear near the top of the answer prompt because a weak model may
  /// otherwise ignore the per-result `instruction` field and declare success
  /// while the workspace is still broken.
  static List<String> completionBlockerInstructions(
    List<ToolResultInfo> toolResults, {
    ToolResultCompletionEvidence? completionEvidence,
  }) {
    final evidence =
        completionEvidence ??
        ToolResultPromptBuilder.completionEvidence(toolResults);

    final lines = <String>[];
    if (evidence.unexecutedToolNames.isNotEmpty) {
      lines.add(
        'TASK NOT COMPLETE: the bounded tool loop stopped before a requested '
        'tool call (${evidence.unexecutedToolNames.join(', ')}) was executed '
        '(code=tool_call_not_executed / reason=bounded_tool_loop_exhausted). '
        'Do not claim the task, port, fix, edit, or file change is finished. '
        'State that this action remains unexecuted, name it, and list what '
        'still needs to be done.',
      );
    }
    if (evidence.unresolvedErrorCount > 0) {
      final pathSuffix = evidence.unresolvedErrorPaths.isEmpty
          ? ''
          : ' in ${evidence.unresolvedErrorPaths.join(', ')}';
      lines.add(
        'TASK NOT COMPLETE: the latest analyzer/test feedback still reports '
        '${evidence.unresolvedErrorCount} unresolved Error-severity diagnostic(s)'
        '$pathSuffix. The code does not pass analysis. Do not claim the coding '
        'or porting task is complete or that it produces correct output. '
        'Report the remaining errors and that they still need fixing.',
      );
    }
    // Unverified change: the turn mutated a file but never ran or tested
    // anything, so a "fixed"/"works"/"passes"/benchmark claim is unbacked by an
    // execution result. Unlike the Dart analyzer (a safe static re-run) an
    // arbitrary shell command may have side effects, so surface the gap as a
    // caution instead of auto-running it. Kept conservative — a turn that did
    // run at least once is left alone to avoid flagging cosmetic post-run edits.
    // Skipped when an analyzer error already blocks completion above.
    if (evidence.unverifiedChangePaths.isNotEmpty) {
      lines.add(
        'UNVERIFIED CHANGE: a file was edited but nothing was run or tested in '
        'this turn, so there is no execution result behind it. Do not claim the '
        'code is fixed, works, passes, runs, or produces specific output or '
        'benchmark numbers — those are unverified. State that the change still '
        'needs to be run or tested to confirm, or, if running does not apply '
        '(for example a docs or config edit), describe only what was changed.',
      );
    }
    return lines;
  }

  static ToolResultCompletionEvidence completionEvidence(
    List<ToolResultInfo> toolResults,
  ) {
    final lastMutationIndexByPath = _lastSuccessfulFileMutationIndexByPath(
      toolResults,
    );

    final unexecutedToolNames = <String>{};
    final unresolvedErrorPaths = <String>{};
    final unresolvedErrorDiagnostics = <UnresolvedErrorDiagnostic>[];
    final seenDiagnosticKeys = <String>{};
    final diagnosticSignatureComponents = <String>{};
    var hasAuthoritativeDiagnosticSnapshot = false;
    var hasUnexecutedActionClaim = false;
    var unresolvedErrorCount = 0;

    for (var index = 0; index < toolResults.length; index += 1) {
      final toolResult = toolResults[index];
      final decoded = _tryDecodeJsonMap(toolResult.result);
      if (decoded == null) {
        continue;
      }

      final reason = decoded['reason']?.toString().trim();
      final code = decoded['code']?.toString().trim();
      if (code == 'unexecuted_command_action' ||
          code == 'unexecuted_file_save') {
        hasUnexecutedActionClaim = true;
      }
      if (reason == 'bounded_tool_loop_exhausted' ||
          code == 'tool_call_not_executed') {
        final toolName = (decoded['tool_name'] ?? toolResult.name)
            ?.toString()
            .trim();
        unexecutedToolNames.add(
          toolName == null || toolName.isEmpty ? 'a tool call' : toolName,
        );
      }

      final diagnostics = decoded['diagnostics'];
      if (diagnostics is List) {
        hasAuthoritativeDiagnosticSnapshot = true;
        for (final diagnostic in diagnostics) {
          if (diagnostic is! Map) {
            continue;
          }
          final severity = diagnostic['severity']?.toString().toLowerCase();
          if (severity != 'error') {
            continue;
          }
          final absolutePath = diagnostic['path']?.toString().trim();
          if (absolutePath != null && absolutePath.isNotEmpty) {
            final laterMutationIndex = lastMutationIndexByPath[absolutePath];
            if (laterMutationIndex != null && laterMutationIndex > index) {
              continue;
            }
          }
          final diagnosticKey = [
            absolutePath ?? '',
            diagnostic['line']?.toString() ?? '',
            diagnostic['column']?.toString() ?? '',
            diagnostic['code']?.toString() ?? '',
            diagnostic['message']?.toString() ?? '',
          ].join('|');
          if (!seenDiagnosticKeys.add(diagnosticKey)) {
            continue;
          }
          diagnosticSignatureComponents.add(
            _diagnosticSignatureComponent(diagnostic),
          );
          unresolvedErrorCount += 1;
          final displayPath =
              (diagnostic['relative_path'] ?? diagnostic['path'])?.toString();
          if (displayPath != null && displayPath.trim().isNotEmpty) {
            unresolvedErrorPaths.add(displayPath.trim());
          }
          unresolvedErrorDiagnostics.add(
            UnresolvedErrorDiagnostic(
              path: displayPath?.trim() ?? '',
              code: diagnostic['code']?.toString().trim() ?? '',
              message: diagnostic['message']?.toString().trim() ?? '',
            ),
          );
        }
      }
    }

    final latestMutationIndex = lastMutationIndexByPath.values.fold(
      -1,
      (latest, index) => index > latest ? index : latest,
    );
    final hasExecutionVerification = _hasAnyExecutionVerification(
      toolResults,
      afterIndex: latestMutationIndex,
    );
    final mutatedWithoutExecutionVerification =
        lastMutationIndexByPath.isNotEmpty && !hasExecutionVerification;
    final unverifiedChangePaths =
        unresolvedErrorCount == 0 && mutatedWithoutExecutionVerification
        ? lastMutationIndexByPath.keys.toList(growable: false)
        : const <String>[];

    return ToolResultCompletionEvidence(
      boundedToolLoopExhausted: unexecutedToolNames.isNotEmpty,
      unexecutedToolNames: unexecutedToolNames.toList(growable: false),
      unresolvedErrorCount: unresolvedErrorCount,
      unresolvedErrorPaths: unresolvedErrorPaths.toList(growable: false),
      unresolvedErrorDiagnostics: List.unmodifiable(unresolvedErrorDiagnostics),
      unverifiedChangePaths: unverifiedChangePaths,
      mutatedWithoutExecutionVerification: mutatedWithoutExecutionVerification,
      hasExecutionVerification: hasExecutionVerification,
      hasSuccessfulExecutionVerification: _hasSuccessfulExecutionVerification(
        toolResults,
      ),
      hasAuthoritativeDiagnosticSnapshot: hasAuthoritativeDiagnosticSnapshot,
      hasUnexecutedActionClaim: hasUnexecutedActionClaim,
      diagnosticSignature: (diagnosticSignatureComponents.toList()..sort())
          .join('\n'),
    );
  }

  static String _diagnosticSignatureComponent(Map diagnostic) {
    final path = (diagnostic['relative_path'] ?? diagnostic['path'])
        ?.toString()
        .trim()
        .replaceAll('\\', '/');
    final normalizedPath = path == null || path.isEmpty
        ? ''
        : path.startsWith('/')
        ? path.split('/').where((part) => part.isNotEmpty).last
        : path;
    var message = diagnostic['message']?.toString() ?? '';
    final absolutePath = diagnostic['path']?.toString().trim();
    if (absolutePath != null && absolutePath.isNotEmpty) {
      message = message.replaceAll(absolutePath, normalizedPath);
    }
    message = message
        .toLowerCase()
        .replaceAll(RegExp(r':\d+(?::\d+)?'), ':<location>')
        .replaceAll(RegExp(r'\bline\s+\d+\b'), 'line <location>')
        .replaceAll(RegExp(r'\bcolumn\s+\d+\b'), 'column <location>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return [
      normalizedPath,
      diagnostic['severity']?.toString().trim().toLowerCase() ?? '',
      diagnostic['code']?.toString().trim().toLowerCase() ?? '',
      message,
    ].join('|');
  }

  static ToolResultCompletionEvidence reconcileFinalizationEvidence({
    required ToolResultCompletionEvidence authoritativeEvidence,
    required List<ToolResultInfo> completedToolResults,
    required List<ToolResultInfo> contentToolResults,
  }) {
    if (contentToolResults.isEmpty || completedToolResults.isNotEmpty) {
      return authoritativeEvidence;
    }
    return completionEvidence(
      contentToolResults,
    ).carryForwardIncompleteFrom(authoritativeEvidence);
  }

  static bool _hasSuccessfulExecutionVerification(
    List<ToolResultInfo> toolResults,
  ) {
    final mutationIndexes = _lastSuccessfulFileMutationIndexByPath(
      toolResults,
    ).values;
    final latestMutationIndex = mutationIndexes.fold(
      -1,
      (latest, index) => index > latest ? index : latest,
    );
    for (
      var index = latestMutationIndex + 1;
      index < toolResults.length;
      index++
    ) {
      final toolResult = toolResults[index];
      if (!_isVerificationRunToolName(toolResult.name)) continue;
      final decoded = _tryDecodeJsonMap(toolResult.result);
      if (decoded == null) continue;
      final exitCode = decoded['exit_code'];
      if (exitCode == 0 || exitCode == '0') return true;
      if (decoded['ok'] == true) return true;
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (normalizedName == 'dart_analyze_feedback') {
        final diagnostics = decoded['diagnostics'];
        if (diagnostics is List &&
            diagnostics.every((item) {
              return item is! Map ||
                  item['severity']?.toString().toLowerCase() != 'error';
            })) {
          return true;
        }
      }
      if (normalizedName == 'dart_test_feedback' &&
          decoded['validationStatus']?.toString().toLowerCase() == 'passed') {
        return true;
      }
    }
    return false;
  }

  /// Whether an execution-class tool produced a result that proves dispatch.
  static bool _hasAnyExecutionVerification(
    List<ToolResultInfo> toolResults, {
    int afterIndex = -1,
  }) {
    for (var index = afterIndex + 1; index < toolResults.length; index++) {
      final toolResult = toolResults[index];
      if (!_isVerificationRunToolName(toolResult.name)) {
        continue;
      }
      final decoded = _tryDecodeJsonMap(toolResult.result);
      if (decoded == null) {
        continue;
      }
      if (decoded.containsKey('exit_code') || decoded['ok'] == true) {
        return true;
      }
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (normalizedName == 'dart_analyze_feedback' &&
          decoded['diagnostics'] is List) {
        return true;
      }
      if (normalizedName == 'dart_test_feedback' &&
          decoded['validationStatus'] != null) {
        return true;
      }
    }
    return false;
  }

  static bool _isVerificationRunToolName(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'local_execute_command':
      case 'analyze_project':
      case 'run_tests':
      case 'git_execute_command':
      case 'process_start':
      case 'process_wait':
        return true;
    }
    return false;
  }

  /// Map each absolute file path to the index of the latest successful
  /// write_file/edit_file/rollback result that touched it, so analyzer
  /// diagnostics emitted earlier in the sequence can be recognized as stale.
  static Map<String, int> _lastSuccessfulFileMutationIndexByPath(
    List<ToolResultInfo> toolResults,
  ) {
    final indexByPath = <String, int>{};
    for (var index = 0; index < toolResults.length; index += 1) {
      final toolResult = toolResults[index];
      if (!_isFileMutationToolName(toolResult.name)) {
        continue;
      }
      final decoded = _tryDecodeJsonMap(toolResult.result);
      if (decoded == null || !_isSuccessfulFileMutation(decoded)) {
        continue;
      }
      final path = decoded['path']?.toString().trim();
      if (path != null && path.isNotEmpty) {
        indexByPath[path] = index;
      }
    }
    return indexByPath;
  }

  static bool _isFileMutationToolName(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'write_file':
      case 'edit_file':
      case 'delete_file':
      case 'rollback_last_file_change':
        return true;
    }
    return false;
  }

  static bool _isSuccessfulFileMutation(Map<String, dynamic> decoded) {
    if (decoded['error'] != null || decoded['ok'] == false) {
      return false;
    }
    if (decoded['already_applied'] == true) {
      return false;
    }
    final code = decoded['code']?.toString().trim().toLowerCase();
    if (code != null && code.isNotEmpty && code != 'ok' && code != 'success') {
      // Any non-success status code (edit_mismatch, unexecuted_file_save,
      // permission_denied, ...) means the mutation did not land.
      return false;
    }
    return true;
  }

  static String formatToolResults(
    List<ToolResultInfo> toolResults, {
    Map<String, String> descriptionsByName = const {},
  }) {
    final sections = toolResults.map((toolResult) {
      final buffer = StringBuffer()..writeln('[Tool: ${toolResult.name}]');
      final description = descriptionsByName[toolResult.name];
      if (description != null && description.isNotEmpty) {
        buffer.writeln('Description: $description');
      }
      final scopeNote = buildToolScopeNote(
        toolName: toolResult.name,
        description: description,
      );
      if (scopeNote != null) {
        buffer.writeln('Scope note: $scopeNote');
      }
      if (toolResult.arguments.isNotEmpty) {
        buffer.writeln('Arguments: ${jsonEncode(toolResult.arguments)}');
      }
      final operationNote = buildToolOperationNote(toolResult);
      if (operationNote != null) {
        buffer.writeln('Operation note: $operationNote');
      }
      final interpretationLines = buildToolDataInterpretationLines(toolResult);
      if (interpretationLines.isNotEmpty) {
        buffer.writeln('Interpretation note:');
        for (final line in interpretationLines) {
          buffer.writeln('- $line');
        }
      }
      buffer
        ..writeln('Result:')
        ..write(formatToolResultPayload(toolResult.result));
      return buffer.toString().trimRight();
    });
    return sections.join('\n\n');
  }

  static String formatToolResultPayload(String result) {
    final decoded = _tryDecodeJsonMap(result);
    if (decoded == null || decoded['imageBase64'] is! String) {
      return result;
    }

    final redacted = Map<String, dynamic>.from(decoded)
      ..['imageBase64'] = '[attached as image content]';
    return jsonEncode(redacted);
  }

  static String? buildToolOperationNote(ToolResultInfo toolResult) {
    final decoded = _tryDecodeJsonMap(toolResult.result);
    if (decoded == null) {
      return null;
    }

    return switch (toolResult.name) {
      'write_file' => _writeFileOperationNote(decoded),
      _ => null,
    };
  }

  static String? _writeFileOperationNote(Map<String, dynamic> decoded) {
    final created = decoded['created'];
    if (created is! bool) {
      return null;
    }
    final path = decoded['path'];
    final pathSuffix = path is String && path.trim().isNotEmpty
        ? ' at ${path.trim()}'
        : '';
    if (created) {
      return 'write_file created a new file$pathSuffix.';
    }
    return 'write_file updated or overwrote an existing file$pathSuffix; '
        'mention this existing-file update in the final answer.';
  }

  static List<String> buildToolDataInterpretationLines(
    ToolResultInfo toolResult,
  ) {
    final decoded = _tryDecodeJsonMap(toolResult.result);
    if (decoded == null) {
      return const [];
    }

    return switch (toolResult.name) {
      'http_get' ||
      'http_post' ||
      'http_put' ||
      'http_patch' ||
      'http_delete' => _httpResponseInterpretationLines(decoded),
      _ => const [],
    };
  }

  static List<String> _httpResponseInterpretationLines(
    Map<String, dynamic> decoded,
  ) {
    final body = decoded['body'];
    if (body is! String || body.trim().isEmpty) {
      return const [];
    }

    final payload = _tryDecodeJsonMap(body);
    if (payload == null) {
      return const [];
    }

    final url = (decoded['url'] as String?)?.toLowerCase() ?? '';
    if (!url.contains('open-meteo.com') &&
        !_looksLikeOpenMeteoWeatherPayload(payload)) {
      return const [];
    }

    final weatherCodeLines = _openMeteoWeatherCodeLines(payload);
    if (weatherCodeLines.isEmpty) {
      return const [];
    }

    return [
      ...weatherCodeLines,
      'Use these WMO labels for weather descriptions; drizzle codes are '
          '51, 53, and 55, while rain codes are 61, 63, and 65.',
    ];
  }

  static bool _looksLikeOpenMeteoWeatherPayload(Map<String, dynamic> payload) {
    final dailyUnits = payload['daily_units'];
    if (dailyUnits is Map) {
      final weatherCodeUnit =
          dailyUnits['weathercode'] ?? dailyUnits['weather_code'];
      if (weatherCodeUnit is String &&
          weatherCodeUnit.toLowerCase().contains('wmo')) {
        return true;
      }
    }
    final hourlyUnits = payload['hourly_units'];
    if (hourlyUnits is Map) {
      final weatherCodeUnit =
          hourlyUnits['weathercode'] ?? hourlyUnits['weather_code'];
      if (weatherCodeUnit is String &&
          weatherCodeUnit.toLowerCase().contains('wmo')) {
        return true;
      }
    }
    return false;
  }

  static List<String> _openMeteoWeatherCodeLines(Map<String, dynamic> payload) {
    final lines = <String>[];
    final daily = payload['daily'];
    if (daily is Map) {
      _addOpenMeteoSeriesWeatherCodeLines(
        lines,
        sectionName: 'daily',
        values: daily['weathercode'] ?? daily['weather_code'],
        times: daily['time'],
      );
    }

    final currentWeather = payload['current_weather'];
    if (currentWeather is Map) {
      _addOpenMeteoScalarWeatherCodeLine(
        lines,
        context: 'current_weather',
        value: currentWeather['weathercode'] ?? currentWeather['weather_code'],
      );
    }

    final current = payload['current'];
    if (current is Map) {
      _addOpenMeteoScalarWeatherCodeLine(
        lines,
        context: 'current',
        value: current['weathercode'] ?? current['weather_code'],
      );
    }

    return lines.take(8).toList(growable: false);
  }

  static void _addOpenMeteoSeriesWeatherCodeLines(
    List<String> lines, {
    required String sectionName,
    required Object? values,
    required Object? times,
  }) {
    if (values is List) {
      for (var index = 0; index < values.length; index += 1) {
        final time = times is List && index < times.length
            ? times[index]
            : null;
        final context = time is String && time.trim().isNotEmpty
            ? '$sectionName ${time.trim()}'
            : '$sectionName index $index';
        _addOpenMeteoScalarWeatherCodeLine(
          lines,
          context: context,
          value: values[index],
        );
      }
      return;
    }

    _addOpenMeteoScalarWeatherCodeLine(
      lines,
      context: sectionName,
      value: values,
    );
  }

  static void _addOpenMeteoScalarWeatherCodeLine(
    List<String> lines, {
    required String context,
    required Object? value,
  }) {
    final code = _asInt(value);
    if (code == null) {
      return;
    }
    final label = _openMeteoWmoWeatherCodeLabels[code];
    if (label == null) {
      lines.add(
        'Open-Meteo $context weather code $code is not in the built-in WMO '
        'mapping; do not invent a weather label.',
      );
      return;
    }
    lines.add('Open-Meteo $context weather code $code = $label.');
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static const Map<int, String> _openMeteoWmoWeatherCodeLabels = {
    0: 'Clear sky',
    1: 'Mainly clear',
    2: 'Partly cloudy',
    3: 'Overcast',
    45: 'Fog',
    48: 'Depositing rime fog',
    51: 'Drizzle: Light intensity',
    53: 'Drizzle: Moderate intensity',
    55: 'Drizzle: Dense intensity',
    56: 'Freezing drizzle: Light intensity',
    57: 'Freezing drizzle: Dense intensity',
    61: 'Rain: Slight intensity',
    63: 'Rain: Moderate intensity',
    65: 'Rain: Heavy intensity',
    66: 'Freezing rain: Light intensity',
    67: 'Freezing rain: Heavy intensity',
    71: 'Snow fall: Slight intensity',
    73: 'Snow fall: Moderate intensity',
    75: 'Snow fall: Heavy intensity',
    77: 'Snow grains',
    80: 'Rain showers: Slight',
    81: 'Rain showers: Moderate',
    82: 'Rain showers: Violent',
    85: 'Snow showers: Slight',
    86: 'Snow showers: Heavy',
    95: 'Thunderstorm: Slight or moderate',
    96: 'Thunderstorm with slight hail',
    99: 'Thunderstorm with heavy hail',
  };

  static Map<String, String> descriptionsByNameFromDefinitions(
    List<Map<String, dynamic>> definitions,
  ) {
    final descriptionsByName = <String, String>{};
    for (final tool in definitions) {
      final function = tool['function'];
      if (function is! Map) {
        continue;
      }
      final name = function['name'];
      final description = function['description'];
      if (name is String &&
          name.isNotEmpty &&
          description is String &&
          description.isNotEmpty) {
        descriptionsByName[name] = description;
      }
    }
    return descriptionsByName;
  }

  static String? buildToolScopeNote({
    required String toolName,
    String? description,
  }) {
    if (toolName == 'search_past_conversations' ||
        toolName == 'recall_memory') {
      return 'This is recalled historical context. It may contain prior '
          'assistant hypotheses or stale facts; treat it as unverified until '
          'corroborated by current tool results or direct user statements.';
    }

    final combinedText = '$toolName ${description ?? ''}'.toLowerCase();
    if (combinedText.contains('router') || combinedText.contains('gateway')) {
      return 'This is infrastructure-side telemetry. Identifiers may refer '
          'to the router, gateway, interfaces, or other monitored '
          'infrastructure rather than a client device.';
    }
    if (combinedText.contains('wifi') ||
        combinedText.contains('wi-fi') ||
        combinedText.contains('access point') ||
        combinedText.contains('bssid') ||
        combinedText.contains('ssid')) {
      return 'This is wireless-side telemetry. Identifiers may refer to '
          'radios, access points, or BSSIDs rather than user devices.';
    }
    return null;
  }

  static _ToolResultPromptBudget _budgetForMode(
    ToolResultPromptBudgetMode mode,
  ) {
    return switch (mode) {
      ToolResultPromptBudgetMode.normal => _normalBudget,
      ToolResultPromptBudgetMode.compact => _compactBudget,
    };
  }

  static String _budgetToolResultPayload(
    ToolResultInfo toolResult, {
    required _ToolResultPromptBudget budget,
    required bool keepImagePayload,
  }) {
    final decoded = _tryDecodeJsonMap(toolResult.result);
    if (decoded == null) {
      return _truncateTextWithMiddle(
        toolResult.result,
        maxChars: budget.maxSingleResultChars,
        reason: 'Tool result was reduced to fit the prompt budget.',
      );
    }

    final budgeted = switch (toolResult.name) {
      'read_file' => _budgetReadFileResult(decoded, budget: budget),
      'local_execute_command' ||
      'run_tests' ||
      'git_execute_command' => _budgetCommandResult(decoded, budget: budget),
      'search_files' => _budgetDiscoveryResult(
        decoded,
        budget: budget,
        listKey: 'matches',
        countKey: 'match_count',
        nextOffsetKey: 'next_offset',
        noMatchHint: _searchFilesNoMatchHint,
      ),
      'list_directory' => _budgetListResult(
        decoded,
        budget: budget,
        listKey: 'entries',
        countKey: 'entry_count',
      ),
      'find_files' => _budgetDiscoveryResult(
        decoded,
        budget: budget,
        listKey: 'matches',
        countKey: 'match_count',
        noMatchHint: _findFilesNoMatchHint,
      ),
      _ => _budgetJsonMap(decoded, budget: budget),
    };

    if (!keepImagePayload && budgeted['imageBase64'] is String) {
      budgeted
        ..['imageBase64'] = '[omitted from this request to fit prompt budget]'
        ..['image_omitted_for_prompt_budget'] = true;
    }

    final encoded = jsonEncode(budgeted);
    return _truncateTextWithMiddle(
      encoded,
      maxChars: budget.maxSingleResultChars,
      reason: 'Tool result was reduced to fit the prompt budget.',
    );
  }

  static Map<String, dynamic> _budgetReadFileResult(
    Map<String, dynamic> decoded, {
    required _ToolResultPromptBudget budget,
  }) {
    final result = _budgetJsonMap(decoded, budget: budget);
    final content = decoded['content'];
    if (content is String && content.length > budget.maxReadFileContentChars) {
      result
        ..['content'] = _truncateTextWithMiddle(
          content,
          maxChars: budget.maxReadFileContentChars,
          reason: 'File content was reduced to fit the prompt budget.',
        )
        ..['content_reduced_for_prompt_budget'] = true
        ..['omitted_content_chars'] =
            content.length - budget.maxReadFileContentChars
        ..['read_more_hint'] = _buildReadMoreHint(decoded);
    }
    return result;
  }

  static Map<String, dynamic> _budgetCommandResult(
    Map<String, dynamic> decoded, {
    required _ToolResultPromptBudget budget,
  }) {
    final result = _budgetJsonMap(decoded, budget: budget);
    for (final key in const ['stdout', 'stderr']) {
      final value = decoded[key];
      if (value is String && value.length > budget.maxCommandOutputChars) {
        result
          ..[key] = _truncateTextWithMiddle(
            value,
            maxChars: budget.maxCommandOutputChars,
            reason: '$key was reduced to fit the prompt budget.',
          )
          ..['${key}_reduced_for_prompt_budget'] = true;
      }
    }
    return result;
  }

  static Map<String, dynamic> _budgetListResult(
    Map<String, dynamic> decoded, {
    required _ToolResultPromptBudget budget,
    required String listKey,
    required String countKey,
    String? nextOffsetKey,
  }) {
    final result = _budgetJsonMap(decoded, budget: budget);
    final items = decoded[listKey];
    if (items is List && items.length > budget.maxListItems) {
      result
        ..[listKey] = items.take(budget.maxListItems).toList(growable: false)
        ..['${listKey}_reduced_for_prompt_budget'] = true
        ..['omitted_${listKey}_count'] = items.length - budget.maxListItems;
      final offset = decoded['offset'];
      if (nextOffsetKey != null) {
        result[nextOffsetKey] =
            (offset is int ? offset : 0) + budget.maxListItems;
      }
      if (!result.containsKey(countKey)) {
        result[countKey] = items.length;
      }
    }
    return result;
  }

  static Map<String, dynamic> _budgetDiscoveryResult(
    Map<String, dynamic> decoded, {
    required _ToolResultPromptBudget budget,
    required String listKey,
    required String countKey,
    required String noMatchHint,
    String? nextOffsetKey,
  }) {
    final result = _budgetListResult(
      decoded,
      budget: budget,
      listKey: listKey,
      countKey: countKey,
      nextOffsetKey: nextOffsetKey,
    );
    if (_isZeroMatchDiscoveryResult(decoded, listKey, countKey) &&
        !result.containsKey('discovery_hint')) {
      result['discovery_hint'] = noMatchHint;
    }
    return result;
  }

  static bool _isZeroMatchDiscoveryResult(
    Map<String, dynamic> decoded,
    String listKey,
    String countKey,
  ) {
    if (decoded.containsKey('error')) {
      return false;
    }
    final items = decoded[listKey];
    if (items is! List || items.isNotEmpty) {
      return false;
    }
    final count = decoded[countKey];
    return count == null || count == 0;
  }

  static const _findFilesNoMatchHint =
      'No matches only means this exact filename glob returned nothing. '
      'Do not conclude the requested file is absent until you inspect likely '
      'parent directories with list_directory, try broader filename patterns, '
      'or read a likely direct path.';

  static const _searchFilesNoMatchHint =
      'No matches only means this exact content query returned nothing. '
      'Do not conclude the requested file or content is absent until you '
      'broaden the query, inspect likely parent directories, try a filename '
      'search, or read a likely direct path.';

  static Map<String, dynamic> _budgetJsonMap(
    Map<String, dynamic> decoded, {
    required _ToolResultPromptBudget budget,
  }) {
    return decoded.map(
      (key, value) =>
          MapEntry(key, _budgetJsonValue(value, key: key, budget: budget)),
    );
  }

  static Object? _budgetJsonValue(
    Object? value, {
    required String key,
    required _ToolResultPromptBudget budget,
  }) {
    if (value is String) {
      if (key == 'imageBase64') {
        return value;
      }
      return _truncateTextWithMiddle(
        value,
        maxChars: budget.maxStringValueChars,
        reason: 'String field was reduced to fit the prompt budget.',
      );
    }
    if (value is List) {
      final retained = value
          .take(budget.maxListItems)
          .map((item) => _budgetJsonValue(item, key: key, budget: budget))
          .toList(growable: false);
      if (value.length <= budget.maxListItems) {
        return retained;
      }
      return [
        ...retained,
        {'omitted_items_for_prompt_budget': value.length - budget.maxListItems},
      ];
    }
    if (value is Map) {
      return value.map(
        (mapKey, mapValue) => MapEntry(
          mapKey.toString(),
          _budgetJsonValue(mapValue, key: mapKey.toString(), budget: budget),
        ),
      );
    }
    return value;
  }

  static String _buildReadMoreHint(Map<String, dynamic> decoded) {
    final path = decoded['path'];
    final startLine = decoded['start_line'];
    final lineCount = decoded['line_count'];
    final totalLines = decoded['total_lines'];
    if (path is String &&
        startLine is int &&
        lineCount is int &&
        totalLines is int &&
        lineCount > 0 &&
        startLine + lineCount <= totalLines) {
      final nextOffset = startLine + lineCount;
      return 'Call read_file with path "$path", offset $nextOffset, and a smaller limit to inspect omitted lines.';
    }
    if (path is String) {
      return 'Call read_file with path "$path", offset, and limit to inspect a smaller exact range.';
    }
    return 'Call read_file with offset and limit to inspect a smaller exact range.';
  }

  static String _truncateTextWithMiddle(
    String value, {
    required int maxChars,
    required String reason,
  }) {
    if (value.length <= maxChars) {
      return value;
    }
    final marker =
        '\n\n[$reason Omitted ${value.length - maxChars} character(s).]\n\n';
    if (maxChars <= marker.length + 20) {
      return value.substring(0, math.max(0, maxChars));
    }
    final retainedChars = maxChars - marker.length;
    final headChars = (retainedChars * 0.65).floor();
    final tailChars = retainedChars - headChars;
    return '${value.substring(0, headChars)}$marker${value.substring(value.length - tailChars)}';
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
