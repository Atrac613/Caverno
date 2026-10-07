import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_execution_scheduler.dart';
import 'chat_tool_execution_log_formatter.dart';
import 'runtime_turn_event_publisher.dart';

/// Reports lifecycle events through explicit registry and tracking ports.
final class ToolLifecycleReporter {
  const ToolLifecycleReporter({
    required RuntimeTurnEventPublisher events,
    required void Function(int, String, String) track,
  }) : _runtimeEvents = events,
       _trackTool = track;
  final RuntimeTurnEventPublisher _runtimeEvents;
  final void Function(int, String, String) _trackTool;
  void scheduled(
    ToolExecutionLifecycleEvent event, {
    required int generation,
    required int loopIndex,
  }) {
    _trackTool(generation, event.toolCall.name, event.state.name);
    _runtimeEvents.emitRuntimeToolLifecycle(
      generation: generation,
      toolCallId: event.toolCall.id,
      toolName: event.toolCall.name,
      state: _runtimeEvents.runtimeToolLifecycleState(event.state),
      loopIndex: loopIndex,
      schedulerClass: event.schedulerMode.name,
      resultStatus: event.resultStatus,
      durationMs: event.durationMs,
    );
    appLog(
      ChatToolExecutionLogFormatter.lifecycleLineForEvent(
        event,
        loopIndex: loopIndex,
      ),
    );
  }

  void explicit({
    required int generation,
    required ToolCallInfo toolCall,
    required String lifecycleState,
    required int loopIndex,
    ToolExecutionBatchMode? schedulerMode,
    String? resultStatus,
    String? skipReason,
    int? durationMs,
  }) {
    final runtimeState = switch (lifecycleState) {
      'queued' => CavernoRuntimeToolLifecycleState.queued,
      'started' => CavernoRuntimeToolLifecycleState.started,
      _ => CavernoRuntimeToolLifecycleState.completed,
    };
    _trackTool(generation, toolCall.name, lifecycleState);
    _runtimeEvents.emitRuntimeToolLifecycle(
      generation: generation,
      toolCallId: toolCall.id,
      toolName: toolCall.name,
      state: runtimeState,
      loopIndex: loopIndex,
      schedulerClass: schedulerMode?.name,
      resultStatus: resultStatus,
      skipReason: skipReason,
      durationMs: durationMs,
    );
    appLog(
      ChatToolExecutionLogFormatter.lifecycleLine(
        toolCall: toolCall,
        lifecycleState: lifecycleState,
        loopIndex: loopIndex,
        schedulerMode: schedulerMode,
        resultStatus: resultStatus,
        skipReason: skipReason,
        durationMs: durationMs,
      ),
    );
  }
}
