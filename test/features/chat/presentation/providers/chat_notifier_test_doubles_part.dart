// Test doubles for chat_notifier_test.dart: fake/stub ChatDataSource, Notifier,
// and service implementations plus small value holders. Pure relocation from
// chat_notifier_test.dart (F1 test-file ratchet), no behavior change.
part of 'chat_notifier_test.dart';

List<String> _toolNames(List<Map<String, dynamic>> definitions) {
  return definitions
      .map((definition) {
        final function = definition['function'];
        if (function is! Map) return null;
        final name = function['name'];
        return name is String ? name : null;
      })
      .nonNulls
      .toList(growable: false);
}

AppSettings _baseTestSettings() {
  return AppSettings.defaults().copyWith(enableLlmSessionLogs: false);
}

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: false,
      demoMode: false,
    );
  }
}

class _TestConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  Conversation? ensureCurrentConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    final resolvedWorkspaceMode = workspaceMode ?? state.activeWorkspaceMode;
    if (!resolvedWorkspaceMode.usesConversations) {
      return null;
    }
    final resolvedProjectId = resolvedWorkspaceMode.usesProjects
        ? (projectId ?? state.activeProjectId)
        : null;
    if (resolvedWorkspaceMode.usesProjects &&
        (resolvedProjectId == null || resolvedProjectId.trim().isEmpty)) {
      return null;
    }
    final currentConversation = state.currentConversation;
    if (currentConversation != null) {
      return currentConversation;
    }
    final now = DateTime(2026, 5, 25, 10);
    final conversation = Conversation(
      id: 'test-conversation-${state.conversations.length + 1}',
      title: defaultConversationTitle,
      messages: const <Message>[],
      createdAt: now,
      updatedAt: now,
      workspaceMode: resolvedWorkspaceMode,
      projectId: resolvedProjectId ?? '',
    );
    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
      activeWorkspaceMode: resolvedWorkspaceMode,
      activeProjectId: resolvedProjectId,
      clearActiveProject:
          !resolvedWorkspaceMode.usesProjects || resolvedProjectId == null,
    );
    return conversation;
  }

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    final currentConversationId = state.currentConversationId;
    if (currentConversationId == null) {
      return;
    }
    await updateConversationMessages(currentConversationId, messages);
  }

  @override
  Future<void> updateConversationMessages(
    String conversationId,
    List<Message> messages,
  ) async {
    final conversation = state.conversations
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      return;
    }
    final updated = conversation.copyWith(messages: messages);
    state = state.copyWith(
      conversations: state.conversations
          .map((item) => item.id == conversationId ? updated : item)
          .toList(growable: false),
    );
  }

  @override
  Future<void> updateConversationParticipants(
    String conversationId, {
    required List<ConversationParticipant> participants,
    ParticipantTurnConfig? participantTurnConfig,
  }) async {
    final conversation = state.conversations
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      return;
    }
    final updated = conversation.copyWith(
      participants: participants,
      participantTurnConfig:
          participantTurnConfig ?? conversation.participantTurnConfig,
    );
    state = state.copyWith(
      conversations: state.conversations
          .map((item) => item.id == conversationId ? updated : item)
          .toList(growable: false),
    );
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _GoalAutoContinueConversationsNotifier
    extends _TestConversationsNotifier {
  @override
  Future<void> saveCurrentGoal({
    required String objective,
    required bool enabled,
    required ConversationGoalStatus status,
    bool? autoContinue,
    int tokenBudget = 0,
    int turnBudget = 0,
    String? blockedReason,
    String? completionSummary,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }
    final now = DateTime(2026, 5, 25, 10);
    final previous = conversation.goal;
    final goal = ConversationGoal(
      id: previous?.id ?? 'goal-auto-continue',
      objective: objective,
      enabled: enabled,
      autoContinue: autoContinue ?? previous?.autoContinue ?? false,
      status: status,
      tokenBudget: tokenBudget,
      tokenUsage: previous?.tokenUsage ?? 0,
      turnBudget: turnBudget,
      turnsUsed: previous?.turnsUsed ?? 0,
      blockedReason: status == ConversationGoalStatus.blocked
          ? blockedReason ?? ''
          : '',
      completionSummary: status == ConversationGoalStatus.completed
          ? completionSummary ?? ''
          : '',
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
      completedAt: status == ConversationGoalStatus.completed ? now : null,
      blockedAt: status == ConversationGoalStatus.blocked ? now : null,
    );
    _replaceCurrentConversation(conversation.copyWith(goal: goal));
  }

  @override
  Future<void> recordCurrentGoalTurn({
    required String assistantResponse,
    required int tokenUsageDelta,
    ToolResultCompletionEvidence completionEvidence =
        const ToolResultCompletionEvidence(),
  }) async {
    final conversation = state.currentConversation;
    final goal = conversation?.goal;
    if (conversation == null || goal == null || !goal.isActive) {
      return;
    }
    _replaceCurrentConversation(
      conversation.copyWith(
        goal: goal.copyWith(
          turnsUsed: goal.turnsUsed + 1,
          tokenUsage: goal.tokenUsage + tokenUsageDelta,
          updatedAt: DateTime(2026, 5, 25, 10, goal.turnsUsed + 1),
        ),
      ),
    );
  }

  @override
  Future<void> markCurrentGoalStatus({
    required ConversationGoalStatus status,
    String? blockedReason,
    String? completionSummary,
  }) async {
    final conversation = state.currentConversation;
    final goal = conversation?.goal;
    if (conversation == null || goal == null) {
      return;
    }
    _replaceCurrentConversation(
      conversation.copyWith(
        goal: goal.copyWith(
          status: status,
          blockedReason: status == ConversationGoalStatus.blocked
              ? blockedReason ?? ''
              : '',
          completionSummary: status == ConversationGoalStatus.completed
              ? completionSummary ?? ''
              : '',
          updatedAt: DateTime(2026, 5, 25, 10, goal.turnsUsed + 1),
        ),
      ),
    );
  }

  void _replaceCurrentConversation(Conversation updatedConversation) {
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) => conversation.id == updatedConversation.id
                ? updatedConversation
                : conversation,
          )
          .toList(growable: false),
    );
  }
}

class _TerminalSuccessGoalConversationsNotifier
    extends _GoalAutoContinueConversationsNotifier {
  String? recordedAssistantResponse;

  @override
  Future<void> recordCurrentVerificationGeneration() async {
    final conversation = state.currentConversation;
    if (conversation == null) return;
    _replaceCurrentConversation(
      conversation.copyWith(
        verificationGeneration: conversation.mutationGeneration,
      ),
    );
  }

  @override
  Future<void> recordCurrentGoalTurn({
    required String assistantResponse,
    required int tokenUsageDelta,
    ToolResultCompletionEvidence completionEvidence =
        const ToolResultCompletionEvidence(),
  }) async {
    recordedAssistantResponse = assistantResponse;
    final conversation = state.currentConversation;
    final goal = conversation?.goal;
    if (conversation == null || goal == null) return;
    final summary = assistantResponse
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    _replaceCurrentConversation(
      conversation.copyWith(
        goal: goal.copyWith(
          status: ConversationGoalStatus.completed,
          completionSummary: summary,
          turnsUsed: goal.turnsUsed + 1,
          tokenUsage: goal.tokenUsage + tokenUsageDelta,
          updatedAt: DateTime(2026, 5, 25, 10, goal.turnsUsed + 1),
        ),
      ),
    );
  }
}

