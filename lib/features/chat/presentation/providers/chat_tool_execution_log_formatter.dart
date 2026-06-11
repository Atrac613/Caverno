import 'dart:convert';

import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_execution_scheduler.dart';

final class ChatToolExecutionLogFormatter {
  const ChatToolExecutionLogFormatter._();

  static String lifecycleLineForEvent(
    ToolExecutionLifecycleEvent event, {
    required int loopIndex,
  }) {
    return lifecycleLine(
      toolCall: event.toolCall,
      lifecycleState: event.state.name,
      loopIndex: loopIndex,
      schedulerMode: event.schedulerMode,
      resultStatus: event.resultStatus,
      durationMs: event.durationMs,
    );
  }

  static String lifecycleLine({
    required ToolCallInfo toolCall,
    required String lifecycleState,
    required int loopIndex,
    ToolExecutionBatchMode? schedulerMode,
    String? resultStatus,
    String? skipReason,
    int? durationMs,
  }) {
    final payload = <String, Object?>{
      'toolCallId': toolCall.id,
      'toolName': toolCall.name,
      'lifecycleState': lifecycleState,
      'loopIndex': loopIndex,
    };
    if (schedulerMode != null) {
      payload['schedulerClass'] = schedulerMode.name;
    }
    if (resultStatus != null) {
      payload['resultStatus'] = resultStatus;
    }
    if (skipReason != null) {
      payload['skipReason'] = skipReason;
    }
    if (durationMs != null) {
      payload['durationMs'] = durationMs;
    }
    return '[Tool] Lifecycle ${jsonEncode(payload)}';
  }

  static String schedulerBatchLine(
    ToolExecutionBatchTelemetry telemetry, {
    bool finalInspection = false,
  }) {
    final batchLabel = finalInspection ? 'final inspection batch' : 'batch';
    return '[Tool] Scheduler ${telemetry.mode.name} $batchLabel '
        '(size=${telemetry.batchSize}, tools=${telemetry.toolNames.join(', ')})'
        '${telemetry.note == null ? '' : ' • ${telemetry.note}'}';
  }
}
