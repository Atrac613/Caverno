import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

class PlanModeScenarioTaskSpec {
  const PlanModeScenarioTaskSpec({
    required this.title,
    required this.targetFiles,
    required this.validationCommand,
    required this.notes,
  });

  final String title;
  final List<String> targetFiles;
  final String validationCommand;
  final String notes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'targetFiles': targetFiles,
      'validationCommand': validationCommand,
      'notes': notes,
    };
  }
}

class PlanModeScenarioToolWriteSpec {
  const PlanModeScenarioToolWriteSpec({
    required this.path,
    required this.content,
  });

  final String path;
  final String content;
}

class PlanModeScenarioDecisionSelection {
  const PlanModeScenarioDecisionSelection({
    required this.question,
    this.optionLabel,
    this.freeTextAnswer,
  }) : assert(
         optionLabel != null || freeTextAnswer != null,
         'Either optionLabel or freeTextAnswer must be provided.',
       );

  final String question;
  final String? optionLabel;
  final String? freeTextAnswer;
}

class PlanModeSavedWorkflowExpectation {
  const PlanModeSavedWorkflowExpectation({
    this.stage,
    this.goal,
    this.taskCount,
    this.minTaskCount,
    this.firstTaskTitle,
    this.openQuestionsContain = const <String>[],
  });

  final ConversationWorkflowStage? stage;
  final String? goal;
  final int? taskCount;
  final int? minTaskCount;
  final String? firstTaskTitle;
  final List<String> openQuestionsContain;
}

class PlanModeScenarioToolOverrideSpec {
  const PlanModeScenarioToolOverrideSpec({
    required this.name,
    required this.arguments,
    required this.result,
    required this.isSuccess,
    this.errorMessage,
  });

  final String name;
  final Map<String, dynamic> arguments;
  final String result;
  final bool isSuccess;
  final String? errorMessage;
}

enum PlanModeUiPhase { decision, proposal, finalResult }

class PlanModeUiExpectation {
  const PlanModeUiExpectation.present({
    required this.phase,
    required this.text,
    this.minCount = 1,
  }) : shouldBePresent = true;

  const PlanModeUiExpectation.absent({required this.phase, required this.text})
    : shouldBePresent = false,
      minCount = 0;

  final PlanModeUiPhase phase;
  final String text;
  final bool shouldBePresent;
  final int minCount;
}

class PlanModeArtifactExpectation {
  const PlanModeArtifactExpectation({
    required this.path,
    this.shouldExist = true,
    this.exactContent,
    this.contains = const <String>[],
    this.absentSnippets = const <String>[],
  });

  final String path;
  final bool shouldExist;
  final String? exactContent;
  final List<String> contains;
  final List<String> absentSnippets;
}

class PlanModeLogExpectation {
  const PlanModeLogExpectation({
    required this.pattern,
    this.exactCount,
    this.minCount,
    this.maxCount,
  }) : assert(
         exactCount != null || minCount != null || maxCount != null,
         'At least one count constraint must be provided.',
       );

  final String pattern;
  final int? exactCount;
  final int? minCount;
  final int? maxCount;
}

sealed class PlanModeWorkflowResponseSpec {
  const PlanModeWorkflowResponseSpec();

  ChatCompletionResult toChatCompletionResult();
}

class PlanModeWorkflowRawResponseSpec extends PlanModeWorkflowResponseSpec {
  const PlanModeWorkflowRawResponseSpec({
    required this.content,
    this.finishReason = 'stop',
  });

  final String content;
  final String finishReason;

  @override
  ChatCompletionResult toChatCompletionResult() {
    return ChatCompletionResult(content: content, finishReason: finishReason);
  }
}

class PlanModeWorkflowProposalResponseSpec
    extends PlanModeWorkflowResponseSpec {
  const PlanModeWorkflowProposalResponseSpec({
    required this.workflowStage,
    required this.goal,
    required this.constraints,
    required this.acceptanceCriteria,
    this.openQuestions = const <String>[],
  });

  final String workflowStage;
  final String goal;
  final List<String> constraints;
  final List<String> acceptanceCriteria;
  final List<String> openQuestions;

  @override
  ChatCompletionResult toChatCompletionResult() {
    return ChatCompletionResult(
      content: jsonEncode(<String, dynamic>{
        'workflowStage': workflowStage,
        'goal': goal,
        'constraints': constraints,
        'acceptanceCriteria': acceptanceCriteria,
        'openQuestions': openQuestions,
      }),
      finishReason: 'stop',
    );
  }
}

class PlanModeWorkflowDecisionResponseSpec
    extends PlanModeWorkflowResponseSpec {
  const PlanModeWorkflowDecisionResponseSpec({required this.decisions});

  final List<WorkflowPlanningDecision> decisions;

  @override
  ChatCompletionResult toChatCompletionResult() {
    return ChatCompletionResult(
      content: jsonEncode(<String, dynamic>{
        'kind': 'decision',
        'decisions': decisions
            .map(
              (decision) => <String, dynamic>{
                'id': decision.id,
                'question': decision.question,
                'help': decision.help,
                if (decision.allowFreeText) 'inputMode': 'freeText',
                if (decision.freeTextPlaceholder.trim().isNotEmpty)
                  'placeholder': decision.freeTextPlaceholder,
                'options': decision.options
                    .map(
                      (option) => <String, dynamic>{
                        'id': option.id,
                        'label': option.label,
                        'description': option.description,
                      },
                    )
                    .toList(growable: false),
              },
            )
            .toList(growable: false),
      }),
      finishReason: 'stop',
    );
  }
}

