import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/mesh_endpoint_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../data/datasources/mesh_secondary_completion_runner.dart';
import '../../data/datasources/session_logging_chat_datasource.dart';
import '../../data/datasources/llama_cpp_slot_transport.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/model_usage_role.dart';
import '../../domain/services/pro_reasoning_candidate_endpoint_resolver.dart';
import '../../domain/services/pro_reasoning_candidate_explorer.dart';
import '../../domain/services/pro_reasoning_investigator.dart';
import '../../domain/services/pro_reasoning_models.dart';
import '../../domain/services/pro_reasoning_prompt_builder.dart';
import '../../domain/services/pro_reasoning_run_coordinator.dart';
import '../../domain/services/pro_reasoning_synthesis_recovery.dart';
import '../../domain/services/secondary_completion_router.dart';
import 'chat_notifier.dart';
import 'conversations_notifier.dart';
import 'hidden_prompt_launch_options.dart';
import 'mcp_tool_provider.dart';
import 'model_usage_providers.dart';

final class ProReasoningRunState {
  const ProReasoningRunState({
    this.isRunning = false,
    this.progress,
    this.error,
  });

  final bool isRunning;
  final ProReasoningProgress? progress;
  final String? error;

  ProReasoningRunState copyWith({
    bool? isRunning,
    ProReasoningProgress? progress,
    String? error,
    bool clearProgress = false,
    bool clearError = false,
  }) => ProReasoningRunState(
    isRunning: isRunning ?? this.isRunning,
    progress: clearProgress ? null : (progress ?? this.progress),
    error: clearError ? null : (error ?? this.error),
  );
}

final proReasoningRunProvider =
    NotifierProvider<ProReasoningRunNotifier, ProReasoningRunState>(
      ProReasoningRunNotifier.new,
    );

class ProReasoningRunNotifier extends Notifier<ProReasoningRunState> {
  final _promptBuilder = const ProReasoningPromptBuilder();
  var _generation = 0;
  final Set<int> _cancelledGenerations = <int>{};
  Completer<void>? _cancelSignal;

  @override
  ProReasoningRunState build() => const ProReasoningRunState();