class _GitLifecycleGoalConversationsNotifier
    extends _TestConversationsNotifier {
  @override
  ConversationsState build() {
    final now = DateTime(2026, 5, 25, 10);
    final conversation = Conversation(
      id: 'git-lifecycle-conversation',
      title: 'Git lifecycle',
      messages: const <Message>[],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.chat,
      goal: ConversationGoal(
        id: 'goal-1',
        objective:
            'Perform a safe Git lifecycle. Initialize the repository, create '
            'lib/git_lifecycle_note.txt containing '
            'CODING_GOAL_GIT_LIFECYCLE_OK, commit it, revert the commit with '
            'revert --no-edit HEAD, and finish only after the final git status '
            'is clean.',
        status: ConversationGoalStatus.active,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return ConversationsState(
      conversations: [conversation],
      currentConversationId: conversation.id,
      activeWorkspaceMode: WorkspaceMode.chat,
      activeProjectId: null,
    );
  }

  @override
  Future<void> recordCurrentGoalTurn({
    required String assistantResponse,
    required int tokenUsageDelta,
    ToolResultCompletionEvidence completionEvidence =
        const ToolResultCompletionEvidence(),
  }) async {
    final current = state.currentConversation;
    final goal = current?.goal;
    if (current == null || goal == null) {
      return;
    }
    final now = DateTime(2026, 5, 25, 10, goal.turnsUsed + 1);
    final normalized = assistantResponse.toLowerCase();
    final completed =
        normalized.contains('goal complete') &&
        normalized.contains('tests passed');
    final updatedGoal = goal.copyWith(
      turnsUsed: goal.turnsUsed + 1,
      tokenUsage: goal.tokenUsage + tokenUsageDelta,
      status: completed ? ConversationGoalStatus.completed : goal.status,
      completionSummary: completed
          ? 'The git lifecycle completed successfully.'
          : goal.completionSummary,
      completedAt: completed ? now : goal.completedAt,
      updatedAt: now,
    );
    final updated = current.copyWith(goal: updatedGoal, updatedAt: now);
    state = state.copyWith(
      conversations: state.conversations
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false),
    );
  }
}

class _DivergingSaveConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() {
    final conversation = Conversation(
      id: 'queue-sync-conversation',
      title: 'Queue sync',
      messages: const <Message>[],
      createdAt: DateTime(2026, 5, 25, 10),
      updatedAt: DateTime(2026, 5, 25, 10),
    );
    return ConversationsState(
      conversations: [conversation],
      currentConversationId: conversation.id,
      activeWorkspaceMode: WorkspaceMode.chat,
      activeProjectId: null,
    );
  }

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }

    await updateConversationMessages(current.id, messages);
  }

  @override
  Future<void> updateConversationMessages(
    String conversationId,
    List<Message> messages,
  ) async {
    final current = state.conversations
        .where((conversation) => conversation.id == conversationId)
        .firstOrNull;
    if (current == null) {
      return;
    }

    final persistedMessages = messages
        .map(
          (message) => message.role == MessageRole.assistant
              ? message.copyWith(
                  content: message.content.endsWith(' persisted')
                      ? message.content
                      : '${message.content} persisted',
                )
              : message,
        )
        .toList(growable: false);
    final updated = current.copyWith(messages: persistedMessages);
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) =>
                conversation.id == updated.id ? updated : conversation,
          )
          .toList(growable: false),
    );
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _WorkflowTestConversationsNotifier extends ConversationsNotifier {
  _WorkflowTestConversationsNotifier(this.conversation);

  final Conversation conversation;

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.normalizedProjectId,
  );

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }
    await updateConversationMessages(current.id, messages);
  }

  @override
  Future<void> updateConversationMessages(
    String conversationId,
    List<Message> messages,
  ) async {
    final current = state.conversations
        .where((conversation) => conversation.id == conversationId)
        .firstOrNull;
    if (current == null) {
      return;
    }
    final updated = current.copyWith(messages: messages);
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) =>
                conversation.id == updated.id ? updated : conversation,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _FixedConversationsNotifier extends ConversationsNotifier {
  _FixedConversationsNotifier(this.initialState);

  final ConversationsState initialState;

  @override
  ConversationsState build() => initialState;
}

class _FixedCodingProjectsNotifier extends CodingProjectsNotifier {
  _FixedCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() =>
      CodingProjectsState(projects: [project], selectedProjectId: project.id);

  @override
  Future<bool> ensureProjectAccess(String? projectId) async => true;
}

class _MockConversationBox extends Mock implements Box<String> {}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());

  final Map<String, Conversation> _store = {};

  @override
  List<Conversation> getAll() {
    final conversations = _store.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Conversation? getById(String id) => _store[id];

  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}

class _DelayedConversationRepository extends _FakeConversationRepository {
  _DelayedConversationRepository({required this.saveDelay});

  final Duration saveDelay;

  @override
  Future<void> save(Conversation conversation) async {
    await Future<void>.delayed(saveDelay);
    await super.save(conversation);
  }
}

class _MockMemoryBox extends Mock implements Box<String> {}

class _TestSessionMemoryService extends SessionMemoryService {
  _TestSessionMemoryService()
    : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) {
    return null;
  }

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    return const MemoryUpdateResult.none();
  }

  @override
  UserMemoryProfile loadProfile() {
    return UserMemoryProfile.empty();
  }
}

class _TrackingSessionMemoryService extends _TestSessionMemoryService {
  int updateCount = 0;
  final List<List<Message>> updateMessages = [];
  final Completer<void> firstUpdate = Completer<void>();

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    updateCount += 1;
    updateMessages.add(List<Message>.from(messages));
    if (!firstUpdate.isCompleted) {
      firstUpdate.complete();
    }
    return const MemoryUpdateResult.none();
  }
}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _MockSshService extends Mock implements SshService {}

class _MockSshCredentialsManager extends Mock
    implements SshCredentialsManager {}

class _TestBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _FakeNotificationService extends NotificationService {
  final List<_NotificationCall> calls = [];

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {
    calls.add(_NotificationCall(title: title, body: body));
  }
}

class _NotificationCall {
  const _NotificationCall({required this.title, required this.body});

  final String title;
  final String body;
}

/// In-memory [SkillsNotifier] for save_skill tests: persists upserts in state
/// (resolving updates by id) without a Hive-backed repository.
class _RecordingSkillsNotifier extends SkillsNotifier {
  @override
  SkillsState build() => SkillsState.initial();

  @override
  Future<Skill> upsertMarkdown({
    String? existingId,
    required String markdown,
    bool enabled = true,
  }) async {
    final parsed = SkillMarkdownParser.parse(markdown);
    final now = DateTime(2026, 6, 22, 19, 30);
    Skill? existing;
    for (final skill in state.skills) {
      if (skill.id == existingId) {
        existing = skill;
        break;
      }
    }
    final saved = Skill(
      id: existing?.id ?? 'skill-${state.skills.length + 1}',
      name: parsed.name,
      description: parsed.description,
      whenToUse: parsed.whenToUse,
      content: parsed.content,
      enabled: existing?.enabled ?? enabled,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    state = SkillsState(
      skills: [
        for (final skill in state.skills)
          if (skill.id != saved.id) skill,
        saved,
      ],
    );
    return saved;
  }
}

/// In-memory [RoutinesNotifier] for create_routine tests: records created
/// routines in state without touching SharedPreferences or the scheduler.
class _RecordingRoutinesNotifier extends RoutinesNotifier {
  @override
  RoutinesState build() => const RoutinesState(routines: []);