class PlanModeScenarioSpec {
  const PlanModeScenarioSpec({
    required this.name,
    required this.userPrompt,
    required this.projectName,
    required this.workflowResponses,
    required this.taskProposal,
    required this.toolWrites,
    required this.continuationStreams,
    this.memorySummary = 'The user is building a host health check tool.',
    this.decisionSelections = const <PlanModeScenarioDecisionSelection>[],
    this.uiExpectations = const <PlanModeUiExpectation>[],
    this.artifactExpectations = const <PlanModeArtifactExpectation>[],
    this.logExpectations = const <PlanModeLogExpectation>[],
    this.savedWorkflowExpectation,
    this.toolOverrides = const <PlanModeScenarioToolOverrideSpec>[],
    this.tags = const <String>[],
    this.allowedWarningPatterns = const <String>[],
    this.toolCallBatchSizes = const <int>[],
    this.planningProposalTimeout = const Duration(seconds: 5),
    this.waitForExecutionCompletion = false,
    this.executionCompletionTimeout = const Duration(seconds: 20),
    this.executionStallTimeout = const Duration(seconds: 45),
  });

  final String name;
  final String userPrompt;
  final String projectName;
  final List<PlanModeWorkflowResponseSpec> workflowResponses;
  final List<PlanModeScenarioTaskSpec> taskProposal;
  final List<PlanModeScenarioToolWriteSpec> toolWrites;
  final List<String> continuationStreams;
  final String memorySummary;
  final List<PlanModeScenarioDecisionSelection> decisionSelections;
  final List<PlanModeUiExpectation> uiExpectations;
  final List<PlanModeArtifactExpectation> artifactExpectations;
  final List<PlanModeLogExpectation> logExpectations;
  final PlanModeSavedWorkflowExpectation? savedWorkflowExpectation;
  final List<PlanModeScenarioToolOverrideSpec> toolOverrides;
  final List<String> tags;
  final List<String> allowedWarningPatterns;
  final List<int> toolCallBatchSizes;
  final Duration planningProposalTimeout;
  final bool waitForExecutionCompletion;
  final Duration executionCompletionTimeout;
  final Duration executionStallTimeout;

  String get initialTaskTitle => taskProposal.first.title;

  List<PlanModeArtifactExpectation> get resolvedArtifactExpectations {
    if (artifactExpectations.isNotEmpty) {
      return artifactExpectations;
    }
    return toolWrites
        .map(
          (write) => PlanModeArtifactExpectation(
            path: write.path,
            exactContent: write.content,
          ),
        )
        .toList(growable: false);
  }

  PlanModeWorkflowProposalResponseSpec? get lastExplicitWorkflowProposal {
    for (final response in workflowResponses.reversed) {
      if (response is PlanModeWorkflowProposalResponseSpec) {
        return response;
      }
    }
    return null;
  }

  PlanModeSavedWorkflowExpectation get resolvedWorkflowExpectation {
    if (savedWorkflowExpectation != null) {
      return savedWorkflowExpectation!;
    }

    final proposal = lastExplicitWorkflowProposal;
    return PlanModeSavedWorkflowExpectation(
      goal: proposal?.goal,
      taskCount: taskProposal.length,
      firstTaskTitle: taskProposal.firstOrNull?.title,
      openQuestionsContain: proposal?.openQuestions ?? const <String>[],
    );
  }

  List<int> get resolvedToolCallBatchSizes {
    if (toolWrites.isEmpty) {
      return const <int>[];
    }
    if (toolCallBatchSizes.isEmpty) {
      return List<int>.filled(toolWrites.length, 1, growable: false);
    }

    final totalWrites = toolCallBatchSizes.fold<int>(
      0,
      (sum, batchSize) => sum + batchSize,
    );
    if (totalWrites != toolWrites.length) {
      throw StateError(
        'Scenario "$name" configured toolCallBatchSizes=$toolCallBatchSizes '
        'for ${toolWrites.length} tool writes.',
      );
    }

    return toolCallBatchSizes;
  }
}

class FakePlanModeChatDataSource implements ChatDataSource {
  FakePlanModeChatDataSource(this.scenario);

  final PlanModeScenarioSpec scenario;

  int _workflowResponseIndex = 0;
  int _toolWriteIndex = 0;
  int _toolCallBatchIndex = 0;
  int _continuationStreamIndex = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final prompt = messages.last.content;

    if (messages.first.content.startsWith(
      'You extract reusable user memory from a conversation.',
    )) {
      appLog('[ScenarioLLM] memory extraction');
      return ChatCompletionResult(
        content: jsonEncode(<String, dynamic>{
          'summary': scenario.memorySummary,
          'open_loops': const <String>[],
          'profile': <String, dynamic>{
            'persona': const <String>[],
            'preferences': const <String>[],
            'constraints': const <String>[],
          },
        }),
        finishReason: 'stop',
      );
    }

    if (prompt.contains(
      'Create a workflow proposal for the current coding thread.',
    )) {
      final response = _nextWorkflowResponse();
      if (response is PlanModeWorkflowDecisionResponseSpec) {
        appLog('[ScenarioLLM] workflow decision');
      } else {
        appLog('[ScenarioLLM] workflow proposal');
      }
      return response.toChatCompletionResult();
    }

    if (prompt.contains(
      'Create a task proposal for the current coding thread.',
    )) {
      appLog('[ScenarioLLM] task proposal');
      return ChatCompletionResult(
        content: jsonEncode(<String, dynamic>{
          'tasks': scenario.taskProposal
              .map((task) => task.toJson())
              .toList(growable: false),
        }),
        finishReason: 'stop',
      );
    }