  Future<bool> start(
    String question, {
    ProReasoningDepth? depth,
    String languageCode = 'en',
  }) async {
    final normalizedQuestion = question.trim();
    if (normalizedQuestion.isEmpty || state.isRunning) return false;
    final conversations = ref.read(conversationsNotifierProvider);
    if (conversations.activeWorkspaceMode != WorkspaceMode.chat) return false;
    final chatState = ref.read(chatNotifierProvider);
    if (chatState.isLoading) return false;

    final conversation =
        conversations.currentConversation ??
        ref
            .read(conversationsNotifierProvider.notifier)
            .ensureCurrentConversation(workspaceMode: WorkspaceMode.chat);
    if (conversation == null) return false;

    final settings = ref.read(settingsNotifierProvider);
    final runDepth = depth ?? settings.proReasoningDepth;
    final generation = ++_generation;
    _cancelledGenerations.remove(generation);
    final cancelSignal = Completer<void>();
    _cancelSignal = cancelSignal;
    state = const ProReasoningRunState(isRunning: true);

    final context = _logContextForConversation(conversation);
    final primaryDataSource = ref.read(chatRemoteDataSourceProvider);
    final meshRunner = _buildMeshRunner(settings);
    final route = _proRoute(settings);
    final toolService = ref.read(mcpToolServiceProvider);
    final endpoints = const ProReasoningCandidateEndpointResolver().resolve(
      settings: settings,
      selectedEndpointOnly:
          settings.proReasoningCandidateRouting ==
          ProReasoningCandidateRouting.selectedOnly,
    );
    final stageTimings = <String, int>{};
    final coordinator = ProReasoningRunCoordinator(
      runFrame: (question, deadline) => _runRouted(
        meshRunner: meshRunner,
        primaryDataSource: primaryDataSource,
        route: route,
        operation: (dataSource, model) => _runFrame(
          question: question,
          dataSource: dataSource,
          model: model,
          deadline: deadline,
          cancelSignal: cancelSignal.future,
          context: context,
          stageTimings: stageTimings,
        ),
      ),
      runInvestigation: (question, frame, maxIterations, deadline) =>
          _runRouted(
            meshRunner: meshRunner,
            primaryDataSource: primaryDataSource,
            route: route,
            operation: (dataSource, model) => _runInvestigation(
              question: question,
              frame: frame,
              maxIterations: maxIterations,
              deadline: deadline,
              dataSource: dataSource,
              model: model,
              toolService: toolService,
              cancelSignal: cancelSignal.future,
              isCancelled: () => _cancelledGenerations.contains(generation),
              context: context,
              stageTimings: stageTimings,
            ),
          ),
      runExplore: (request) => _runExplore(
        request: request,
        endpoints: endpoints,
        context: context,
        cancelSignal: cancelSignal.future,
        stageTimings: stageTimings,
      ),
      runCritique: (question, frame, evidence, candidates, deadline) =>
          _runRouted(
            meshRunner: meshRunner,
            primaryDataSource: primaryDataSource,
            route: route,
            operation: (dataSource, model) => _runCritique(
              question: question,
              frame: frame,
              evidence: evidence,
              candidates: candidates,
              deadline: deadline,
              dataSource: dataSource,
              model: model,
              cancelSignal: cancelSignal.future,
              context: context,
              stageTimings: stageTimings,
            ),
          ),
      runSynthesis: (request) => _runSynthesisWithFallback(
        request: request,
        languageCode: languageCode,
        context: context,
        targetConversationId: conversation.id,
        meshRunner: meshRunner,
        primaryDataSource: primaryDataSource,
        route: route,
        stageTimings: stageTimings,
      ),
    );

    ProReasoningRunResult? result;
    Object? failure;
    try {
      result = await ModelUsageRole.proReasoning.runWith(
        () => coordinator.run(
          question: normalizedQuestion,
          depth: runDepth,
          isCancelled: () => _cancelledGenerations.contains(generation),
          onProgress: (progress) {
            if (generation != _generation || !ref.mounted) return;
            state = state.copyWith(progress: progress, clearError: true);
          },
        ),
      );
      if (result?.synthesisDispatched != true) {
        failure = StateError('Pro Reasoning could not produce a final answer.');
        return false;
      }
      return true;
    } catch (error, stackTrace) {
      failure = error;
      appLog('[ProReasoning] run failed: $error');
      appLog('[ProReasoning] stackTrace: $stackTrace');
      return false;
    } finally {
      await _recordRunSummary(
        context: context,
        depth: runDepth,
        candidateRouting: settings.proReasoningCandidateRouting,
        result: result,
        stageTimings: stageTimings,
        error: failure,
      );
      if (generation == _generation && ref.mounted) {
        state = ProReasoningRunState(error: failure?.toString());
        _cancelSignal = null;
      }
      _cancelledGenerations.remove(generation);
    }
  }

  void cancel() {
    if (!state.isRunning) return;
    if (state.progress?.stage == ProReasoningStage.synthesize &&
        ref.read(chatNotifierProvider).isLoading) {
      ref.read(chatNotifierProvider.notifier).cancelStreaming();
    }
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    _cancelledGenerations.add(_generation);
    final progress = state.progress;
    if (progress != null) {
      state = state.copyWith(
        progress: ProReasoningProgress(
          stage: progress.stage,
          startedAt: progress.startedAt,
          deadline: progress.deadline,
          completedCandidates: progress.completedCandidates,
          requestedCandidates: progress.requestedCandidates,
          endpointLabels: progress.endpointLabels,
          deadlineHit: progress.deadlineHit,
          cancelRequested: true,
        ),
      );
    }
  }