  @override
  Future<void> createRoutine({
    required String name,
    required String prompt,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required RoutineScheduleMode scheduleMode,
    required int timeOfDayMinutes,
    required bool enabled,
    required bool notifyOnCompletion,
    required bool toolsEnabled,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
    String workspaceDirectory = '',
    bool allowWorkspaceWrites = false,
  }) async {
    final now = DateTime(2026, 6, 23, 22, 0);
    final routine = Routine(
      id: 'routine-${state.routines.length + 1}',
      name: name.trim(),
      prompt: prompt.trim(),
      createdAt: now,
      updatedAt: now,
      enabled: enabled,
      notifyOnCompletion: notifyOnCompletion,
      toolsEnabled: toolsEnabled,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      workspaceDirectory: workspaceDirectory,
      allowWorkspaceWrites: allowWorkspaceWrites,
      intervalValue: intervalValue,
      intervalUnit: intervalUnit,
      scheduleMode: scheduleMode,
      timeOfDayMinutes: timeOfDayMinutes,
      nextRunAt: now.add(const Duration(hours: 1)),
    );
    state = RoutinesState(routines: [...state.routines, routine]);
  }
}

class _ReleaseCheckSkillsNotifier extends SkillsNotifier {
  @override
  SkillsState build() {
    final now = DateTime(2026, 5, 29, 20, 28);
    return SkillsState(
      skills: [
        Skill(
          id: 'release-check',
          name: 'Release Check',
          description: 'Use for release readiness checks',
          whenToUse: 'When the user asks to verify a release',
          content:
              'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }
}

class _StreamingChatDataSource implements ChatDataSource, FinishReasonAware {
  _StreamingChatDataSource(this.controller, {this.lastFinishReason});

  final StreamController<String> controller;

  @override
  final String? lastFinishReason;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return controller.stream;
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _ToolAwareStreamingChatDataSource implements ChatDataSource {
  _ToolAwareStreamingChatDataSource(this.controller);

  final StreamController<String> controller;
  int toolAwareRequestCount = 0;
  List<String> requestedToolNames = const [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return controller.stream;
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    toolAwareRequestCount += 1;
    requestedToolNames = tools
        .map((tool) => (tool['function'] as Map?)?['name'])
        .whereType<String>()
        .toList(growable: false);
    final chunks = <String>[];
    final completion = Completer<ChatCompletionResult>();
    final stream = controller.stream.transform<String>(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          chunks.add(chunk);
          sink.add(chunk);
        },
        handleError: (error, stackTrace, sink) {
          if (!completion.isCompleted) {
            completion.completeError(error, stackTrace);
          }
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          if (!completion.isCompleted) {
            completion.complete(
              ChatCompletionResult(
                content: chunks.join(),
                finishReason: 'stop',
              ),
            );
          }
          sink.close();
        },
      ),
    );
    return StreamWithToolsResult(stream: stream, completion: completion.future);
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _FoundationModelsContextFallbackDataSource implements ChatDataSource {
  int toolAwareRequestCount = 0;
  int normalRequestCount = 0;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    normalRequestCount += 1;
    return Stream<String>.fromIterable(const ['fallback response']);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    toolAwareRequestCount += 1;
    return StreamWithToolsResult(
      stream: Stream<String>.error(
        Exception(
          'Exceeded model context window size: '
          'exceededContextWindowSize(Content contains 6575 tokens, '
          'which exceeds the maximum allowed context size of 4096.)',
        ),
      ),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ),
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _ControllableQueueChatDataSource implements ChatDataSource {
  _ControllableQueueChatDataSource(this.controllers);

  final Queue<StreamController<String>> controllers;
  final List<List<Message>> requests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requests.add(List<Message>.from(messages));
    return controllers.removeFirst().stream;
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _DelayedAskQuestionToolChatDataSource implements ChatDataSource {
  _DelayedAskQuestionToolChatDataSource({required this.initialCompletion});

  final Completer<ChatCompletionResult> initialCompletion;
  final List<String> finalAnswerChunks = const [
    'Proceeding with the selected option.',
  ];
  final List<List<Message>> initialRequests = [];
  final List<List<Message>> finalAnswerRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    finalAnswerRequests.add(List<Message>.from(messages));
    return Stream<String>.fromIterable(finalAnswerChunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequests.add(List<Message>.from(messages));
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: initialCompletion.future,
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    return Future<ChatCompletionResult>.value(
      ChatCompletionResult(content: '', finishReason: 'stop'),
    );
  }
}

class _SkippedSkillLoadChatDataSource implements ChatDataSource {
  _SkippedSkillLoadChatDataSource({
    required this.initialContent,
    required this.finalAnswerChunks,
  });

  final String initialContent;
  final List<String> finalAnswerChunks;
  final List<List<Message>> initialRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<Message>> finalAnswerRequests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    finalAnswerRequests.add(List<Message>.from(messages));
    return Stream<String>.fromIterable(finalAnswerChunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequests.add(List<Message>.from(messages));
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(content: initialContent, finishReason: 'stop'),
      ),
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    return Future<ChatCompletionResult>.value(
      ChatCompletionResult(content: '', finishReason: 'stop'),
    );
  }
}

class _QueuedAskQuestionToolChatDataSource implements ChatDataSource {
  _QueuedAskQuestionToolChatDataSource({
    required List<Completer<ChatCompletionResult>> initialCompletions,
    required List<String> finalAnswers,
  }) : _initialCompletions = Queue<Completer<ChatCompletionResult>>.from(
         initialCompletions,
       ),
       _finalAnswers = Queue<String>.from(finalAnswers);

  final Queue<Completer<ChatCompletionResult>> _initialCompletions;
  final Queue<String> _finalAnswers;
  final List<List<Message>> initialRequests = [];
  final List<List<Message>> finalAnswerRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<String?> initialRequestContextConversationIds = [];
  final List<String?> toolResultContextConversationIds = [];
  final List<String?> finalAnswerContextConversationIds = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    finalAnswerContextConversationIds.add(
      LlmSessionLogContext.current?.conversationId,
    );
    finalAnswerRequests.add(List<Message>.from(messages));
    return Stream<String>.fromIterable([
      _finalAnswers.isEmpty
          ? 'Proceeding with the selected option.'
          : _finalAnswers.removeFirst(),
    ]);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequestContextConversationIds.add(
      LlmSessionLogContext.current?.conversationId,
    );
    initialRequests.add(List<Message>.from(messages));
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: _initialCompletions.removeFirst().future,
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    toolResultContextConversationIds.add(
      LlmSessionLogContext.current?.conversationId,
    );
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    return Future<ChatCompletionResult>.value(
      ChatCompletionResult(content: '', finishReason: 'stop'),
    );
  }
}

class _QueuedStreamingChatDataSource implements ChatDataSource {
  _QueuedStreamingChatDataSource(List<List<String>> responses)
    : _responses = Queue<List<String>>.from(responses);

  final Queue<List<String>> _responses;
  final List<List<Message>> requests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requests.add(List<Message>.from(messages));
    if (_responses.isEmpty) {
      return const Stream<String>.empty();
    }
    return Stream<String>.fromIterable(_responses.removeFirst());
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _NativeToolFormatFallbackDataSource implements ChatDataSource {
  _NativeToolFormatFallbackDataSource(List<List<String>> plainResponses)
    : _plainResponses = Queue<List<String>>.from(plainResponses);

  final Queue<List<String>> _plainResponses;
  final List<List<Message>> toolAwareRequests = [];
  final List<List<Map<String, dynamic>>> toolAwareToolBatches = [];
  final List<List<Message>> plainRequests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    plainRequests.add(List<Message>.from(messages));
    if (_plainResponses.isEmpty) {
      return const Stream<String>.empty();
    }
    return Stream<String>.fromIterable(_plainResponses.removeFirst());
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    toolAwareRequests.add(List<Message>.from(messages));
    toolAwareToolBatches.add(List<Map<String, dynamic>>.from(tools));
    return StreamWithToolsResult(
      stream: Stream<String>.error(
        Exception(
          'StreamException: The model produced output that does not match the expected peg-native format',
        ),
      ),
      completion: Completer<ChatCompletionResult>().future,
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _ContinuationFallbackChatDataSource implements ChatDataSource {
  final List<List<Message>> streamRequests = [];
  final List<List<Message>> completionRequests = [];
  var _streamCallCount = 0;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamRequests.add(List<Message>.from(messages));
    _streamCallCount += 1;
    if (_streamCallCount == 1) {
      return Stream<String>.fromIterable(const [
        '<tool_call>{"name":"read_file","arguments":{"path":"src/config_loader.py"}}</tool_call>',
      ]);
    }
    return Stream<String>.error(
      Exception(
        'ClientException: Connection closed before full header was received',
      ),
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    completionRequests.add(List<Message>.from(messages));
    return ChatCompletionResult(
      content: 'Recovered continuation after stream failure.',
      finishReason: 'stop',
    );
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _ParticipantStreamingChatDataSource
    implements ChatDataSource, FinishReasonAware {
  _ParticipantStreamingChatDataSource({
    List<StreamController<String>> manualStreams = const [],
    List<List<String>> chunkBatches = const [],
    List<_ParticipantToolStreamResponse> toolResponses = const [],
    List<ChatCompletionResult> autoReviewResponses = const [],
  }) : _manualStreams = Queue<StreamController<String>>.from(manualStreams),
       _chunkBatches = Queue<List<String>>.from(chunkBatches),
       _toolResponses = Queue<_ParticipantToolStreamResponse>.from(
         toolResponses,
       ),
       _autoReviewResponses = Queue<ChatCompletionResult>.from(
         autoReviewResponses,
       );

  final Queue<StreamController<String>> _manualStreams;
  final Queue<List<String>> _chunkBatches;
  final Queue<_ParticipantToolStreamResponse> _toolResponses;
  final Queue<ChatCompletionResult> _autoReviewResponses;
  final List<List<Message>> streamRequests = [];
  final List<_ParticipantToolStreamRequest> toolStreamRequests = [];
  final List<List<Message>> autoReviewRequestMessages = [];
  final List<String?> requestedModels = [];

  @override
  String? get lastFinishReason => 'stop';

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamRequests.add(List<Message>.from(messages));
    requestedModels.add(model);
    if (_manualStreams.isNotEmpty) {
      return _manualStreams.removeFirst().stream;
    }
    final chunks = _chunkBatches.isEmpty
        ? const <String>[]
        : _chunkBatches.removeFirst();
    return Stream<String>.fromIterable(chunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    if ((tools == null || tools.isEmpty) &&
        messages.isNotEmpty &&
        messages.first.id == 'auto_review_policy') {
      autoReviewRequestMessages.add(List<Message>.from(messages));
      if (_autoReviewResponses.isNotEmpty) {
        return Future<ChatCompletionResult>.value(
          _autoReviewResponses.removeFirst(),
        );
      }
    }
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    toolStreamRequests.add(
      _ParticipantToolStreamRequest(
        messages: List<Message>.from(messages),
        tools: List<Map<String, dynamic>>.from(tools),
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    requestedModels.add(model);
    final response = _toolResponses.removeFirst();
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable(response.chunks),
      completion: Future<ChatCompletionResult>.value(response.completion),
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _ParticipantToolStreamRequest {
  const _ParticipantToolStreamRequest({
    required this.messages,
    required this.tools,
    required this.model,
    required this.temperature,
    required this.maxTokens,
  });

  final List<Message> messages;
  final List<Map<String, dynamic>> tools;
  final String? model;
  final double? temperature;
  final int? maxTokens;
}

class _ParticipantToolStreamResponse {
  const _ParticipantToolStreamResponse({
    this.chunks = const <String>[],
    required this.completion,
  });

  final List<String> chunks;
  final ChatCompletionResult completion;
}

class _ToolBatchChatDataSource implements ChatDataSource {
  _ToolBatchChatDataSource({
    required this.initialToolCalls,
    this.initialCompletionContent = '',
    this.initialFinishReason = 'tool_calls',
    this.initialStreamChunks = const [],
    this.followUpToolCalls = const [],
    this.intermediateToolRoleResponseContent = '',
    this.toolRoleResponseContent = '',
    this.finalAnswerChunks = const ['Combined tool summary'],
    this.failFirstToolResultCompletionWithContextLength = false,
    this.failFirstFinalAnswerStreamWithContextLength = false,
    List<ChatCompletionResult> autoReviewResponses = const [],
  }) : autoReviewResponses = Queue<ChatCompletionResult>.from(
         autoReviewResponses,
       );

  final List<ToolCallInfo> initialToolCalls;
  final String initialCompletionContent;
  final String initialFinishReason;
  final List<String> initialStreamChunks;
  final List<ToolCallInfo> followUpToolCalls;
  final String intermediateToolRoleResponseContent;
  final String toolRoleResponseContent;
  final List<String> finalAnswerChunks;
  final bool failFirstToolResultCompletionWithContextLength;
  final bool failFirstFinalAnswerStreamWithContextLength;
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<Message>> initialRequestMessages = [];
  final List<List<Message>> toolResultRequestMessages = [];
  final List<List<Map<String, dynamic>>> initialToolDefinitionBatches = [];
  final List<List<Map<String, dynamic>>> followUpToolDefinitionBatches = [];
  final List<List<Message>> finalAnswerRequestMessages = [];
  final List<List<Message>> autoReviewRequestMessages = [];
  final Queue<ChatCompletionResult> autoReviewResponses;
  List<Message> finalAnswerMessages = const [];
  var _toolLoopResponseCount = 0;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final requestMessages = List<Message>.from(messages);
    finalAnswerRequestMessages.add(requestMessages);
    finalAnswerMessages = requestMessages;
    if (failFirstFinalAnswerStreamWithContextLength &&
        finalAnswerRequestMessages.length == 1) {
      throw StateError(
        'This model has a maximum context length of 8192 tokens',
      );
    }
    yield* Stream<String>.fromIterable(finalAnswerChunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    if ((tools == null || tools.isEmpty) &&
        messages.isNotEmpty &&
        messages.first.id == 'auto_review_policy') {
      autoReviewRequestMessages.add(List<Message>.from(messages));
      if (autoReviewResponses.isNotEmpty) {
        return Future<ChatCompletionResult>.value(
          autoReviewResponses.removeFirst(),
        );
      }
    }
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequestMessages.add(List<Message>.from(messages));
    initialToolDefinitionBatches.add(List<Map<String, dynamic>>.from(tools));
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable(initialStreamChunks),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(
          content: initialCompletionContent,
          toolCalls: initialToolCalls,
          finishReason: initialFinishReason,
        ),
      ),
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
    toolResultRequestMessages.add(List<Message>.from(messages));
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    followUpToolDefinitionBatches.add(
      List<Map<String, dynamic>>.from(tools ?? const []),
    );
    _toolLoopResponseCount += 1;
    if (failFirstToolResultCompletionWithContextLength &&
        _toolLoopResponseCount == 1) {
      throw StateError(
        'This model has a maximum context length of 8192 tokens',
      );
    }
    if (_toolLoopResponseCount == 1 && followUpToolCalls.isNotEmpty) {
      return ChatCompletionResult(
        content: intermediateToolRoleResponseContent,
        toolCalls: followUpToolCalls,
        finishReason: 'tool_calls',
      );
    }
    return ChatCompletionResult(
      content: toolRoleResponseContent,
      finishReason: 'stop',
    );
  }
}

class _FinalAnswerRecoveryChatDataSource
    implements ChatDataSource, FinishReasonAware {
  _FinalAnswerRecoveryChatDataSource({
    required this.initialToolCall,
    required this.firstAnswer,
    required this.firstFinishReason,
    required this.recoveryResult,
    this.pendingActionRecoveryResult,
  });

  final ToolCallInfo initialToolCall;
  final String firstAnswer;
  final String firstFinishReason;
  final ChatCompletionResult recoveryResult;
  final ChatCompletionResult? pendingActionRecoveryResult;
  final List<List<Map<String, dynamic>>> initialToolBatches = [];
  final List<List<Message>> recoveryRequestMessages = [];
  final List<List<Map<String, dynamic>>?> recoveryToolBatches = [];
  final List<double?> recoveryTemperatures = [];
  final List<int?> recoveryMaxTokens = [];
  final List<List<Message>> pendingActionRecoveryRequestMessages = [];
  final List<List<Map<String, dynamic>>> pendingActionRecoveryToolBatches = [];
  var finalAnswerStreamCount = 0;
  var toolResultCompletionCount = 0;
  String? _lastFinishReason;

  @override
  String? get lastFinishReason => _lastFinishReason;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    finalAnswerStreamCount += 1;
    _lastFinishReason = firstFinishReason;
    yield firstAnswer;
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (!messages.any((message) => message.id == 'final_answer_recovery')) {
      return ChatCompletionResult(
        content:
            '{"summary":"","open_loops":[],"profile":'
            '{"persona":[],"preferences":[],"do_not":[]},"memories":[]}',
        finishReason: 'stop',
      );
    }
    recoveryRequestMessages.add(List<Message>.from(messages));
    recoveryToolBatches.add(
      tools == null ? null : List<Map<String, dynamic>>.from(tools),
    );
    recoveryTemperatures.add(temperature);
    recoveryMaxTokens.add(maxTokens);
    _lastFinishReason = recoveryResult.finishReason;
    return recoveryResult;
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialToolBatches.add(
      tools.map((tool) => Map<String, dynamic>.from(tool)).toList(),
    );
    _lastFinishReason = 'tool_calls';
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(
          content: '',
          toolCalls: [initialToolCall],
          finishReason: 'tool_calls',
        ),
      ),
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
    toolResultCompletionCount += 1;
    final isPendingActionRecovery = messages.any(
      (message) =>
          message.id.startsWith('length_truncated_pending_action_recovery_'),
    );
    if (isPendingActionRecovery && pendingActionRecoveryResult != null) {
      pendingActionRecoveryRequestMessages.add(List<Message>.from(messages));
      pendingActionRecoveryToolBatches.add(
        (tools ?? const <Map<String, dynamic>>[])
            .map((tool) => Map<String, dynamic>.from(tool))
            .toList(),
      );
      _lastFinishReason = pendingActionRecoveryResult!.finishReason;
      return pendingActionRecoveryResult!;
    }
    _lastFinishReason = 'stop';
    return ChatCompletionResult(content: '', finishReason: 'stop');
  }
}

class _GoalAutoContinueChatDataSource implements ChatDataSource {
  _GoalAutoContinueChatDataSource({
    required List<List<ToolCallInfo>> toolCallBatches,
    List<List<String>> streamChunkBatches = const [],
    List<List<String>> finalAnswerChunkBatches = const [],
    this.toolCompletionGates = const {},
    List<ChatCompletionResult> autoReviewResponses = const [],
  }) : _toolCallBatches = Queue<List<ToolCallInfo>>.from(toolCallBatches),
       _streamChunkBatches = Queue<List<String>>.from(streamChunkBatches),
       _finalAnswerChunkBatches = Queue<List<String>>.from(
         finalAnswerChunkBatches,
       ),
       autoReviewResponses = Queue<ChatCompletionResult>.from(
         autoReviewResponses,
       );

  final Queue<List<ToolCallInfo>> _toolCallBatches;
  final Queue<List<String>> _streamChunkBatches;
  final Queue<List<String>> _finalAnswerChunkBatches;
  final Map<int, Future<void>> toolCompletionGates;
  final Queue<ChatCompletionResult> autoReviewResponses;
  final List<List<Message>> initialRequestMessages = [];
  final List<List<Map<String, dynamic>>> initialToolDefinitions = [];
  final List<List<Message>> finalAnswerRequestMessages = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<Map<String, dynamic>>> toolResultToolDefinitions = [];
  final List<List<Message>> autoReviewRequestMessages = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    finalAnswerRequestMessages.add(List<Message>.from(messages));
    final chunks = _finalAnswerChunkBatches.isEmpty
        ? const ['No final answer queued.']
        : _finalAnswerChunkBatches.removeFirst();
    yield* Stream<String>.fromIterable(chunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    if ((tools == null || tools.isEmpty) &&
        messages.isNotEmpty &&
        messages.first.id == 'auto_review_policy') {
      autoReviewRequestMessages.add(List<Message>.from(messages));
      if (autoReviewResponses.isNotEmpty) {
        return Future<ChatCompletionResult>.value(
          autoReviewResponses.removeFirst(),
        );
      }
    }
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequestMessages.add(List<Message>.from(messages));
    initialToolDefinitions.add(
      tools.map((tool) => Map<String, dynamic>.from(tool)).toList(),
    );
    final requestNumber = initialRequestMessages.length;
    final toolCalls = _toolCallBatches.isEmpty
        ? const <ToolCallInfo>[]
        : _toolCallBatches.removeFirst();
    final chunks = _streamChunkBatches.isEmpty
        ? const <String>[]
        : _streamChunkBatches.removeFirst();
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable(chunks),
      completion: () async {
        final gate = toolCompletionGates[requestNumber];
        if (gate != null) {
          await gate;
        }
        return ChatCompletionResult(
          content: chunks.join(),
          toolCalls: toolCalls,
          finishReason: toolCalls.isEmpty ? 'stop' : 'tool_calls',
        );
      }(),
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    toolResultToolDefinitions.add(
      (tools ?? const <Map<String, dynamic>>[])
          .map((tool) => Map<String, dynamic>.from(tool))
          .toList(growable: false),
    );
    return ChatCompletionResult(
      content: assistantContent ?? '',
      finishReason: 'stop',
    );
  }
}

List<ChatCompletionResult> _toolLoopResponsesThroughRecoveredRead() {
  return [
    for (var index = 1; index < 12; index += 1)
      ChatCompletionResult(
        content: 'Continue lookup $index',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-command-$index',
            name: 'local_execute_command',
            arguments: {'command': 'probe-$index'},
          ),
        ],
        finishReason: 'tool_calls',
      ),
    ChatCompletionResult(
      content: 'Found the target file; read it now.',
      toolCalls: [
        ToolCallInfo(
          id: 'tool-read-target',
          name: 'read_file',
          arguments: const {'path': '/tmp/session-log.jsonl'},
        ),
      ],
      finishReason: 'tool_calls',
    ),
    ChatCompletionResult(
      content: 'Recovery still requires the declared file read.',
      toolCalls: [
        ToolCallInfo(
          id: 'tool-read-target-recovery',
          name: 'read_file',
          arguments: const {'path': '/tmp/session-log.jsonl'},
        ),
      ],
      finishReason: 'tool_calls',
    ),
    ChatCompletionResult(
      content: 'The target log was inspected.',
      finishReason: 'stop',
    ),
  ];
}

class _QueuedToolLoopChatDataSource implements ChatDataSource {
  _QueuedToolLoopChatDataSource({
    required this.initialToolCalls,
    required List<ChatCompletionResult> toolLoopResponses,
    this.finalAnswerChunks = const ['Recovered final answer'],
    List<List<String>> finalAnswerChunkBatches = const [],
    this.toolLoopResponseGates = const {},
  }) : _toolLoopResponses = Queue<ChatCompletionResult>.from(toolLoopResponses),
       _finalAnswerChunkBatches = Queue<List<String>>.from(
         finalAnswerChunkBatches,
       );

  final List<ToolCallInfo> initialToolCalls;
  final Queue<ChatCompletionResult> _toolLoopResponses;
  final Queue<List<String>> _finalAnswerChunkBatches;
  final Map<int, Future<void>> toolLoopResponseGates;
  final List<String> finalAnswerChunks;
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<Message>> toolResultRequestMessages = [];
  final List<Message> finalAnswerMessages = <Message>[];
  final List<String?> assistantContents = [];
  double? initialToolTemperature;
  final List<double?> toolLoopTemperatures = [];
  final List<double?> finalAnswerTemperatures = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    finalAnswerTemperatures.add(temperature);
    finalAnswerMessages
      ..clear()
      ..addAll(List<Message>.from(messages));
    final chunks = _finalAnswerChunkBatches.isNotEmpty
        ? _finalAnswerChunkBatches.removeFirst()
        : finalAnswerChunks;
    yield* Stream<String>.fromIterable(chunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialToolTemperature = temperature;
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(
          content: '',
          toolCalls: initialToolCalls,
          finishReason: 'tool_calls',
        ),
      ),
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
    toolLoopTemperatures.add(temperature);
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    toolResultRequestMessages.add(List<Message>.from(messages));
    assistantContents.add(assistantContent);
    final gate = toolLoopResponseGates[toolResultBatches.length];
    if (gate != null) {
      await gate;
    }
    return _toolLoopResponses.removeFirst();
  }
}

class _NoToolStreamingWithToolsDataSource implements ChatDataSource {
  _NoToolStreamingWithToolsDataSource({
    required this.streamChunks,
    required this.completionContent,
  });

  final List<String> streamChunks;
  final String completionContent;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable(streamChunks),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(content: completionContent, finishReason: 'stop'),
      ),
    );
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

class _ToolEnabledSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
    );
  }
}

class _ToolEnabledLoggingSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      enableLlmSessionLogs: true,
    );
  }
}

class _ToolEnabledHighTemperatureSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      temperature: 1.7,
      mcpEnabled: true,
      demoMode: false,
    );
  }
}

