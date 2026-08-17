import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/mesh_endpoint_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/mesh_secondary_completion_runner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/model_usage_role.dart';
import '../../domain/services/composer_shortcut_suggestion_service.dart';
import '../../domain/services/secondary_call_budget.dart';
import '../../domain/services/secondary_completion_router.dart';
import 'chat_notifier.dart';
import 'chat_state.dart';
import 'coding_environment_snapshot_provider.dart';
import 'coding_projects_notifier.dart';
import 'conversations_notifier.dart';
import 'model_usage_providers.dart';

export '../../domain/services/composer_shortcut_suggestion_service.dart'
    show ComposerShortcut, ComposerShortcutKind;

/// Shortcut chips currently offered for one thread.
///
/// Keyed by thread so a background turn's suggestions stay with their own
/// thread instead of appearing under whichever composer is on screen.
class ComposerShortcutsState {
  const ComposerShortcutsState({
    this.byThread = const {},
    this.generatingThreads = const {},
  });

  final Map<String, List<ComposerShortcut>> byThread;
  final Set<String> generatingThreads;

  List<ComposerShortcut> shortcutsFor(String? threadId) =>
      byThread[threadId] ?? const [];

  bool isGeneratingFor(String? threadId) =>
      threadId != null && generatingThreads.contains(threadId);

  ComposerShortcutsState withThread(
    String threadId, {
    required List<ComposerShortcut> shortcuts,
    required bool isGenerating,
  }) {
    final nextByThread = Map<String, List<ComposerShortcut>>.of(byThread);
    if (shortcuts.isEmpty) {
      nextByThread.remove(threadId);
    } else {
      nextByThread[threadId] = shortcuts;
    }
    final nextGenerating = Set<String>.of(generatingThreads);
    if (isGenerating) {
      nextGenerating.add(threadId);
    } else {
      nextGenerating.remove(threadId);
    }
    return ComposerShortcutsState(
      byThread: nextByThread,
      generatingThreads: nextGenerating,
    );
  }
}

/// Drafts the composer's shortcut chips when a turn finishes.
///
/// Lives outside [ChatNotifier] and only observes it: the chips are a composer
/// affordance, not turn state, and the chat loop stays free of them.
class ComposerShortcutsNotifier extends Notifier<ComposerShortcutsState> {
  /// Assistant message the last suggestion ran for, so a rebuild that replays
  /// the same completed turn does not pay for a second completion.
  final Map<String, String> _lastSuggestedMessageIds = {};

  @override
  ComposerShortcutsState build() {
    ref.listen<ChatState>(chatNotifierProvider, (previous, next) {
      _onChatStateChanged(previous, next);
    });
    return const ComposerShortcutsState();
  }

  /// Chips for the thread the user is looking at. The composer asks for these
  /// rather than resolving the thread itself.
  List<ComposerShortcut> get visibleShortcuts =>
      state.shortcutsFor(_visibleThreadId());

  bool get isGeneratingForVisibleThread =>
      state.isGeneratingFor(_visibleThreadId());

  /// Drops the chips for [threadId] (or the visible thread), e.g. once the user
  /// has acted on one.
  void clear([String? threadId]) {
    final target = threadId ?? _visibleThreadId();
    if (target == null) return;
    if (!state.byThread.containsKey(target) &&
        !state.generatingThreads.contains(target)) {
      return;
    }
    state = state.withThread(target, shortcuts: const [], isGenerating: false);
  }

  void _onChatStateChanged(ChatState? previous, ChatState next) {
    final threadId = _visibleThreadId();
    if (threadId == null) return;

    // A new turn invalidates chips drafted for the previous one.
    if (next.isLoading) {
      clear(threadId);
      return;
    }
    final lastMessage = next.messages.isEmpty ? null : next.messages.last;
    if (!ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
      wasLoading: previous?.isLoading ?? false,
      isLoading: next.isLoading,
      lastMessage: lastMessage,
      lastSuggestedMessageId: _lastSuggestedMessageIds[threadId],
    )) {
      return;
    }
    _lastSuggestedMessageIds[threadId] = lastMessage!.id;