  Future<ProReasoningFrame> _runFrame({
    required String question,
    required ChatDataSource dataSource,
    required String model,
    required DateTime deadline,
    required Future<void> cancelSignal,
    required LlmSessionLogContext context,
    required Map<String, int> stageTimings,
  }) async {
    final prompt = _promptBuilder.buildFramePrompt(question);
    final messages = _messagesFor(prompt, 'frame');
    final startedAt = DateTime.now();
    try {
      final result = await _bounded(
        dataSource.createChatCompletion(
          messages: messages,
          model: model,
          temperature: 0.1,
          maxTokens: 900,
        ),
        deadline: deadline,
        cancelSignal: cancelSignal,
      );
      final finishedAt = DateTime.now();
      stageTimings['frame'] = finishedAt.difference(startedAt).inMilliseconds;
      await _recordCompletion(
        context: context.withRequestLabel('pro_reasoning_frame'),
        operation: 'pro_reasoning_frame',
        messages: messages,
        model: model,
        maxTokens: 900,
        result: result,
        startedAt: startedAt,
        finishedAt: finishedAt,
      );
      return _promptBuilder.parseFrame(result.content, question);
    } catch (error) {
      final finishedAt = DateTime.now();
      stageTimings['frame'] = finishedAt.difference(startedAt).inMilliseconds;
      await _recordStageError(
        context: context,
        operation: 'pro_reasoning_frame',
        messages: messages,
        model: model,
        maxTokens: 900,
        startedAt: startedAt,
        finishedAt: finishedAt,
        error: error,
      );
      rethrow;
    }
  }

  Future<String> _runInvestigation({
    required String question,
    required ProReasoningFrame frame,
    required int maxIterations,
    required DateTime deadline,
    required ChatDataSource dataSource,
    required String model,
    required McpToolService? toolService,
    required Future<void> cancelSignal,
    required bool Function() isCancelled,
    required LlmSessionLogContext context,
    required Map<String, int> stageTimings,
  }) async {
    if (toolService == null) return '';
    final startedAt = DateTime.now();
    try {
      final result = await _bounded(
        ProReasoningInvestigator().investigate(
          dataSource: dataSource,
          model: model,
          question: question,
          frame: frame,
          maxIterations: maxIterations,
          deadline: deadline,
          isCancelled: isCancelled,
          toolDefinitions: toolService.getOpenAiToolDefinitions(),
          runTool: (call) => toolService.executeTool(
            name: call.name,
            arguments: call.arguments,
          ),
          onLlmCall:
              ({
                required messages,
                required tools,
                required result,
                required startedAt,
                required finishedAt,
              }) => _recordCompletion(
                context: context.withRequestLabel('pro_reasoning_investigate'),
                operation: 'pro_reasoning_investigate',
                messages: messages,
                tools: tools,
                model: model,
                maxTokens: 1200,
                result: result,
                startedAt: startedAt,
                finishedAt: finishedAt,
              ),
        ),
        deadline: deadline,
        cancelSignal: cancelSignal,
      );
      stageTimings['investigate'] = DateTime.now()
          .difference(startedAt)
          .inMilliseconds;
      return result;
    } catch (error) {
      final finishedAt = DateTime.now();
      stageTimings['investigate'] = finishedAt
          .difference(startedAt)
          .inMilliseconds;
      await _recordStageError(
        context: context,
        operation: 'pro_reasoning_investigate',
        messages: _messagesFor(
          _promptBuilder.buildInvestigationPrompt(
            question: question,
            frame: frame,
          ),
          'investigate',
        ),
        model: model,
        maxTokens: 1200,
        startedAt: startedAt,
        finishedAt: finishedAt,
        error: error,
      );
      rethrow;
    }
  }

  Future<ProReasoningCritique> _runCritique({
    required String question,
    required ProReasoningFrame frame,
    required String evidence,
    required List<ProReasoningCandidate> candidates,
    required DateTime deadline,
    required ChatDataSource dataSource,
    required String model,
    required Future<void> cancelSignal,
    required LlmSessionLogContext context,
    required Map<String, int> stageTimings,
  }) async {
    final prompt = _promptBuilder.buildCritiquePrompt(
      question: question,
      frame: frame,
      evidence: evidence,
      candidates: candidates,
    );
    final messages = _messagesFor(prompt, 'critique');
    final startedAt = DateTime.now();
    try {
      final result = await _bounded(
        dataSource.createChatCompletion(
          messages: messages,
          model: model,
          temperature: 0.1,
          maxTokens: 1200,
        ),
        deadline: deadline,
        cancelSignal: cancelSignal,
      );
      final finishedAt = DateTime.now();
      stageTimings['critique'] = finishedAt
          .difference(startedAt)
          .inMilliseconds;
      await _recordCompletion(
        context: context.withRequestLabel('pro_reasoning_critique'),
        operation: 'pro_reasoning_critique',
        messages: messages,
        model: model,
        maxTokens: 1200,
        result: result,
        startedAt: startedAt,
        finishedAt: finishedAt,
      );
      return _promptBuilder.parseCritique(result.content, candidates);
    } catch (error) {
      final finishedAt = DateTime.now();
      stageTimings['critique'] = finishedAt
          .difference(startedAt)
          .inMilliseconds;
      await _recordStageError(
        context: context,
        operation: 'pro_reasoning_critique',
        messages: messages,
        model: model,
        maxTokens: 1200,
        startedAt: startedAt,
        finishedAt: finishedAt,
        error: error,
      );
      rethrow;
    }
  }