class _AppleToolEnabledSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      llmProvider: LlmProvider.appleFoundationModels,
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
    );
  }
}

Future<void> _waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout.', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _ToolEnabledNoConfirmSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
    );
  }
}

class _ToolEnabledNoVerificationSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      enableCodingVerificationFeedback: false,
    );
  }
}

class _ToolEnabledRequestOnlyVerificationSettingsNotifier
    extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      codingVerificationTriggerPolicy:
          CodingVerificationTriggerPolicy.onRequestOnly,
    );
  }
}

class _ToolEnabledRemoteDenySettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      localCommandPermissionRules: const [
        LocalCommandPermissionRule(
          id: 'deny-rm',
          action: LocalCommandPermissionAction.deny,
          match: LocalCommandPermissionMatch.prefix,
          pattern: 'rm',
          workingDirectory: '/tmp/project',
        ),
      ],
    );
  }
}

class _ToolEnabledAutoReviewSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.autoReview,
    );
  }
}

class _ToolEnabledChatFullAccessSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      browserToolsEnabled: true,
      chatApprovalMode: ToolApprovalMode.fullAccess,
    );
  }
}

class _ToolEnabledChatAutoReviewSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      browserToolsEnabled: true,
      chatApprovalMode: ToolApprovalMode.autoReview,
    );
  }
}