    appLog('[ScenarioLLM] createChatCompletion fallback');
    return ChatCompletionResult(content: '{}', finishReason: 'stop');
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final prompt = messages.last.content;
    final isFinalToolAnswerPrompt = prompt.startsWith(
      'Please answer the user\'s question based on the following tool results.',
    );
    final isSearchAnswerPrompt = prompt.startsWith(
      'Please answer the user\'s question based on the following search results.',
    );
    final isContinuationPrompt = prompt.startsWith(
      'Continue the task using the following tool results.',
    );
    if (isFinalToolAnswerPrompt ||
        isSearchAnswerPrompt ||
        isContinuationPrompt) {
      if (_continuationStreamIndex >= scenario.continuationStreams.length) {
        appLog('[ScenarioLLM] continuation stream exhausted');
        return;
      }

      final response = scenario.continuationStreams[_continuationStreamIndex++];
      final isLastStream =
          _continuationStreamIndex == scenario.continuationStreams.length;
      appLog(
        isLastStream
            ? '[ScenarioLLM] final answer stream'
            : '[ScenarioLLM] continuation stream',
      );
      yield response;
      return;
    }

    appLog('[ScenarioLLM] empty stream fallback');
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final prompt = messages.last.content;
    if (prompt.contains('Use the saved task "${scenario.initialTaskTitle}"') &&
        scenario.toolWrites.isNotEmpty) {
      appLog('[ScenarioLLM] implementation tool call stream');
      return StreamWithToolsResult(
        stream: const Stream<String>.empty(),
        completion: Future.value(_toolWriteResultBatchAt(_toolWriteIndex)),
      );
    }

    appLog('[ScenarioLLM] streamWithTools fallback');
    return StreamWithToolsResult(
      stream: const Stream<String>.empty(),
      completion: Future.value(
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ),
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    return createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: toolCallId,
          name: toolName,
          arguments: toolArguments.isEmpty
              ? const <String, dynamic>{}
              : jsonDecode(toolArguments) as Map<String, dynamic>,
          result: toolResult,
        ),
      ],
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    _toolWriteIndex += toolResults.length;
    if (_toolWriteIndex < scenario.toolWrites.length) {
      appLog('[ScenarioLLM] follow-up tool call');
      return _toolWriteResultBatchAt(_toolWriteIndex);
    }

    appLog('[ScenarioLLM] tool loop complete');
    return ChatCompletionResult(content: '', finishReason: 'stop');
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return const Stream<String>.empty();
  }

  PlanModeWorkflowResponseSpec _nextWorkflowResponse() {
    if (_workflowResponseIndex < scenario.workflowResponses.length) {
      return scenario.workflowResponses[_workflowResponseIndex++];
    }
    return scenario.workflowResponses.last;
  }

  ChatCompletionResult _toolWriteResultBatchAt(int startIndex) {
    final batchSizes = scenario.resolvedToolCallBatchSizes;
    final batchSize = batchSizes[_toolCallBatchIndex++];
    final writes = scenario.toolWrites
        .skip(startIndex)
        .take(batchSize)
        .toList(growable: false);

    if (writes.length != batchSize) {
      throw StateError(
        'Scenario "${scenario.name}" requested $batchSize tool writes in a '
        'batch but only ${writes.length} remained.',
      );
    }

    return ChatCompletionResult(
      content: '',
      finishReason: 'tool_calls',
      toolCalls: List<ToolCallInfo>.generate(writes.length, (offset) {
        final writeIndex = startIndex + offset;
        final write = writes[offset];
        return ToolCallInfo(
          id: 'tool-write-$writeIndex',
          name: 'write_file',
          arguments: <String, dynamic>{
            'path': write.path,
            'content': write.content,
          },
        );
      }, growable: false),
    );
  }
}

class FakePlanModeMcpToolService extends McpToolService {
  FakePlanModeMcpToolService(this.scenario) : super();

  final PlanModeScenarioSpec scenario;
  int _toolOverrideIndex = 0;

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final override = _nextMatchingOverride(name: name, arguments: arguments);
    if (override != null) {
      appLog('[ScenarioTool] Overriding tool result for $name');
      return McpToolResult(
        toolName: name,
        result: override.result,
        isSuccess: override.isSuccess,
        errorMessage: override.errorMessage,
      );
    }

    return super.executeTool(name: name, arguments: arguments);
  }

  PlanModeScenarioToolOverrideSpec? _nextMatchingOverride({
    required String name,
    required Map<String, dynamic> arguments,
  }) {
    if (_toolOverrideIndex >= scenario.toolOverrides.length) {
      return null;
    }

    final override = scenario.toolOverrides[_toolOverrideIndex];
    if (override.name != name) {
      return null;
    }
    if (!_matchesScenarioArguments(override.arguments, arguments)) {
      return null;
    }

    _toolOverrideIndex += 1;
    return override;
  }
}

bool _matchesScenarioArguments(
  Map<String, dynamic> expected,
  Map<String, dynamic> actual,
) {
  for (final entry in expected.entries) {
    final actualValue = actual[entry.key];
    if (!_scenarioArgumentValueMatches(
      entry.value,
      actualValue,
      key: entry.key,
    )) {
      return false;
    }
  }
  return true;
}

bool _scenarioArgumentValueMatches(
  Object? expected,
  Object? actual, {
  String? key,
}) {
  if (expected is Map && actual is Map) {
    return _matchesScenarioArguments(
      Map<String, dynamic>.from(expected),
      Map<String, dynamic>.from(actual),
    );
  }

  if (expected is List && actual is List) {
    if (expected.length != actual.length) {
      return false;
    }
    for (var index = 0; index < expected.length; index++) {
      if (!_scenarioArgumentValueMatches(expected[index], actual[index])) {
        return false;
      }
    }
    return true;
  }

  if (key == 'path' && expected is String && actual is String) {
    return actual == expected || actual.endsWith('/$expected');
  }

  return expected == actual;
}