  Future<ProReasoningExploreResult> _runExplore({
    required ProReasoningExploreRequest request,
    required List<ProReasoningEndpointTarget> endpoints,
    required LlmSessionLogContext context,
    required Future<void> cancelSignal,
    required Map<String, int> stageTimings,
  }) async {
    final startedAt = DateTime.now();
    try {
      return await ProReasoningCandidateExplorer(
        endpoints: endpoints,
        onCandidateCall:
            ({
              required target,
              required candidateIndex,
              required attemptCount,
              required maxTokens,
              required result,
              required error,
              required startedAt,
              required finishedAt,
            }) => _recordCandidate(
              context: context,
              target: target,
              candidateIndex: candidateIndex,
              attemptCount: attemptCount,
              maxTokens: maxTokens,
              result: result,
              startedAt: startedAt,
              finishedAt: finishedAt,
              error: error,
            ),
      ).explore(
        ProReasoningExploreRequest(
          question: request.question,
          frame: request.frame,
          evidence: request.evidence,
          candidateCount: request.candidateCount,
          deadline: request.deadline,
          isCancelled: request.isCancelled,
          cancelSignal: cancelSignal,
          onProgress: request.onProgress,
        ),
      );
    } finally {
      stageTimings['explore'] = DateTime.now()
          .difference(startedAt)
          .inMilliseconds;
    }
  }