class _ContentToolSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: false,
      demoMode: false,
      confirmFileMutations: true,
      confirmLocalCommands: true,
    );
  }
}

class _ContentToolNoConfirmSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: false,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
    );
  }
}

class _AppleContentToolSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      llmProvider: LlmProvider.appleFoundationModels,
      assistantMode: AssistantMode.general,
      mcpEnabled: false,
      demoMode: false,
      confirmFileMutations: true,
      confirmLocalCommands: true,
    );
  }
}

class _PlanSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return _baseTestSettings().copyWith(
      assistantMode: AssistantMode.plan,
      mcpEnabled: false,
      demoMode: false,
    );
  }
}

class _FakeMcpToolService extends McpToolService {
  _FakeMcpToolService({
    required this.results,
    this.descriptions = const {},
    Map<String, List<String>> queuedResults = const {},
  }) : queuedResults = queuedResults.map(
         (key, value) => MapEntry(key, Queue<String>.from(value)),
       );

  final Map<String, String> results;
  final Map<String, String> descriptions;
  final Map<String, Queue<String>> queuedResults;
  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedToolArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return ToolDefinitionSearchService.appendSearchToolIfUseful(
      results.keys
          .map(
            (toolName) => {
              'type': 'function',
              'function': {
                'name': toolName,
                'description': descriptions[toolName] ?? 'Fake tool $toolName',
                'parameters': const <String, dynamic>{'type': 'object'},
              },
            },
          )
          .toList(growable: false),
    );
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedToolArguments.add(Map<String, dynamic>.from(arguments));
    if (name == ToolDefinitionSearchService.toolName) {
      return McpToolResult(
        toolName: name,
        result: ToolDefinitionSearchService.searchToolDefinitions(
          definitions: getOpenAiToolDefinitions(),
          query: (arguments['query'] as String?) ?? '',
          maxResults:
              ((arguments['max_results'] as num?)?.toInt() ??
                      ToolDefinitionSearchService.defaultMaxResults)
                  .clamp(1, ToolDefinitionSearchService.maxResultsLimit)
                  .toInt(),
        ),
        isSuccess: true,
      );
    }
    final queued = queuedResults[name];
    if (queued != null && queued.isNotEmpty) {
      return McpToolResult(
        toolName: name,
        result: queued.removeFirst(),
        isSuccess: true,
      );
    }
    return McpToolResult(
      toolName: name,
      result: results[name] ?? '',
      isSuccess: true,
    );
  }
}