List<PlanModeScenarioSpec> buildPlanModeScenarios() {
  return <PlanModeScenarioSpec>[
    PlanModeScenarioSpec(
      name: 'clarify_fallback_after_decisions',
      userPrompt:
          'Create a monitoring script plan and keep asking if the direction still needs clarification.',
      projectName: 'tmp',
      tags: const <String>['fake', 'recovery', 'clarify', 'decision'],
      workflowResponses: <PlanModeWorkflowResponseSpec>[
        const PlanModeWorkflowProposalResponseSpec(
          workflowStage: 'plan',
          goal: 'Plan a small monitoring script scaffold.',
          constraints: <String>[
            'Keep the first slice reviewable.',
            'Document the unresolved direction before implementation.',
          ],
          acceptanceCriteria: <String>[
            'The saved workflow captures the remaining blocker clearly.',
          ],
          openQuestions: <String>['Should we use SSH checks or HTTP checks?'],
        ),
        PlanModeWorkflowDecisionResponseSpec(
          decisions: <WorkflowPlanningDecision>[
            WorkflowPlanningDecision(
              id: 'delivery_shape',
              question:
                  'Should the scaffold start with a CLI entry point or a background job?',
              help: 'Pick the initial delivery shape.',
              options: const <WorkflowPlanningDecisionOption>[
                WorkflowPlanningDecisionOption(
                  id: 'cli',
                  label: 'CLI entry point',
                  description: 'Start with a command line entry point.',
                ),
                WorkflowPlanningDecisionOption(
                  id: 'job',
                  label: 'Background job',
                  description: 'Start with a scheduled job scaffold.',
                ),
              ],
            ),
          ],
        ),
        PlanModeWorkflowDecisionResponseSpec(
          decisions: <WorkflowPlanningDecision>[
            WorkflowPlanningDecision(
              id: 'report_format',
              question: 'Which report format should the first slice generate?',
              help: 'Choose the first reporting format.',
              options: const <WorkflowPlanningDecisionOption>[
                WorkflowPlanningDecisionOption(
                  id: 'json',
                  label: 'JSON report',
                  description: 'Emit a machine-readable JSON summary.',
                ),
                WorkflowPlanningDecisionOption(
                  id: 'markdown',
                  label: 'Markdown report',
                  description: 'Emit a markdown status summary.',
                ),
              ],
            ),
          ],
        ),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[
        PlanModeScenarioTaskSpec(
          title: 'Capture the unresolved reporting blocker',
          targetFiles: <String>['clarify_notes.md'],
          validationCommand: 'ls clarify_notes.md',
          notes:
              'Record the remaining open question before implementation proceeds.',
        ),
      ],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[
        PlanModeScenarioToolWriteSpec(
          path: 'clarify_notes.md',
          content:
              '# Clarify Next\n\nOpen question: Which report format should the first slice generate?\n',
        ),
      ],
      continuationStreams: const <String>[
        'I captured the remaining reporting blocker in clarify_notes.md so the next planning pass can converge faster.',
      ],
      decisionSelections: const <PlanModeScenarioDecisionSelection>[
        PlanModeScenarioDecisionSelection(
          question: 'Should we use SSH checks or HTTP checks?',
          optionLabel: 'SSH checks',
        ),
        PlanModeScenarioDecisionSelection(
          question:
              'Should the scaffold start with a CLI entry point or a background job?',
          optionLabel: 'CLI entry point',
        ),
        PlanModeScenarioDecisionSelection(
          question: 'Which report format should the first slice generate?',
          optionLabel: 'JSON report',
        ),
      ],
      savedWorkflowExpectation: const PlanModeSavedWorkflowExpectation(
        stage: ConversationWorkflowStage.implement,
        goal: 'Plan a small monitoring script scaffold.',
        taskCount: 1,
        firstTaskTitle: 'Capture the unresolved reporting blocker',
        openQuestionsContain: <String>[
          'Which report format should the first slice generate?',
        ],
      ),
      uiExpectations: <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Plan a small monitoring script scaffold.',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Which report format should the first slice generate?',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.finalResult,
          text: 'remaining reporting blocker',
        ),
      ],
      artifactExpectations: <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'clarify_notes.md',
          exactContent:
              '# Clarify Next\n\nOpen question: Which report format should the first slice generate?\n',
          contains: <String>[
            'Which report format should the first slice generate?',
          ],
        ),
      ],
      logExpectations: <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern:
              '[Workflow] Using fallback proposal after repeated planning decision rounds',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] workflow proposal',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] workflow decision',
          exactCount: 2,
        ),
      ],
      allowedWarningPatterns: const <String>[
        '[Workflow] Using fallback proposal',
      ],
    ),
    PlanModeScenarioSpec(
      name: 'reasoning_only_proposal_recovery',
      userPrompt:
          'Create a Python readiness plan for a host health checker with a minimal first slice.',
      projectName: 'tmp',
      tags: const <String>['fake', 'recovery', 'proposal'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowRawResponseSpec(
          content: '''
<think>
* Workflow Stage: Plan
* Goal: Create a Python host health checker scaffold.
* Constraints: Keep the first slice lightweight.
* Acceptance Criteria: The scaffold documents the first runnable slice.
* Open Questions: Which host configuration source should the script read first?
</think>
''',
        ),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[
        PlanModeScenarioTaskSpec(
          title: 'Document the recovered scaffold plan',
          targetFiles: <String>['plan.md'],
          validationCommand: 'ls plan.md',
          notes:
              'Capture the recovered workflow summary in a single planning note.',
        ),
      ],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[
        PlanModeScenarioToolWriteSpec(
          path: 'plan.md',
          content:
              '# Plan\n\nGoal: Create a Python host health checker scaffold.\n',
        ),
      ],
      continuationStreams: const <String>[
        'I recovered the reasoning-only proposal and documented it in plan.md.',
      ],
      savedWorkflowExpectation: const PlanModeSavedWorkflowExpectation(
        stage: ConversationWorkflowStage.implement,
        goal: 'Create a Python host health checker scaffold.',
        taskCount: 1,
        firstTaskTitle: 'Document the recovered scaffold plan',
        openQuestionsContain: <String>[
          'Which host configuration source should the script read first?',
        ],
      ),
      uiExpectations: <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Create a Python host health checker scaffold.',
        ),
        PlanModeUiExpectation.absent(
          phase: PlanModeUiPhase.proposal,
          text: '\'workflowStage\'',
        ),
        PlanModeUiExpectation.absent(
          phase: PlanModeUiPhase.proposal,
          text: 'Recent Context:',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.finalResult,
          text: 'reasoning-only proposal',
        ),
      ],
      artifactExpectations: <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'plan.md',
          exactContent:
              '# Plan\n\nGoal: Create a Python host health checker scaffold.\n',
          contains: <String>['Create a Python host health checker scaffold.'],
        ),
      ],
      logExpectations: <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] workflow proposal',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] task proposal',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] final answer stream',
          exactCount: 1,
        ),
      ],
    ),
    PlanModeScenarioSpec(
      name: 'permission_denied_blocks_auto_continue',
      userPrompt:
          'Create a Python host health scaffold and keep moving through the saved tasks automatically.',
      projectName: 'tmp',
      tags: const <String>['fake', 'tool-error', 'auto-continue'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowProposalResponseSpec(
          workflowStage: 'plan',
          goal:
              'Create a Python host health scaffold with automatic task progression.',
          constraints: <String>['Keep the first slice small and file-based.'],
          acceptanceCriteria: <String>[
            'The scaffold is created.',
            'Automatic continuation stops when file access is denied.',
          ],
        ),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[
        PlanModeScenarioTaskSpec(
          title: 'Create the scaffold files',
          targetFiles: <String>['requirements.txt', 'README.md'],
          validationCommand: 'ls README.md',
          notes: 'Start with the project scaffold.',
        ),
        PlanModeScenarioTaskSpec(
          title: 'Implement the executable entry point',
          targetFiles: <String>['main.py'],
          validationCommand: 'python main.py --help',
          notes: 'Create the first runnable command after the scaffold exists.',
        ),
      ],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[
        PlanModeScenarioToolWriteSpec(
          path: 'requirements.txt',
          content: 'ping3>=4.0.0\n',
        ),
        PlanModeScenarioToolWriteSpec(
          path: 'README.md',
          content:
              '# Host Health Check\n\nThis scaffold starts with a simple ping-based flow.\n',
        ),
      ],
      continuationStreams: const <String>[
        'Task 1 is complete. Starting task 2 now.\n<tool_use>{"name":"write_file","arguments":{"path":"main.py","content":"from ping3 import ping\\n\\nprint(\\"ready\\")\\n"}}</tool_use>',
      ],
      toolOverrides: const <PlanModeScenarioToolOverrideSpec>[
        PlanModeScenarioToolOverrideSpec(
          name: 'write_file',
          arguments: <String, dynamic>{
            'path': 'main.py',
            'content': 'from ping3 import ping\n\nprint("ready")\n',
          },
          result:
              '{"error":"Access denied for the selected project","code":"permission_denied","path":"main.py"}',
          isSuccess: false,
          errorMessage: 'permission_denied',
        ),
      ],
      uiExpectations: <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.finalResult,
          text: 'Task 1 is complete. Starting task 2 now.',
        ),
      ],
      artifactExpectations: <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'requirements.txt',
          exactContent: 'ping3>=4.0.0\n',
        ),
        PlanModeArtifactExpectation(
          path: 'README.md',
          exactContent:
              '# Host Health Check\n\nThis scaffold starts with a simple ping-based flow.\n',
        ),
        PlanModeArtifactExpectation(path: 'main.py', shouldExist: false),
      ],
      logExpectations: <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[ContentTool] Execution failed: permission_denied',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] final answer stream',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] continuation stream',
          exactCount: 0,
        ),
      ],
    ),
    PlanModeScenarioSpec(
      name: 'auto_continue_across_saved_tasks',
      userPrompt:
          'Create a Python host health scaffold and keep moving through the saved tasks automatically.',
      projectName: 'tmp',
      tags: const <String>['fake', 'artifact', 'auto-continue'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowProposalResponseSpec(
          workflowStage: 'plan',
          goal:
              'Create a Python host health scaffold that auto-continues across saved tasks.',
          constraints: <String>[
            'Finish the first two saved tasks automatically.',
          ],
          acceptanceCriteria: <String>[
            'The scaffold files are created.',
            'main.py exists after the second saved task runs.',
          ],
        ),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[
        PlanModeScenarioTaskSpec(
          title: 'Create the scaffold files',
          targetFiles: <String>['requirements.txt', 'README.md'],
          validationCommand: 'ls README.md',
          notes: 'Start with the project scaffold.',
        ),
        PlanModeScenarioTaskSpec(
          title: 'Implement the executable entry point',
          targetFiles: <String>['main.py'],
          validationCommand: 'python main.py --help',
          notes: 'Create the first runnable command after the scaffold exists.',
        ),
      ],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[
        PlanModeScenarioToolWriteSpec(
          path: 'requirements.txt',
          content: 'ping3>=4.0.0\n',
        ),
        PlanModeScenarioToolWriteSpec(
          path: 'README.md',
          content:
              '# Host Health Check\n\nThis scaffold starts with a simple ping-based flow.\n',
        ),
      ],
      continuationStreams: const <String>[
        'Task 1 is complete. Starting task 2 now.\n<tool_use>{"name":"write_file","arguments":{"path":"main.py","content":"from ping3 import ping\\n\\n\\ndef main() -> None:\\n    print(\\"ready\\")\\n\\n\\nif __name__ == \\"__main__\\":\\n    main()\\n"}}</tool_use>',
        'I completed task 2 by creating main.py, so the scaffold auto-continued through both saved tasks.',
      ],
      uiExpectations: <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.finalResult,
          text: 'auto-continued through both saved tasks',
        ),
      ],
      artifactExpectations: <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'requirements.txt',
          exactContent: 'ping3>=4.0.0\n',
        ),
        PlanModeArtifactExpectation(
          path: 'README.md',
          exactContent:
              '# Host Health Check\n\nThis scaffold starts with a simple ping-based flow.\n',
        ),
        PlanModeArtifactExpectation(
          path: 'main.py',
          contains: <String>[
            'from ping3 import ping',
            'def main() -> None:',
            'print("ready")',
          ],
        ),
      ],
      logExpectations: <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] continuation stream',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] final answer stream',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ContentTool] Executing tool: write_file',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[McpToolService] Executing tool: write_file',
          exactCount: 3,
        ),
      ],
    ),
    PlanModeScenarioSpec(
      name: 'host_health_scaffold',
      userPrompt:
          'Create a Python script to diagnose the health of a specific host using ping.',
      projectName: 'tmp',
      tags: const <String>['fake', 'smoke', 'artifact', 'ci'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowProposalResponseSpec(
          workflowStage: 'plan',
          goal:
              'Create a Python host health check scaffold that starts with ping-based diagnostics.',
          constraints: <String>[
            'Keep the first slice small and reviewable.',
            'Use a simple Python dependency list.',
          ],
          acceptanceCriteria: <String>[
            'requirements.txt exists with the initial dependency list.',
            'README.md describes the scaffolded project.',
          ],
        ),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[
        PlanModeScenarioTaskSpec(
          title: 'Setup project structure and dependencies',
          targetFiles: <String>['requirements.txt', 'README.md'],
          validationCommand: 'ls requirements.txt',
          notes:
              'Initialize the repository with basic documentation and dependency list.',
        ),
        PlanModeScenarioTaskSpec(
          title: 'Implement the ping health check entry point',
          targetFiles: <String>['main.py'],
          validationCommand: 'python main.py --help',
          notes: 'Add the first executable slice after the scaffold exists.',
        ),
      ],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[
        PlanModeScenarioToolWriteSpec(
          path: 'requirements.txt',
          content: 'ping3>=4.0.0\n',
        ),
        PlanModeScenarioToolWriteSpec(
          path: 'README.md',
          content:
              '# Host Health Check\n\nThis project bootstraps a ping-based host health check tool.\n',
        ),
      ],
      continuationStreams: const <String>[
        'I created requirements.txt and README.md to bootstrap the project scaffold.',
      ],
      uiExpectations: <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Suggested plan',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Setup project structure and dependencies',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.finalResult,
          text: 'requirements.txt and README.md',
        ),
      ],
      artifactExpectations: <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'requirements.txt',
          exactContent: 'ping3>=4.0.0\n',
          contains: <String>['ping3>=4.0.0'],
        ),
        PlanModeArtifactExpectation(
          path: 'README.md',
          exactContent:
              '# Host Health Check\n\nThis project bootstraps a ping-based host health check tool.\n',
          contains: <String>['Host Health Check', 'ping-based host health'],
        ),
      ],
      logExpectations: <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] workflow proposal',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] task proposal',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] final answer stream',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ContentTool] Executing tool: write_file',
          exactCount: 0,
        ),
        PlanModeLogExpectation(
          pattern: '[McpToolService] Executing tool: write_file',
          exactCount: 2,
        ),
      ],
    ),
    PlanModeScenarioSpec(
      name: 'batched_tool_calls',
      userPrompt:
          'Create the first scaffold files for a host health tool and return related file writes together.',
      projectName: 'tmp',
      tags: const <String>['fake', 'smoke', 'artifact', 'batch'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowProposalResponseSpec(
          workflowStage: 'plan',
          goal:
              'Create the first host health scaffold files in one implementation pass.',
          constraints: <String>[
            'Keep the first saved task small.',
            'Write the initial scaffold files in a single assistant turn.',
          ],
          acceptanceCriteria: <String>[
            'requirements.txt exists with the initial dependency.',
            'README.md describes the scaffolded project.',
          ],
        ),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[
        PlanModeScenarioTaskSpec(
          title: 'Write the initial scaffold files',
          targetFiles: <String>['requirements.txt', 'README.md'],
          validationCommand: 'ls README.md',
          notes: 'Create both scaffold files in the first implementation turn.',
        ),
      ],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[
        PlanModeScenarioToolWriteSpec(
          path: 'requirements.txt',
          content: 'ping3>=4.0.0\n',
        ),
        PlanModeScenarioToolWriteSpec(
          path: 'README.md',
          content:
              '# Host Health Check\n\nThis scaffold was written from one batched tool-call turn.\n',
        ),
      ],
      toolCallBatchSizes: const <int>[2],
      continuationStreams: const <String>[
        'I created requirements.txt and README.md from a single batched tool-call turn.',
      ],
      uiExpectations: <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.finalResult,
          text: 'single batched tool-call turn',
        ),
      ],
      artifactExpectations: <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'requirements.txt',
          exactContent: 'ping3>=4.0.0\n',
        ),
        PlanModeArtifactExpectation(
          path: 'README.md',
          exactContent:
              '# Host Health Check\n\nThis scaffold was written from one batched tool-call turn.\n',
        ),
      ],
      logExpectations: <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] implementation tool call stream',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[Tool] Retrieved 2 tool result(s) in this loop',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[McpToolService] Executing tool: write_file',
          exactCount: 2,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] final answer stream',
          exactCount: 1,
        ),
      ],
    ),
    PlanModeScenarioSpec(
      name: 'cli_entrypoint_decision',
      userPrompt:
          'Create a Python host health tool and decide whether the first slice should be a CLI or a reusable module.',
      projectName: 'tmp',
      tags: const <String>['fake', 'smoke', 'decision', 'artifact', 'ci'],
      workflowResponses: <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowDecisionResponseSpec(
          decisions: <WorkflowPlanningDecision>[
            WorkflowPlanningDecision(
              id: 'delivery_mode',
              question:
                  'Should the first slice focus on a CLI entry point or a reusable Python module?',
              help: 'Pick the shape that should guide the first plan.',
              options: const <WorkflowPlanningDecisionOption>[
                WorkflowPlanningDecisionOption(
                  id: 'cli',
                  label: 'CLI entry point',
                  description:
                      'Ship a runnable command line tool in the first slice.',
                ),
                WorkflowPlanningDecisionOption(
                  id: 'module',
                  label: 'Reusable module',
                  description:
                      'Start with library code that can be reused later.',
                ),
              ],
            ),
          ],
        ),
        const PlanModeWorkflowProposalResponseSpec(
          workflowStage: 'plan',
          goal: 'Create a CLI-first Python host health scaffold.',
          constraints: <String>[
            'Keep the first slice runnable from the terminal.',
            'Document the CLI entry point in the scaffold.',
          ],
          acceptanceCriteria: <String>[
            'requirements.txt exists with the initial dependency list.',
            'README.md explains the CLI-first scaffold.',
          ],
        ),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[
        PlanModeScenarioTaskSpec(
          title: 'Create the CLI scaffold files',
          targetFiles: <String>['requirements.txt', 'README.md'],
          validationCommand: 'ls README.md',
          notes:
              'Bootstrap a CLI-oriented scaffold before the actual implementation.',
        ),
        PlanModeScenarioTaskSpec(
          title: 'Implement the CLI host check command',
          targetFiles: <String>['main.py'],
          validationCommand: 'python main.py --help',
          notes: 'Add a CLI-first entry point for the health check.',
        ),
      ],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[
        PlanModeScenarioToolWriteSpec(
          path: 'requirements.txt',
          content: 'ping3>=4.0.0\nclick>=8.1.0\n',
        ),
        PlanModeScenarioToolWriteSpec(
          path: 'README.md',
          content:
              '# CLI Host Health Check\n\nThis scaffold starts with a CLI-first health check flow.\n',
        ),
      ],
      continuationStreams: const <String>[
        'I created a CLI-first scaffold with requirements.txt and README.md.',
      ],
      decisionSelections: const <PlanModeScenarioDecisionSelection>[
        PlanModeScenarioDecisionSelection(
          question:
              'Should the first slice focus on a CLI entry point or a reusable Python module?',
          optionLabel: 'CLI entry point',
        ),
      ],
      uiExpectations: <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.decision,
          text: 'Choose Before Planning',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.decision,
          text:
              'Should the first slice focus on a CLI entry point or a reusable Python module?',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Create the CLI scaffold files',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'CLI-first Python host health scaffold.',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.finalResult,
          text: 'CLI-first scaffold',
        ),
      ],
      artifactExpectations: <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(
          path: 'requirements.txt',
          exactContent: 'ping3>=4.0.0\nclick>=8.1.0\n',
          contains: <String>['ping3>=4.0.0', 'click>=8.1.0'],
        ),
        PlanModeArtifactExpectation(
          path: 'README.md',
          exactContent:
              '# CLI Host Health Check\n\nThis scaffold starts with a CLI-first health check flow.\n',
          contains: <String>['CLI Host Health Check', 'CLI-first health check'],
        ),
      ],
      logExpectations: <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] workflow decision',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] workflow proposal',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ScenarioLLM] task proposal',
          exactCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[ContentTool] Executing tool: write_file',
          exactCount: 0,
        ),
        PlanModeLogExpectation(
          pattern: '[McpToolService] Executing tool: write_file',
          exactCount: 2,
        ),
        PlanModeLogExpectation(
          pattern:
              '[Screenshot] Saved "plan_mode_cli_entrypoint_decision_decision_1"',
          minCount: 1,
        ),
      ],
    ),
  ];
}

