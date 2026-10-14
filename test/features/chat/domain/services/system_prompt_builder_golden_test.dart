import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_projector.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_builder.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins `SystemPromptBuilder.build` byte for byte across a matrix of modes,
/// tools, context and workflow states, so the LL46 section refactor can move
/// blocks without changing what the model reads.
///
/// Regenerate after an intended prompt change with
/// `UPDATE_SYSTEM_PROMPT_GOLDENS=1 flutter test <this file>`, and review the
/// golden diff like any other change to model input.
void main() {
  final update = Platform.environment['UPDATE_SYSTEM_PROMPT_GOLDENS'] == '1';
  const goldenDir = 'test/goldens/system_prompt';

  for (final MapEntry(key: name, value: render) in _scenarios().entries) {
    test('system prompt golden: $name', () {
      final prompt = render();
      final file = File('$goldenDir/$name.txt');
      if (update) {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync(prompt);
        return;
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Missing golden; run with UPDATE_SYSTEM_PROMPT_GOLDENS=1.',
      );
      expect(prompt, file.readAsStringSync());
    });
  }
}

final _now = DateTime.utc(2026, 10, 14, 9, 30);

/// Every tool name the builder branches on, plus one computer-use and one
/// browser tool for its prefix checks.
const _allTools = [
  'browser_navigate',
  'computer_screenshot',
  'computer_switch_space',
  'create_routine',
  'edit_file',
  'find_files',
  'get_current_datetime',
  'git_execute_command',
  'git_finish_worktree_session',
  'inspect_file',
  'list_directory',
  'load_skill',
  'local_execute_command',
  'os_get_system_info',
  'os_log_read',
  'process_cancel',
  'process_list',
  'process_start',
  'process_status',
  'process_tail',
  'process_wait',
  'read_file',
  'recall_memory',
  'resolve_installed_dependency',
  'rollback_last_file_change',
  'run_python_script',
  'run_tests',
  'save_skill',
  'search_files',
  'search_images',
  'search_news',
  'search_past_conversations',
  'search_web',
  'searxng_web_search',
  'spawn_subagent',
  'tool_search',
  'web_search',
  'web_url_read',
  'write_file',
];

final _weakProfile = ModelCapabilityProfile(
  id: '',
  baseUrl: 'http://localhost:1234/v1',
  model: 'weak-tool-model',
  toolCallStyle: ModelToolCallStyle.embeddedToolTags,
  structuredOutputSupport: ModelStructuredOutputSupport.none,
  editFormatPreference: ModelEditFormatPreference.searchReplace,
  usableContextTokens: 4096,
).normalizedForPersistence();

final _strongProfile = ModelCapabilityProfile(
  id: '',
  baseUrl: 'http://localhost:1234/v1',
  model: 'strong-tool-model',
  toolCallStyle: ModelToolCallStyle.nativeToolCalls,
  structuredOutputSupport: ModelStructuredOutputSupport.jsonSchema,
  editFormatPreference: ModelEditFormatPreference.searchReplace,
  usableContextTokens: 32768,
).normalizedForPersistence();

const _harness = ModelHarnessConfig(
  id: 'cfg',
  model: 'weak-tool-model',
  bootstrapInstruction: 'Identify the required output artifact first.',
  failureRecoveryInstruction: 'Re-read the file before retrying an edit.',
  explorationToEditNudgeEnabled: true,
  recoveryMiddlewareEnabled: true,
);

ConversationGoal _goal({
  ConversationGoalStatus status = ConversationGoalStatus.active,
  int tokenUsage = 5000,
  int turnsUsed = 2,
  bool enabled = true,
}) => ConversationGoal(
  id: 'goal-1',
  objective: 'Fix the login crash and verify the regression test',
  status: status,
  enabled: enabled,
  tokenBudget: 20000,
  tokenUsage: tokenUsage,
  turnBudget: 5,
  turnsUsed: turnsUsed,
  createdAt: DateTime.utc(2026, 10, 14, 9),
  updatedAt: DateTime.utc(2026, 10, 14, 9),
);