class _QueuedMcpToolResultService extends _FakeMcpToolService {
  _QueuedMcpToolResultService(Map<String, List<McpToolResult>> results)
    : _queuedToolResults = results.map(
        (name, values) => MapEntry(name, Queue<McpToolResult>.from(values)),
      ),
      super(results: {for (final name in results.keys) name: ''});

  final Map<String, Queue<McpToolResult>> _queuedToolResults;

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedToolArguments.add(Map<String, dynamic>.from(arguments));
    final queued = _queuedToolResults[name];
    if (queued == null || queued.isEmpty) {
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: 'No queued tool result for $name',
      );
    }
    return queued.removeFirst();
  }
}

class _FakeBackgroundProcessTools extends BackgroundProcessTools {
  _FakeBackgroundProcessTools({
    required this.statusResults,
    this.queuedStatusResults = const {},
  });

  final Map<String, String> statusResults;
  final Map<String, List<String>> queuedStatusResults;
  final List<Map<String, dynamic>> startCalls = [];

  @override
  bool get isSupported => true;

  @override
  Future<String> start({
    required String command,
    required String workingDirectory,
    String? label,
  }) async {
    startCalls.add({
      'command': command,
      'working_directory': workingDirectory,
      if (label != null && label.isNotEmpty) 'label': label,
    });
    return jsonEncode({
      'ok': true,
      'status': 'running',
      'job_id': 'proc_fake',
      'command': command,
      'working_directory': workingDirectory,
      'label': label,
    });
  }