List<PlanModeScenarioSpec> buildLivePlanModeScenarios() {
  return <PlanModeScenarioSpec>[
    PlanModeScenarioSpec(
      name: 'live_host_health_scaffold',
      userPrompt:
          'Create a reviewable plan for a Python host health checker scaffold. '
          'Assume a CLI-first tool for a single host with ping-only checks. '
          'Do not ask for extra clarifications unless the plan is blocked. '
          'For the first implementation slice, create only requirements.txt '
          'and README.md.',
      projectName: 'tmp-live',
      tags: const <String>['live', 'smoke', 'artifact'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowRawResponseSpec(content: '{}'),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[],
      continuationStreams: const <String>[],
      uiExpectations: const <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Suggested plan',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Approve and start',
        ),
      ],
      artifactExpectations: const <PlanModeArtifactExpectation>[
        PlanModeArtifactExpectation(path: 'requirements.txt'),
      ],
      planningProposalTimeout: const Duration(minutes: 3),
      savedWorkflowExpectation: const PlanModeSavedWorkflowExpectation(
        minTaskCount: 2,
        firstTaskTitle: 'Create requirements.txt',
      ),
      logExpectations: const <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[LLM] ========== createChatCompletion ==========',
          minCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[LLM] === Response (streamWithTools) ===',
          minCount: 1,
        ),
      ],
    ),
    PlanModeScenarioSpec(
      name: 'live_cli_entrypoint_decision',
      userPrompt:
          'Create a reviewable plan for a Python host health checker. Before '
          'you lock the workflow, ask me exactly one planning decision: '
          'whether the first slice should be a CLI entry point or a reusable '
          'module. After I choose, do not ask any more planning questions. '
          'Assume ping-only checks, use click for CLI parsing, use a Markdown '
          'README, and keep the first implementation slice limited to '
          'requirements.txt and README.md.',
      projectName: 'tmp-live-decision',
      tags: const <String>['live', 'smoke', 'decision'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowRawResponseSpec(content: '{}'),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[],
      continuationStreams: const <String>[],
      decisionSelections: const <PlanModeScenarioDecisionSelection>[
        PlanModeScenarioDecisionSelection(
          question: '',
          optionLabel: 'CLI Entry Point',
        ),
      ],
      uiExpectations: const <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.decision,
          text: 'Choose Before Planning',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Approve and start',
        ),
      ],
      artifactExpectations: const <PlanModeArtifactExpectation>[],
      allowedWarningPatterns: const <String>[
        '[Workflow] Workflow proposal parse failed',
        '[Workflow] Workflow proposal recovered on retry',
      ],
      planningProposalTimeout: const Duration(minutes: 3),
      savedWorkflowExpectation: const PlanModeSavedWorkflowExpectation(),
      logExpectations: const <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[LLM] ========== createChatCompletion ==========',
          minCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[LLM] === Response (streamWithTools) ===',
          minCount: 1,
        ),
      ],
    ),
    PlanModeScenarioSpec(
      name: 'live_ping_cli_completion',
      userPrompt: _livePromptFromEnvironment(
        'CAVERNO_PLAN_MODE_USER_PROMPT',
        fallback:
            'Create a Python CLI script that pings a specific host. '
            'Generate a reviewable plan first, then keep implementing until '
            'the approved plan finishes unless you are genuinely blocked.',
      ),
      projectName: 'tmp-live-ping-cli',
      tags: const <String>['live', 'automation', 'completion'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowRawResponseSpec(content: '{}'),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[],
      continuationStreams: const <String>[],
      uiExpectations: const <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Approve and start',
        ),
      ],
      planningProposalTimeout: const Duration(minutes: 3),
      waitForExecutionCompletion: true,
      executionCompletionTimeout: const Duration(minutes: 3),
      executionStallTimeout: const Duration(seconds: 45),
      savedWorkflowExpectation: const PlanModeSavedWorkflowExpectation(
        minTaskCount: 2,
      ),
      logExpectations: const <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[Workflow] Planning research pass started',
          minCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[LLM] ========== createChatCompletion ==========',
          minCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[LLM] === Response (streamWithTools) ===',
          minCount: 1,
        ),
      ],
    ),
    PlanModeScenarioSpec(
      name: 'live_clarify_recovery',
      userPrompt:
          'Create a reviewable plan for a Python host health checker. You may '
          'ask exactly one planning decision if the scope is still ambiguous, '
          'and if anything remains unresolved after that, keep it in open '
          'questions instead of blocking the workflow. Use the exact option '
          'labels "JSON Report" and "Markdown Report" if you ask about the '
          'first reporting format. Keep the first implementation slice limited '
          'to requirements.txt and README.md.',
      projectName: 'tmp-live-clarify',
      tags: const <String>['live', 'smoke', 'recovery'],
      workflowResponses: const <PlanModeWorkflowResponseSpec>[
        PlanModeWorkflowRawResponseSpec(content: '{}'),
      ],
      taskProposal: const <PlanModeScenarioTaskSpec>[],
      toolWrites: const <PlanModeScenarioToolWriteSpec>[],
      continuationStreams: const <String>[],
      decisionSelections: const <PlanModeScenarioDecisionSelection>[
        PlanModeScenarioDecisionSelection(
          question: '',
          optionLabel: 'JSON Report',
        ),
      ],
      uiExpectations: const <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Suggested plan',
        ),
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Approve and start',
        ),
      ],
      artifactExpectations: const <PlanModeArtifactExpectation>[],
      savedWorkflowExpectation: const PlanModeSavedWorkflowExpectation(),
      logExpectations: const <PlanModeLogExpectation>[
        PlanModeLogExpectation(
          pattern: '[LLM] ========== createChatCompletion ==========',
          minCount: 1,
        ),
        PlanModeLogExpectation(
          pattern: '[LLM] === Response (streamWithTools) ===',
          minCount: 1,
        ),
      ],
      planningProposalTimeout: const Duration(minutes: 3),
      allowedWarningPatterns: const <String>[
        '[Workflow] Workflow proposal parse failed',
        '[Workflow] Workflow proposal recovered on retry',
        '[Workflow] Using fallback proposal',
        '[LLM] Recovered raw text response after create parse failure',
      ],
    ),
  ];
}

String _livePromptFromEnvironment(String name, {required String fallback}) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    return fallback;
  }
  return value;
}
