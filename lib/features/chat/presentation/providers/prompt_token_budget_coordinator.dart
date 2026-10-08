import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/repositories/context_window_observation_store.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_compaction_artifact.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/conversation_compaction_service.dart';
import '../../domain/services/model_routing/reported_context_limit.dart';
import '../../domain/services/tool_results/tool_result_prompt_builder.dart';
import 'prompt_token_calibration_registry.dart';

/// Decides how much conversation history a prompt may carry.
///
/// Two inputs the compaction service cannot reach on its own meet here: the
/// active model's usable context window, and what the endpoint has actually
/// charged this thread for prompts of a known estimated size.
final class PromptTokenBudgetCoordinator {
  final PromptTokenCalibrationRegistry _calibrations =
      PromptTokenCalibrationRegistry();
  final Map<String, String> _routeKeys = <String, String>{};
  final Map<String, int?> _routeWindows = <String, int?>{};
  final Set<String> _pressured = <String>{};
  ContextWindowObservationStore? _observations;

  /// The window the fixed tool-result budgets were tuned for.
  static const int referenceWindowTokens = 65536;

  /// Cost ceiling: tool results never scale past a prompt of this size, even
  /// on a model with a million-token window.
  static const int costCapTokens = 200000;

  /// Starts recording what requests prove about each route's context window.
  void attach(Ref ref) =>
      observeWith(ref.read(contextWindowObservationStoreProvider));

  void observeWith(ContextWindowObservationStore? store) =>
      _observations = store;

  /// [route] is the endpoint-and-model key and usable window of the model
  /// this turn is routed to. A review turn on another endpoint was budgeted
  /// against the primary model's window, whatever the reviewing model could
  /// hold. When the route window is unknown the primary's stands in, as it
  /// always did, so an unknown route never budgets below today's allowance.
  PromptTokenBudget budgetFor(
    AppSettings settings,
    String? conversationId, {
    ({String key, int? window})? route,
  }) {
    if (route != null && conversationId != null) {
      _routeKeys[conversationId] = route.key;
      _routeWindows[conversationId] = route.window;
    }
    final routeWindow = route?.window ?? 0;
    return PromptTokenBudget._(
      budgetTokens: ConversationCompactionService.resolvePromptTokenBudget(
        usableContextTokens: routeWindow > 0
            ? routeWindow
            : settings.effectiveModelCapabilityProfile?.usableContextTokens ??
                  0,
        maxResponseTokens: settings.maxTokens,
      ),
      calibration: _calibrations.forConversation(conversationId),
    );
  }

  /// Records what was estimated for the prompt about to be sent.
  void recordEstimate(ChatTurnOwner owner, List<Message> promptMessages) {
    _calibrations.recordEstimate(
      owner: owner,
      estimatedPromptTokens: ConversationCompactionService.estimatePromptTokens(
        promptMessages
            .where((message) => !message.isStreaming)
            .toList(growable: false),
      ),
    );
  }

  /// Completes that pair with the prompt size the endpoint reported, which
  /// also proves the route's window holds at least that many tokens.
  void recordMeasurement(ChatTurnOwner owner, ChatCompletionResult result) {
    _calibrations.recordMeasurement(
      owner: owner,
      measuredPromptTokens: result.usage.promptTokens,
    );
    final key = _routeKeys[owner.conversationId];
    final pressured = _pressured.remove(owner.conversationId);
    if (key != null && result.usage.promptTokens > 0) {
      _observations?.accept(
        key,
        result.usage.promptTokens,
        pressured: pressured,
      );
    }
  }

  /// How far this conversation's route may widen the normal tool-result
  /// budget: a known window relative to [referenceWindowTokens], otherwise the
  /// learned scale, never past a learned ceiling or [costCapTokens].
  double toolResultScale(String? conversationId) {
    final key = conversationId == null ? null : _routeKeys[conversationId];
    final observed = key == null ? null : _observations?.read(key);
    final window = conversationId == null
        ? null
        : _routeWindows[conversationId];
    var scale = window != null && window > 0
        ? window / referenceWindowTokens
        : observed?.budgetScale ?? 1;
    final ceiling = observed?.ceilingTokens;
    if (ceiling != null) {
      scale = math.min(scale, ceiling / referenceWindowTokens);
    }
    return scale.clamp(1.0, costCapTokens / referenceWindowTokens);
  }

  /// Budgets [results] for [owner]'s prompt at its route's scale, noting
  /// whether the budget had to shorten anything so a fitting request can
  /// earn the route more room.
  List<ToolResultInfo> budgetToolResults(
    ChatTurnOwner? owner,
    List<ToolResultInfo> results, {
    required ToolResultPromptBudgetMode mode,
    required Set<String> protectedPaths,
    required bool summaryFirst,
  }) {
    final budgeted = ToolResultPromptBuilder.budgetToolResults(
      results,
      mode: mode,
      protectedPaths: protectedPaths,
      summaryFirst: summaryFirst,
      scale: toolResultScale(owner?.conversationId),
    );
    if (owner != null &&
        mode == ToolResultPromptBudgetMode.normal &&
        budgeted.any(
          (result) => result.result.contains(
            ToolResultPromptBuilder.promptBudgetReductionMarker,
          ),
        )) {
      _pressured.add(owner.conversationId);
    }
    return budgeted;
  }

  /// Whether [error] is a context-length rejection; when it is, records the
  /// rejected prompt size and any limit the endpoint named as the route's
  /// upper bound.
  bool recordLengthFailure(ChatTurnOwner? owner, Object error) {
    final message = error.toString();
    if (!ConversationCompactionService.isContextLengthError(message)) {
      return false;
    }
    final key = owner == null ? null : _routeKeys[owner.conversationId];
    final estimate = owner == null
        ? null
        : _calibrations.pendingEstimate(owner);
    if (key != null) {
      _observations?.reject(
        key,
        promptTokens: estimate == null
            ? null
            : estimate +
                  _calibrations
                      .forConversation(owner!.conversationId)
                      .uncountedTokens,
        reportedLimit: reportedContextLimit(message),
      );
    }
    return true;
  }

  void clearConversation(String conversationId) =>
      _calibrations.clearConversation(conversationId);
}

/// One thread's prompt allowance, and the measurement it was derived from.
final class PromptTokenBudget {
  const PromptTokenBudget._({
    required this.budgetTokens,
    required this.calibration,
  });

  final int budgetTokens;
  final PromptTokenCalibration calibration;

  ConversationTokenPressure assess(List<Message> messages) =>
      ConversationCompactionService.assessTokenPressure(
        messages: messages,
        promptTokenBudget: budgetTokens,
        calibration: calibration,
      );

  /// The summary to stand in for omitted turns, preferring a freshly built one
  /// and falling back to whatever the conversation already carries.
  ConversationCompactionArtifact? resolveArtifact({
    required Conversation? conversation,
    required List<Message> messages,
    bool forceCompaction = false,
  }) {
    final freshArtifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      planDocument: conversation?.displayPlanDocument(
        isPlanning: conversation.isPlanningSession,
      ),
      now: conversation?.effectiveCompactionArtifact.updatedAt,
      force: forceCompaction,
      promptTokenBudget: budgetTokens,
      calibration: calibration,
    );
    if (freshArtifact != null) {
      return freshArtifact;
    }
    final persistedArtifact = conversation?.compactionArtifact;
    if (persistedArtifact?.hasContent ?? false) {
      return persistedArtifact;
    }
    return null;
  }
}
