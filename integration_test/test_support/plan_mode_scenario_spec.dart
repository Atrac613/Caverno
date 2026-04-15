import 'dart:convert';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
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

sealed class PlanModeWorkflowResponseSpec {
  const PlanModeWorkflowResponseSpec();

  ChatCompletionResult toChatCompletionResult();
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
    required this.finalAnswer,
    this.memorySummary = 'The user is building a host health check tool.',
    this.decisionSelections = const <PlanModeScenarioDecisionSelection>[],
    this.expectedProposalTextSnippets = const <String>[],
    this.expectedFinalTextSnippets = const <String>[],
    this.expectedLogCounts = const <String, int>{},
  });

  final String name;
  final String userPrompt;
  final String projectName;
  final List<PlanModeWorkflowResponseSpec> workflowResponses;
  final List<PlanModeScenarioTaskSpec> taskProposal;
  final List<PlanModeScenarioToolWriteSpec> toolWrites;
  final String finalAnswer;
  final String memorySummary;
  final List<PlanModeScenarioDecisionSelection> decisionSelections;
  final List<String> expectedProposalTextSnippets;
  final List<String> expectedFinalTextSnippets;
  final Map<String, int> expectedLogCounts;

  String get initialTaskTitle => taskProposal.first.title;

  Map<String, String> get expectedArtifacts => <String, String>{
    for (final write in toolWrites) write.path: write.content,
  };

  PlanModeWorkflowProposalResponseSpec get finalWorkflowProposal =>
      workflowResponses.whereType<PlanModeWorkflowProposalResponseSpec>().last;
}

class FakePlanModeChatDataSource implements ChatDataSource {
  FakePlanModeChatDataSource(this.scenario);

  final PlanModeScenarioSpec scenario;

  int _workflowResponseIndex = 0;
  int _toolWriteIndex = 0;

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
    if (prompt.startsWith(
      'Please answer the user\'s question based on the following search results.',
    )) {
      appLog('[ScenarioLLM] final answer stream');
      yield scenario.finalAnswer;
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
        completion: Future.value(_toolWriteResultAt(_toolWriteIndex)),
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
    _toolWriteIndex += 1;
    if (_toolWriteIndex < scenario.toolWrites.length) {
      appLog('[ScenarioLLM] follow-up tool call');
      return _toolWriteResultAt(_toolWriteIndex);
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

  ChatCompletionResult _toolWriteResultAt(int index) {
    final write = scenario.toolWrites[index];
    return ChatCompletionResult(
      content: '',
      finishReason: 'tool_calls',
      toolCalls: <ToolCallInfo>[
        ToolCallInfo(
          id: 'tool-write-$index',
          name: 'write_file',
          arguments: <String, dynamic>{
            'path': write.path,
            'content': write.content,
          },
        ),
      ],
    );
  }
}

List<PlanModeScenarioSpec> buildPlanModeScenarios() {
  return <PlanModeScenarioSpec>[
    PlanModeScenarioSpec(
      name: 'host_health_scaffold',
      userPrompt:
          'Create a Python script to diagnose the health of a specific host using ping.',
      projectName: 'tmp',
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
      finalAnswer:
          'I created requirements.txt and README.md to bootstrap the project scaffold.',
      expectedProposalTextSnippets: <String>[
        'Setup project structure and dependencies',
      ],
      expectedFinalTextSnippets: <String>['requirements.txt and README.md'],
      expectedLogCounts: <String, int>{
        '[ScenarioLLM] workflow proposal': 1,
        '[ScenarioLLM] task proposal': 1,
        '[ScenarioLLM] final answer stream': 1,
        '[ContentTool] Executing tool: write_file': 0,
        '[McpToolService] Executing tool: write_file': 2,
      },
    ),
    PlanModeScenarioSpec(
      name: 'cli_entrypoint_decision',
      userPrompt:
          'Create a Python host health tool and decide whether the first slice should be a CLI or a reusable module.',
      projectName: 'tmp',
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
      finalAnswer:
          'I created a CLI-first scaffold with requirements.txt and README.md.',
      decisionSelections: const <PlanModeScenarioDecisionSelection>[
        PlanModeScenarioDecisionSelection(
          question:
              'Should the first slice focus on a CLI entry point or a reusable Python module?',
          optionLabel: 'CLI entry point',
        ),
      ],
      expectedProposalTextSnippets: <String>[
        'Create the CLI scaffold files',
        'CLI-first Python host health scaffold.',
      ],
      expectedFinalTextSnippets: <String>['CLI-first scaffold'],
      expectedLogCounts: <String, int>{
        '[ScenarioLLM] workflow decision': 1,
        '[ScenarioLLM] workflow proposal': 1,
        '[ScenarioLLM] task proposal': 1,
        '[ContentTool] Executing tool: write_file': 0,
        '[McpToolService] Executing tool: write_file': 2,
      },
    ),
  ];
}