const _spec = ConversationWorkflowSpec(
  goal: 'Ship the CLI',
  constraints: ['Standard library only'],
  acceptanceCriteria: ['list prints every task'],
  openQuestions: ['Should done tasks be hidden?'],
  tasks: [
    ConversationWorkflowTask(
      id: 'task-1',
      title: 'Add task persistence',
      status: ConversationWorkflowTaskStatus.completed,
      validationCommand: 'flutter test',
    ),
    ConversationWorkflowTask(
      id: 'task-2',
      title: 'Add the list command',
      targetFiles: ['lib/list.dart'],
      status: ConversationWorkflowTaskStatus.inProgress,
      notes: 'Reuse the storage helper.',
    ),
    ConversationWorkflowTask(
      id: 'task-3',
      title: 'Package the binary',
      status: ConversationWorkflowTaskStatus.blocked,
    ),
    ConversationWorkflowTask(id: 'task-4', title: 'Write the README'),
  ],
);

ExecutionSnapshot _snapshot(ConversationWorkflowStage stage) =>
    ExecutionSnapshot(
      contractHash: 'hash',
      workflowStage: stage,
      action: ExecutionSnapshotAction.verify,
      activeTaskId: 'task-2',
      activeTaskStatus: ConversationWorkflowTaskStatus.pending,
      validationStatus: ConversationExecutionValidationStatus.unknown,
      completedTaskCount: 1,
      remainingTaskCount: 1,
      unresolvedQuestionCount: 0,
      requiresValidation: true,
      latestDiagnostic: null,
      taskLifecycleStates: const {'task-1': 'accepted'},
      taskAcceptanceSummaries: const {
        'task-1': 'worktree branch feature/cli -- The flags match the spec.',
      },
    );

const _plan = ConversationPlanArtifact(
  draftMarkdown: '# Plan\n\n## Goal\nDraft',
  approvedMarkdown: '# Plan\n\n## Goal\nApproved',
);

String _coding({
  List<String> toolNames = _allTools,
  ConversationGoal? goal,
  ConversationWorkflowStage stage = ConversationWorkflowStage.idle,
  bool withWorkflow = false,
  bool isVoiceMode = false,
  String? participantRolePrompt,
  List<String> delegatedResults = const [],
  ModelCapabilityProfile? profile,
  ModelHarnessConfig? harness,
  bool fullContext = false,
}) => SystemPromptBuilder.build(
  now: _now,
  assistantMode: AssistantMode.coding,
  toolNames: toolNames,
  projectName: 'caverno',
  projectRootPath: '/tmp/caverno',
  repoMapContext: fullContext ? 'lib/main.dart\nlib/app.dart' : null,
  environmentGroundingContext: fullContext ? 'Flutter 3.47.5' : null,
  sessionMemoryContext: fullContext ? 'User prefers concise answers.' : null,
  agentsMarkdown: fullContext ? '# AGENTS\nRun tests before commit.' : null,
  skillsContext: fullContext ? '- release: ship a build' : null,
  hasPythonInputAttachment: fullContext,
  goal: goal,
  workflowStage: stage,
  workflowSpec: withWorkflow ? _spec : null,
  planArtifact: withWorkflow ? _plan : null,
  executionSnapshot: withWorkflow ? _snapshot(stage) : null,
  isVoiceMode: isVoiceMode,
  participantRolePrompt: participantRolePrompt,
  delegatedResults: delegatedResults,
  modelCapabilityProfile: profile,
  modelHarnessConfig: harness,
);

ModelCapabilityProfile _profile({
  ModelToolCallStyle toolCallStyle = ModelToolCallStyle.unknown,
  ModelStructuredOutputSupport structured =
      ModelStructuredOutputSupport.unknown,
  ModelEditFormatPreference edit = ModelEditFormatPreference.unknown,
  ModelVisionSupport vision = ModelVisionSupport.unknown,
}) => ModelCapabilityProfile(
  id: '',
  baseUrl: 'http://localhost:1234/v1',
  model: 'profiled-model',
  toolCallStyle: toolCallStyle,
  structuredOutputSupport: structured,
  editFormatPreference: edit,
  visionSupport: vision,
  usableContextTokens: 16384,
).normalizedForPersistence();