  Future<void> _runSynthesisWithFallback({
    required ProReasoningSynthesisRequest request,
    required String languageCode,
    required LlmSessionLogContext context,
    required String targetConversationId,
    required MeshSecondaryCompletionRunner<ChatDataSource> meshRunner,
    required ChatDataSource primaryDataSource,
    required SecondaryCompletionRouteSnapshot route,
    required Map<String, int> stageTimings,
  }) async {
    final startedAt = DateTime.now();
    final initialUserCount = _messageCount(
      targetConversationId,
      MessageRole.user,
    );
    final resolved = meshRunner.resolve(
      primary: primaryDataSource,
      primaryBaseUrl: route.primaryBaseUrl,
      primaryApiKey: route.primaryApiKey,
      endpoints: route.enabledEndpoints,
      endpointId: route.selectedEndpointId,
      model: route.selectedModel,
      fallbackModel: route.fallbackModel,
    );
    late Message answer;
    late String completedModel;
    try {
      answer = await _runSynthesisAttempt(
        request: request,
        languageCode: languageCode,
        targetConversationId: targetConversationId,
        dataSource: resolved.dataSource,
        model: resolved.model,
        includeVisibleQuestion: true,
      );
      completedModel = resolved.model;
      if (!resolved.isPrimary) {
        meshRunner.health.recordSuccess(resolved.endpointId);
      }
    } catch (error) {
      if (resolved.isPrimary) rethrow;
      meshRunner.health.recordFailure(
        resolved.endpointId,
        hard: MeshSecondaryCompletionRunner.isHardEndpointFailure(error),
      );
      answer = await _runSynthesisAttempt(
        request: request,
        languageCode: languageCode,
        targetConversationId: targetConversationId,
        dataSource: primaryDataSource,
        model: route.fallbackModel,
        includeVisibleQuestion:
            _messageCount(targetConversationId, MessageRole.user) ==
            initialUserCount,
      );
      completedModel = route.fallbackModel;
    }
    final finishedAt = DateTime.now();
    stageTimings['synthesize'] = finishedAt
        .difference(startedAt)
        .inMilliseconds;
    await _recordSynthesis(
      context: context,
      request: request,
      answer: answer.content,
      finishReason: answer.responseMetrics?.finishReason,
      model: completedModel,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
  }

  Future<Message> _runSynthesisAttempt({
    required ProReasoningSynthesisRequest request,
    required String languageCode,
    required String targetConversationId,
    required ChatDataSource dataSource,
    required String model,
    required bool includeVisibleQuestion,
  }) async {
    final assistantCount = _messageCount(
      targetConversationId,
      MessageRole.assistant,
    );
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final owner = await chatNotifier.sendHiddenPrompt(
      _promptBuilder.buildSynthesisPrompt(request),
      options: HiddenPromptLaunchOptions(
        visibleUserContent: includeVisibleQuestion ? request.question : null,
        targetConversationId: targetConversationId,
        dataSource: dataSource,
        model: model,
        usageRole: ModelUsageRole.proReasoning,
      ),
      languageCode: languageCode,
      persistAssistantResponse: true,
      allowedToolNames: const <String>{},
    );
    if (owner == null) {
      throw StateError('The Pro Reasoning synthesis could not start.');
    }
    await chatNotifier.waitForTurnCompletion(owner);
    final answers = _conversationMessages(targetConversationId)
        .where((message) => message.role == MessageRole.assistant)
        .skip(assistantCount)
        .where((message) => message.content.trim().isNotEmpty)
        .toList(growable: false);
    if (answers.isEmpty) {
      throw StateError('The Pro Reasoning synthesis returned no answer.');
    }
    final initial = answers.last;
    const recovery = ProReasoningSynthesisRecovery();
    if (!recovery.shouldContinue(initial)) return initial;

    final continuationCount = _messageCount(
      targetConversationId,
      MessageRole.assistant,
    );
    final continuationOwner = await chatNotifier.sendHiddenPrompt(
      ProReasoningSynthesisRecovery.continuationPrompt,
      options: HiddenPromptLaunchOptions(
        targetConversationId: targetConversationId,
        dataSource: dataSource,
        model: model,
        usageRole: ModelUsageRole.proReasoning,
      ),
      languageCode: languageCode,
      persistAssistantResponse: true,
      allowedToolNames: const <String>{},
    );
    if (continuationOwner == null) return initial;
    await chatNotifier.waitForTurnCompletion(continuationOwner);
    final continuations = _conversationMessages(targetConversationId)
        .where((message) => message.role == MessageRole.assistant)
        .skip(continuationCount)
        .where((message) => message.content.trim().isNotEmpty)
        .toList(growable: false);
    if (continuations.isEmpty) return initial;

    final continuation = continuations.last;
    final merged = recovery.merge(initial, continuation);
    final messages = [..._conversationMessages(targetConversationId)];
    final initialIndex = messages.indexWhere(
      (message) => message.id == initial.id,
    );
    final continuationIndex = messages.indexWhere(
      (message) => message.id == continuation.id,
    );
    if (initialIndex < 0 || continuationIndex < 0) return continuation;
    messages[initialIndex] = merged;
    messages.removeAt(continuationIndex);
    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateConversationMessages(targetConversationId, messages);
    return merged;
  }

  MeshSecondaryCompletionRunner<ChatDataSource> _buildMeshRunner(
    AppSettings settings,
  ) => MeshSecondaryCompletionRunner<ChatDataSource>(
    router: ref.read(meshEndpointRouterProvider),
    health: ref.read(endpointHealthTrackerProvider),
    buildEndpointDataSource: (baseUrl, apiKey) => ChatRemoteDataSource(
      baseUrl: baseUrl,
      apiKey: apiKey,
      reasoningEffort: settings.reasoningEffort.apiValue,
      usageSink: ref.read(modelUsageSinkProvider),
    ),
  );

  SecondaryCompletionRouteSnapshot _proRoute(AppSettings settings) =>
      SecondaryCompletionRouteSnapshot(
        provider: settings.llmProvider,
        primaryBaseUrl: settings.baseUrl,
        primaryApiKey: settings.apiKey,
        primaryModel: settings.model,
        enabledEndpoints: settings.enabledLlmEndpoints,
        selectedEndpointId: settings.proReasoningEndpointId,
        selectedModel: settings.effectiveProReasoningModel,
        fallbackModel: settings.model,
        usageRole: ModelUsageRole.proReasoning,
      );

  Future<T> _runRouted<T>({
    required MeshSecondaryCompletionRunner<ChatDataSource> meshRunner,
    required ChatDataSource primaryDataSource,
    required SecondaryCompletionRouteSnapshot route,
    required SecondaryCompletionOperation<ChatDataSource, T> operation,
  }) => SecondaryCompletionRouter<ChatDataSource>(meshRunner: meshRunner).run(
    primaryDataSource: primaryDataSource,
    route: route,
    operation: operation,
  );

  int _messageCount(String conversationId, MessageRole role) =>
      _conversationMessages(
        conversationId,
      ).where((message) => message.role == role).length;

  List<Message> _conversationMessages(String conversationId) =>
      ref
          .read(conversationsNotifierProvider)
          .conversations
          .where((conversation) => conversation.id == conversationId)
          .firstOrNull
          ?.messages ??
      const <Message>[];

  Future<void> _recordSynthesis({
    required LlmSessionLogContext context,
    required ProReasoningSynthesisRequest request,
    required String answer,
    required String? finishReason,
    required String model,
    required DateTime startedAt,
    required DateTime finishedAt,
  }) {
    if (!_sessionLoggingEnabled) return Future<void>.value();
    return ref
        .read(llmSessionLogStoreProvider)
        .record(
          context: context,
          request: LlmSessionLogRequest(
            operation: 'pro_reasoning_synthesis',
            label: 'pro_reasoning_synthesis',
            messages: _messagesFor(
              _promptBuilder.buildSynthesisPrompt(request),
              'synthesis',
            ),
            model: model,
          ),
          startedAt: startedAt,
          finishedAt: finishedAt,
          response: LlmSessionLogResponse(
            content: answer,
            finishReason: finishReason,
          ),
        );
  }

  LlmSessionLogContext _logContextForConversation(Conversation conversation) =>
      LlmSessionLogContext(
        workspaceMode: WorkspaceMode.chat,
        sessionId: conversation.id,
        conversationId: conversation.id,
        sessionTitle: conversation.title,
        phase: 'pro_reasoning',
      );

  bool get _sessionLoggingEnabled {
    final settings = ref.read(settingsNotifierProvider);
    return LlmSessionLogStore.isEnabled(
      settingsEnabled: settings.enableLlmSessionLogs,
    );
  }

  List<Message> _messagesFor(String prompt, String stage) => <Message>[
    Message(
      id: 'pro_reasoning_${stage}_user',
      role: MessageRole.user,
      timestamp: DateTime.now(),
      content: prompt,
    ),
  ];

  Future<T> _bounded<T>(
    Future<T> operation, {
    required DateTime deadline,
    required Future<void> cancelSignal,
  }) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return Future<T>.error(TimeoutException('Pro Reasoning deadline hit.'));
    }
    return Future.any<T>([
      operation.timeout(remaining),
      cancelSignal.then<T>(
        (_) => throw const ProReasoningRunCancelledException(),
      ),
    ]);
  }

  Future<void> _recordCompletion({
    required LlmSessionLogContext context,
    required String operation,
    required List<Message> messages,
    required String model,
    required int maxTokens,
    required ChatCompletionResult result,
    required DateTime startedAt,
    required DateTime finishedAt,
    List<Map<String, dynamic>>? tools,
  }) {
    if (!_sessionLoggingEnabled) return Future<void>.value();
    return ref
        .read(llmSessionLogStoreProvider)
        .record(
          context: context,
          request: LlmSessionLogRequest(
            operation: operation,
            label: operation,
            messages: messages,
            tools: tools,
            model: model,
            maxTokens: maxTokens,
          ),
          startedAt: startedAt,
          finishedAt: finishedAt,
          response: LlmSessionLogResponse(
            content: result.content,
            finishReason: result.finishReason,
            toolCalls: result.toolCalls,
            usage: result.usage,
          ),
        );
  }

  Future<void> _recordCandidate({
    required LlmSessionLogContext context,
    required ProReasoningEndpointTarget target,
    required int candidateIndex,
    required int attemptCount,
    required int maxTokens,
    required SlotChatResult? result,
    required DateTime startedAt,
    required DateTime finishedAt,
    required Object? error,
  }) {
    if (!_sessionLoggingEnabled) return Future<void>.value();
    return ref
        .read(llmSessionLogStoreProvider)
        .record(
          context: context,
          request: LlmSessionLogRequest(
            operation: 'pro_reasoning_candidate',
            label: 'pro_reasoning_candidate_$candidateIndex',
            messages: <Message>[
              Message(
                id: 'pro_reasoning_candidate_${candidateIndex}_metadata',
                role: MessageRole.user,
                timestamp: startedAt,
                content: jsonEncode({
                  'endpointId': target.endpointId,
                  'endpointLabel': target.label,
                  'slotId': result?.idSlot,
                  'attemptCount': attemptCount,
                }),
              ),
            ],
            model: target.model,
            maxTokens: maxTokens,
          ),
          startedAt: startedAt,
          finishedAt: finishedAt,
          response: error == null
              ? LlmSessionLogResponse(
                  content: jsonEncode({
                    'answer': result?.content ?? '',
                    'reasoning': result?.reasoning ?? '',
                    'endpointId': target.endpointId,
                    'endpointLabel': target.label,
                    'slotId': result?.idSlot,
                    'attemptCount': attemptCount,
                  }),
                  finishReason: result?.finishReason,
                  usage: TokenUsage(
                    promptTokens: result?.promptTokens ?? 0,
                    completionTokens: result?.completionTokens ?? 0,
                    totalTokens:
                        (result?.promptTokens ?? 0) +
                        (result?.completionTokens ?? 0),
                  ),
                )
              : null,
          error: error,
        );
  }

  Future<void> _recordStageError({
    required LlmSessionLogContext context,
    required String operation,
    required List<Message> messages,
    required String model,
    required int maxTokens,
    required DateTime startedAt,
    required DateTime finishedAt,
    required Object error,
  }) {
    if (!_sessionLoggingEnabled) return Future<void>.value();
    return ref
        .read(llmSessionLogStoreProvider)
        .record(
          context: context.withRequestLabel(operation),
          request: LlmSessionLogRequest(
            operation: operation,
            label: operation,
            messages: messages,
            model: model,
            maxTokens: maxTokens,
          ),
          startedAt: startedAt,
          finishedAt: finishedAt,
          error: error,
        );
  }

  Future<void> _recordRunSummary({
    required LlmSessionLogContext context,
    required ProReasoningDepth depth,
    required ProReasoningCandidateRouting candidateRouting,
    required ProReasoningRunResult? result,
    required Map<String, int> stageTimings,
    required Object? error,
  }) {
    if (!_sessionLoggingEnabled) return Future<void>.value();
    final now = DateTime.now();
    final summary = <String, dynamic>{
      'depth': depth.name,
      'candidateRouting': candidateRouting.name,
      'stageTimingsMs': stageTimings,
      if (result != null) ...{
        'candidates': result.exploreResult.candidates.length,
        'attemptedCandidates': result.exploreResult.attemptedCandidateCount,
        'endpoints': result.exploreResult.endpointLabels,
        'models': result.exploreResult.candidates
            .map((candidate) => candidate.model)
            .toSet()
            .toList(),
        'slotIds': result.exploreResult.candidates
            .map((candidate) => candidate.slotId)
            .nonNulls
            .toSet()
            .toList(),
        'deadlineHit': result.deadlineHit,
        'cancelRequested': result.cancelRequested,
        'winnerIndex': result.critique.winnerIndex,
        'synthesisDispatched': result.synthesisDispatched,
        'stageErrors': result.stageErrors,
      },
    };
    return ref
        .read(llmSessionLogStoreProvider)
        .record(
          context: context,
          request: LlmSessionLogRequest(
            operation: 'pro_reasoning_summary',
            label: 'pro_reasoning_summary',
            messages: const <Message>[],
          ),
          startedAt: result?.startedAt ?? now,
          finishedAt: result?.finishedAt ?? now,
          response: LlmSessionLogResponse(
            content: jsonEncode(summary),
            finishReason: error == null ? 'completed' : 'failed',
          ),
          error: error,
        );
  }
}

final class ProReasoningRunCancelledException implements Exception {
  const ProReasoningRunCancelledException();
}