  @override
  Future<String> status({required String jobId, int? tailChars}) async {
    final queued = queuedStatusResults[jobId];
    if (queued != null && queued.isNotEmpty) {
      return queued.removeAt(0);
    }
    return statusResults[jobId] ??
        jsonEncode({
          'ok': false,
          'code': 'job_not_found',
          'job_id': jobId,
          'error': 'No background process job exists for job_id: $jobId',
        });
  }
}

class _WritingFileMcpToolService extends McpToolService {
  _WritingFileMcpToolService(this.root);

  final Directory root;
  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedToolArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'write_file',
          'description': 'Write a UTF-8 text file in the fixture project.',
          'parameters': const <String, dynamic>{
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'content': {'type': 'string'},
              'create_parents': {'type': 'boolean'},
            },
            'required': ['path', 'content'],
          },
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedToolArguments.add(Map<String, dynamic>.from(arguments));
    if (name != 'write_file') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported fixture tool: $name'}),
        isSuccess: false,
        errorMessage: 'Unsupported fixture tool: $name',
      );
    }
    final resolvedPath = FilesystemTools.resolvePath(
      arguments['path'] as String?,
      defaultRoot: root.absolute.path,
    );
    if (resolvedPath == null || resolvedPath.trim().isEmpty) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'path is required'}),
        isSuccess: false,
        errorMessage: 'path is required',
      );
    }
    final targetPath = File(resolvedPath).absolute.path;
    final rootPath = root.absolute.path;
    if (targetPath != rootPath &&
        !targetPath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Path must stay inside the fixture.'}),
        isSuccess: false,
        errorMessage: 'Path must stay inside the fixture.',
      );
    }

    final result = await FilesystemTools.writeFile(
      path: targetPath,
      content: arguments['content'] as String? ?? '',
      createParents: arguments['create_parents'] as bool? ?? true,
    );
    final decoded = _tryDecodeObject(result);
    final error = decoded['error'] as String?;
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: error == null || error.isEmpty,
      errorMessage: error,
    );
  }
}

Map<String, dynamic> _tryDecodeObject(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

class _FakeCodingDiagnosticFeedbackService
    extends CodingDiagnosticFeedbackService {
  _FakeCodingDiagnosticFeedbackService(this.feedback, {this.baseline});

  final ToolResultInfo? feedback;
  final CodingDiagnosticFeedbackBaseline? baseline;
  final List<String> requestedProjectRoots = [];
  final List<List<String>> requestedChangedPaths = [];
  final List<String> baselineProjectRoots = [];
  final List<List<String>> baselineChangedPaths = [];
  final List<CodingDiagnosticFeedbackBaseline?> receivedBaselines = [];

  @override
  Future<CodingDiagnosticFeedbackBaseline?> captureBaseline({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    baselineProjectRoots.add(projectRoot);
    baselineChangedPaths.add(List<String>.from(changedPaths));
    return baseline;
  }

  @override
  Future<ToolResultInfo?> buildFeedbackToolResult({
    required String projectRoot,
    required Iterable<String> changedPaths,
    CodingDiagnosticFeedbackBaseline? baseline,
    DateTime? now,
  }) async {
    requestedProjectRoots.add(projectRoot);
    requestedChangedPaths.add(List<String>.from(changedPaths));
    receivedBaselines.add(baseline);
    return feedback;
  }
}

class _FakeCodingVerificationFeedbackService
    extends CodingVerificationFeedbackService {
  _FakeCodingVerificationFeedbackService(ToolResultInfo? feedback)
    : runs = Queue<CodingVerificationFeedbackRun>.from([
        _runFromFeedback(feedback),
      ]);

  _FakeCodingVerificationFeedbackService.sequence(
    List<ToolResultInfo?> feedbacks,
  ) : runs = Queue<CodingVerificationFeedbackRun>.from(
        feedbacks.map(_runFromFeedback),
      );

  _FakeCodingVerificationFeedbackService.runs(
    List<CodingVerificationFeedbackRun> runs,
  ) : runs = Queue<CodingVerificationFeedbackRun>.from(runs);

  final Queue<CodingVerificationFeedbackRun> runs;
  final List<String> requestedProjectRoots = [];
  final List<List<String>> requestedChangedPaths = [];
  final List<CodingVerificationTrigger> requestedTriggers = [];

  @override
  Future<CodingVerificationFeedbackRun> buildFeedbackRun({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required CodingVerificationTrigger trigger,
    DateTime? now,
  }) async {
    requestedProjectRoots.add(projectRoot);
    requestedChangedPaths.add(List<String>.from(changedPaths));
    requestedTriggers.add(trigger);
    if (runs.isEmpty) {
      return const CodingVerificationFeedbackRun(
        snapshot: null,
        toolResult: null,
      );
    }
    return runs.removeFirst();
  }

  @override
  Future<ToolResultInfo?> buildFeedbackToolResult({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required CodingVerificationTrigger trigger,
    DateTime? now,
  }) async {
    final run = await buildFeedbackRun(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
      trigger: trigger,
      now: now,
    );
    return run.toolResult;
  }

  static CodingVerificationFeedbackRun _runFromFeedback(
    ToolResultInfo? feedback,
  ) {
    return CodingVerificationFeedbackRun(snapshot: null, toolResult: feedback);
  }
}

CodingVerificationSnapshot _codingVerificationSnapshot({
  required String projectRoot,
  required String changedPath,
  required ConversationExecutionValidationStatus validationStatus,
  required int passedCount,
  required int failedCount,
  required int exitCode,
  List<CodingVerificationFailure> failures = const [],
}) {
  final command = CodingVerificationCommand(
    executable: 'flutter',
    arguments: const ['test', '--machine', 'test/main_test.dart'],
    workingDirectory: projectRoot,
  );
  final attempt = CodingVerificationCommandAttempt(
    command: command,
    exitCode: exitCode,
    durationMs: 25,
    timedOut: false,
    validationStatus: validationStatus,
    passedCount: passedCount,
    failedCount: failedCount,
    skippedCount: 0,
  );
  return CodingVerificationSnapshot(
    providerName: CodingVerificationFeedbackService.providerName,
    projectRoot: projectRoot,
    changedPaths: [changedPath],
    trigger: CodingVerificationTrigger.completionClaim,
    validationStatus: validationStatus,
    targetBatches: [
      CodingVerificationTargetBatch(
        packageRoot: projectRoot,
        targets: const ['test/main_test.dart'],
      ),
    ],
    failures: failures,
    telemetry: CodingVerificationTelemetry(durationMs: 25, attempts: [attempt]),
    passedCount: passedCount,
    failedCount: failedCount,
    skippedCount: 0,
    selectedAttempt: attempt,
  );
}

class _SavedValidationToolLoopOutcome {
  const _SavedValidationToolLoopOutcome({
    required this.executedToolNames,
    required this.finalAnswerMessages,
    required this.lastMessageContent,
  });

  final List<String> executedToolNames;
  final List<Message> finalAnswerMessages;
  final String lastMessageContent;
}

Set<String> _toolNamesFromDefinitions(List<Map<String, dynamic>> definitions) {
  return ToolDefinitionSearchService.toolNamesFromDefinitions(definitions);
}

class _SavedValidationWrapperCase {
  const _SavedValidationWrapperCase({
    required this.name,
    required this.wrapperCommand,
    required this.commandResult,
  });

  final String name;
  final String wrapperCommand;
  final String commandResult;
}

Future<_SavedValidationToolLoopOutcome>
_runSavedValidationWrapperFollowUpScenario({
  required String wrapperCommand,
  required String commandResult,
  String validationCommand = 'ls README.md',
}) async {
  final conversation = Conversation(
    id: 'conversation-tool-loop-negative-wrapper',
    title: 'Plan thread',
    messages: const <Message>[],
    createdAt: DateTime(2026, 4, 24, 12),
    updatedAt: DateTime(2026, 4, 24, 12, 5),
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-1',
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: ConversationWorkflowSpec(
      tasks: [
        ConversationWorkflowTask(
          id: 'task-readme',
          title: 'Create README.md with project description',
          targetFiles: const ['README.md'],
          validationCommand: validationCommand,
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    ),
  );
  final toolDataSource = _QueuedToolLoopChatDataSource(
    initialToolCalls: [
      ToolCallInfo(
        id: 'tool-write',
        name: 'write_file',
        arguments: const {
          'path': 'README.md',
          'content': '# Host Health Checker\n',
        },
      ),
    ],
    toolLoopResponses: [
      ChatCompletionResult(
        content: '',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-validate',
            name: 'local_execute_command',
            arguments: {'command': wrapperCommand, 'working_directory': '/tmp'},
          ),
        ],
        finishReason: 'tool_calls',
      ),
      ChatCompletionResult(
        content:
            'The wrapper result did not prove saved validation success, so the follow-up write is still allowed.',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-rewrite-after-untrusted-validation',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host Health Checker\n\nFollow-up rewrite\n',
            },
          ),
        ],
        finishReason: 'tool_calls',
      ),
      ChatCompletionResult(
        content:
            'The current saved task is complete after the follow-up write.',
        finishReason: 'stop',
      ),
    ],
    finalAnswerChunks: const [
      'Final answer after rejected validation wrapper.',
    ],
  );
  final toolService = _FakeMcpToolService(
    results: {
      'write_file': '{"path":"/tmp/README.md","bytes_written":22}',
      'local_execute_command': commandResult,
    },
  );
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  final toolContainer = ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        _ToolEnabledNoConfirmSettingsNotifier.new,
      ),
      conversationsNotifierProvider.overrideWith(
        () => _WorkflowTestConversationsNotifier(conversation),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        _TestCodingProjectsNotifier.new,
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
    ],
  );

  try {
    final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

    await toolNotifier.sendMessage('Create the README first');

    return _SavedValidationToolLoopOutcome(
      executedToolNames: List<String>.from(toolService.executedToolNames),
      finalAnswerMessages: List<Message>.from(
        toolDataSource.finalAnswerMessages,
      ),
      lastMessageContent: toolNotifier.state.messages.last.content,
    );
  } finally {
    toolContainer.dispose();
  }
}

