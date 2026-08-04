import 'dart:collection';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';

import '../../data/datasources/chat_remote_datasource.dart';
import '../../domain/services/tool_execution_scheduler.dart';

/// Publishes non-terminal runtime events for notifier-owned turn handles.
final class RuntimeTurnEventPublisher {
  /// Takes a read-only view, not the notifier's map.
  ///
  /// It used to take `ChatNotifier._runtimeTurns` itself, so two objects held
  /// one mutable map with no stated ownership rule. Nothing was broken by it --
  /// this class only reads -- but the type is now what says so, and a write
  /// added here would fail to compile instead of racing the turn lifecycle.
  RuntimeTurnEventPublisher(Map<int, CavernoRuntimeTurnHandle> handles)
    : _handlesByGeneration = UnmodifiableMapView(handles);

  final Map<int, CavernoRuntimeTurnHandle> _handlesByGeneration;
  final Map<int, String> _visibleAssistantContentByGeneration = {};

  void clearAssistantContent(int generation) {
    _visibleAssistantContentByGeneration.remove(generation);
  }

  void emitRuntimeAssistantContent(int generation, String content) {
    final visibleContent = ContentParser.parse(content).text;
    final previous = _visibleAssistantContentByGeneration[generation] ?? '';
    if (visibleContent == previous) return;
    _visibleAssistantContentByGeneration[generation] = visibleContent;
    if (!visibleContent.startsWith(previous)) return;
    _handlesByGeneration[generation]?.emitAssistantDelta(
      visibleContent.substring(previous.length),
    );
  }

  void emitRuntimeToolLifecycle({
    required int generation,
    required String toolCallId,
    required String toolName,
    required CavernoRuntimeToolLifecycleState state,
    required int loopIndex,
    String? schedulerClass,
    String? resultStatus,
    String? skipReason,
    int? durationMs,
  }) {
    _handlesByGeneration[generation]?.emitToolLifecycle(
      toolCallId: toolCallId,
      toolName: toolName,
      state: state,
      loopIndex: loopIndex,
      schedulerClass: schedulerClass,
      resultStatus: resultStatus,
      skipReason: skipReason,
      durationMs: durationMs,
    );
  }

  void emitRuntimeApprovalRequired({
    required int generation,
    required String id,
    required String capability,
    required String summary,
    String? target,
    bool rememberAllowed = false,
  }) {
    _handlesByGeneration[generation]?.emitApprovalRequired(
      CavernoRuntimeApprovalRequest(
        id: id,
        capability: capability,
        risk: CavernoRuntimeApprovalRisk.high,
        summary: summary,
        target: target,
        rememberAllowed: rememberAllowed,
      ),
    );
  }

  void emitRuntimeQuestionRequired(
    int generation,
    CavernoRuntimeQuestionRequest request,
  ) {
    _handlesByGeneration[generation]?.emitQuestionRequired(request);
  }

  void emitRuntimeWorkflowTransition({
    required int generation,
    required String stage,
    String? taskId,
    String? taskStatus,
  }) {
    _handlesByGeneration[generation]?.emitWorkflowTransition(
      stage: stage,
      taskId: taskId,
      taskStatus: taskStatus,
    );
  }

  void emitRuntimeUsage(int generation, TokenUsage usage) {
    _handlesByGeneration[generation]?.emitUsage(
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens,
      totalTokens: usage.totalTokens,
    );
  }

  CavernoRuntimeToolLifecycleState runtimeToolLifecycleState(
    ToolExecutionLifecycleState state,
  ) => switch (state) {
    ToolExecutionLifecycleState.queued =>
      CavernoRuntimeToolLifecycleState.queued,
    ToolExecutionLifecycleState.started =>
      CavernoRuntimeToolLifecycleState.started,
    ToolExecutionLifecycleState.completed =>
      CavernoRuntimeToolLifecycleState.completed,
  };
}