final _longPlan = ConversationPlanArtifact(
  draftMarkdown: '# Plan\n\n${List.filled(300, 'Step detail.').join(' ')}',
  approvedMarkdown: '# Plan\n\n${List.filled(300, 'Step detail.').join(' ')}',
);

Map<String, String Function()> _scenarios() => {
  'general_minimal': () => SystemPromptBuilder.build(
    now: _now,
    assistantMode: AssistantMode.general,
  ),
  'general_all_tools_ja': () => SystemPromptBuilder.build(
    now: _now,
    assistantMode: AssistantMode.general,
    languageCode: 'ja',
    toolNames: _allTools,
    sessionMemoryContext: 'User prefers concise answers.',
    environmentGroundingContext: 'macOS 26',
  ),
  'general_voice': () => SystemPromptBuilder.build(
    now: _now,
    assistantMode: AssistantMode.general,
    toolNames: _allTools,
    isVoiceMode: true,
  ),
  'plan_read_tools': () => SystemPromptBuilder.build(
    now: _now,
    assistantMode: AssistantMode.plan,
    toolNames: const ['list_directory', 'read_file'],
    projectName: 'caverno',
    projectRootPath: '/tmp/caverno',
  ),
  'coding_no_tools': () => _coding(toolNames: const []),
  'coding_all_tools_full_context': () =>
      _coding(fullContext: true, profile: _weakProfile, harness: _harness),
  'coding_strong_model': () => _coding(profile: _strongProfile),
  'coding_voice': () => _coding(isVoiceMode: true),
  'coding_goal_active': () => _coding(goal: _goal()),
  'coding_goal_budget_exhausted': () =>
      _coding(goal: _goal(tokenUsage: 20000, turnsUsed: 5)),
  'coding_goal_completed': () =>
      _coding(goal: _goal(status: ConversationGoalStatus.completed)),
  'coding_goal_disabled': () => _coding(goal: _goal(enabled: false)),
  for (final stage in ConversationWorkflowStage.values)
    'coding_workflow_${stage.name}': () =>
        _coding(goal: _goal(), stage: stage, withWorkflow: true),
  'coding_profile_no_tools_object_whole_rejected': () => _coding(
    profile: _profile(
      toolCallStyle: ModelToolCallStyle.none,
      structured: ModelStructuredOutputSupport.jsonObject,
      edit: ModelEditFormatPreference.wholeFile,
      vision: ModelVisionSupport.rejected,
    ),
  ),
  'coding_profile_diff_vision_basic': () => _coding(
    profile: _profile(
      edit: ModelEditFormatPreference.unifiedDiff,
      vision: ModelVisionSupport.basic,
    ),
  ),
  'coding_idle_approved_plan': () => SystemPromptBuilder.build(
    now: _now,
    assistantMode: AssistantMode.coding,
    toolNames: _allTools,
    projectName: 'caverno',
    planArtifact: _plan,
  ),
  'plan_idle_long_draft': () => SystemPromptBuilder.build(
    now: _now,
    assistantMode: AssistantMode.plan,
    toolNames: const ['list_directory', 'read_file'],
    projectRootPath: '/tmp/caverno',
    planArtifact: _longPlan,
  ),
  'coding_participant_role': () => _coding(
    participantRolePrompt: 'You are the reviewer. Find defects only.',
  ),
  'coding_anabasis_parent': () => ModelUsageRole.anabasisParent.runWith(
    () => _coding(
      goal: _goal(),
      stage: ConversationWorkflowStage.implement,
      withWorkflow: true,
      delegatedResults: const ['task-2: produced lib/list.dart, tests green'],
    ),
  ),
};