class _SelectiveFakeMcpToolService extends McpToolService {
  _SelectiveFakeMcpToolService({required this.results});

  final Map<String, String> results;
  final List<String> executedToolNames = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return <String>{...results.keys, 'google'}
        .map(
          (toolName) => {
            'type': 'function',
            'function': {
              'name': toolName,
              'description': 'Fake tool $toolName',
              'parameters': const <String, dynamic>{'type': 'object'},
            },
          },
        )
        .toList(growable: false);
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    final result = results[name];
    if (result == null) {
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: 'No matching tool available: $name',
      );
    }
    return McpToolResult(toolName: name, result: result, isSuccess: true);
  }
}

class _PlanningResearchMcpToolService extends McpToolService {
  final List<String> executedToolNames = [];
  final List<({String name, Map<String, dynamic> arguments})> executedCalls =
      [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedCalls.add((
      name: name,
      arguments: Map<String, dynamic>.from(arguments),
    ));

    return switch (name) {
      'list_directory' => McpToolResult(
        toolName: name,
        result:
            '{"path":"/tmp/planning-project","entry_count":2,"entries":["[dir] lib","[file] pubspec.yaml (1 KB)"]}',
        isSuccess: true,
      ),
      'find_files' => _findFilesResult(name, arguments),
      'search_files' => McpToolResult(
        toolName: name,
        result:
            '{"path":"/tmp/planning-project","query":"planning state","matches":["lib/features/chat/presentation/providers/chat_notifier.dart:42: class ChatNotifier extends Notifier<ChatState>"],"match_count":1,"scanned_files":3}',
        isSuccess: true,
      ),
      'read_file' => _readFileResult(name, arguments),
      _ => McpToolResult(toolName: name, result: '{}', isSuccess: true),
    };
  }

  McpToolResult _findFilesResult(String name, Map<String, dynamic> arguments) {
    final pattern = arguments['pattern'] as String? ?? '';
    final matches = switch (pattern) {
      'pubspec.yaml' => ['pubspec.yaml'],
      _ when pattern.contains('planning') => [
        'lib/features/chat/presentation/providers/chat_notifier.dart',
      ],
      _ => const <String>[],
    };
    return McpToolResult(
      toolName: name,
      result:
          '{"path":"/tmp/planning-project","pattern":"$pattern","matches":${_jsonEncodeStringList(matches)},"match_count":${matches.length}}',
      isSuccess: true,
    );
  }

  McpToolResult _readFileResult(String name, Map<String, dynamic> arguments) {
    final path = arguments['path'] as String? ?? '';
    if (path.endsWith('pubspec.yaml')) {
      return McpToolResult(
        toolName: name,
        result:
            '{"path":"$path","content":"name: caverno\\ndescription: Chat client\\ndependencies:\\n  flutter:\\n    sdk: flutter\\n  flutter_riverpod: ^2.0.0\\n","size_bytes":96}',
        isSuccess: true,
      );
    }

    return McpToolResult(
      toolName: name,
      result:
          '{"path":"$path","content":"class ChatNotifier extends Notifier<ChatState> {\\n  Future<void> generatePlanProposal({String languageCode = \\"en\\"}) async {}\\n}\\n","size_bytes":132}',
      isSuccess: true,
    );
  }

  String _jsonEncodeStringList(List<String> values) {
    return '[${values.map((value) => '"$value"').join(',')}]';
  }
}

class _QueuedProposalDataSource implements ChatDataSource {
  _QueuedProposalDataSource(List<ChatCompletionResult> responses)
    : _responses = Queue<ChatCompletionResult>.from(responses);

  final Queue<ChatCompletionResult> _responses;
  final List<List<Message>> requests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requests.add(List<Message>.from(messages));
    return _responses.removeFirst();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
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
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}