    unawaited(
      suggest(threadId: threadId, assistantContent: lastMessage.content),
    );
  }

  /// Runs one suggestion pass for [threadId]. Failures leave the bar empty.
  Future<void> suggest({
    required String threadId,
    required String assistantContent,
    String languageCode = 'en',
  }) async {
    final settings = ref.read(settingsNotifierProvider);
    if (!settings.composerShortcutsEnabled) return;
    final conversation = _conversationFor(threadId);
    if (!ComposerShortcutSuggestionService.hasUsefulContext(
      conversation: conversation,
      assistantContent: assistantContent,
    )) {
      return;
    }

    state = state.withThread(threadId, shortcuts: const [], isGenerating: true);
    try {
      final isCodingWorkspace =
          conversation?.workspaceMode == WorkspaceMode.coding;
      final content = await _complete(
        settings: settings,
        messages: ComposerShortcutSuggestionService.buildMessages(
          conversation: conversation,
          assistantContent: assistantContent,
          languageCode: languageCode,
          repoSnapshot: isCodingWorkspace ? await _repoSnapshot() : null,
          isCodingWorkspace: isCodingWorkspace,
        ),
      );
      if (!ref.mounted) return;
      final shortcuts = ComposerShortcutSuggestionService.parse(content);
      appLog(
        '[ComposerShortcuts] Suggested: '
        '${ComposerShortcutSuggestionService.encodeForDebug(shortcuts)}',
      );
      state = state.withThread(
        threadId,
        shortcuts: shortcuts,
        isGenerating: false,
      );
    } catch (error) {
      appLog('[ComposerShortcuts] Suggestion failed: $error');
      if (!ref.mounted) return;
      state = state.withThread(
        threadId,
        shortcuts: const [],
        isGenerating: false,
      );
    }
  }

  /// Routes the draft like any other secondary completion, so it can be pinned
  /// to its own endpoint and shows up under its usage role.
  Future<String> _complete({
    required AppSettings settings,
    required List<Message> messages,
  }) async {
    final meshRunner = MeshSecondaryCompletionRunner<ChatDataSource>(
      router: ref.read(meshEndpointRouterProvider),
      health: ref.read(endpointHealthTrackerProvider),
      buildEndpointDataSource: (baseUrl, apiKey) => ChatRemoteDataSource(
        baseUrl: baseUrl,
        apiKey: apiKey,
        reasoningEffort: settings.reasoningEffort.apiValue,
        usageSink: ref.read(modelUsageSinkProvider),
      ),
    );
    final result =
        await SecondaryCompletionRouter<ChatDataSource>(
          meshRunner: meshRunner,
        ).run(
          primaryDataSource: ref.read(chatRemoteDataSourceProvider),
          route: SecondaryCompletionRouteSnapshot(
            provider: settings.llmProvider,
            primaryBaseUrl: settings.baseUrl,
            primaryApiKey: settings.apiKey,
            primaryModel: settings.model,
            enabledEndpoints: settings.enabledLlmEndpoints,
            selectedEndpointId: settings.goalSuggestionEndpointId,
            selectedModel: settings.effectiveGoalSuggestionModel,
            fallbackModel: settings.model,
            usageRole: ModelUsageRole.goalSuggestion,
          ),
          operation: (dataSource, model) => dataSource.createChatCompletion(
            messages: messages,
            model: model,
            temperature: 0.1,
            maxTokens: SecondaryCallBudget.resolve(settings.maxTokens, 400),
          ),
        );
    return result.content;
  }

  /// Branch and change volume for the selected coding project, or null when
  /// there is no project, no git, or git did not answer in time.
  Future<ComposerShortcutRepoSnapshot?> _repoSnapshot() async {
    final rootPath = ref
        .read(codingProjectsNotifierProvider)
        .selectedProject
        ?.rootPath
        .trim();
    if (rootPath == null || rootPath.isEmpty) return null;
    try {
      final snapshot = await ref.read(
        codingEnvironmentSnapshotProvider(rootPath).future,
      );
      if (!snapshot.isGitRepository) return null;
      return ComposerShortcutRepoSnapshot(
        branchName: snapshot.displayBranchName,
        changedFileCount: snapshot.changedFileCount,
        insertions: snapshot.insertions,
        deletions: snapshot.deletions,
      );
    } catch (error) {
      appLog('[ComposerShortcuts] Repository snapshot unavailable: $error');
      return null;
    }
  }

  String? _visibleThreadId() {
    final id = ref.read(conversationsNotifierProvider).currentConversation?.id;
    return (id == null || id.isEmpty) ? null : id;
  }

  Conversation? _conversationFor(String threadId) => ref
      .read(conversationsNotifierProvider)
      .conversations
      .where((conversation) => conversation.id == threadId)
      .firstOrNull;
}

final composerShortcutsNotifierProvider =
    NotifierProvider<ComposerShortcutsNotifier, ComposerShortcutsState>(
      ComposerShortcutsNotifier.new,
    );
