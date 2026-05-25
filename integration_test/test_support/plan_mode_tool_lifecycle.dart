import 'dart:convert';

const planModeToolLifecycleLogPattern = '[Tool] Lifecycle';
const planModeMcpToolExecutionLogPattern = '[McpToolService] Executing tool:';

Map<String, Object> buildPlanModeToolLifecycleReport(List<String> logs) {
  final events = logs
      .map(_parseToolLifecycleEvent)
      .whereType<Map<String, Object?>>()
      .toList(growable: false);
  final serviceExecutions = <Map<String, Object?>>[];
  for (var index = 0; index < logs.length; index += 1) {
    final serviceExecution = _parseMcpToolServiceExecution(logs[index], index);
    if (serviceExecution != null) {
      serviceExecutions.add(serviceExecution);
    }
  }
  final states = <String, int>{};
  final resultStatuses = <String, int>{};
  final schedulerClasses = <String, int>{};
  final toolSummariesById = <String, _ToolLifecycleSummary>{};
  final observedToolNames = <String>{};
  var completedCount = 0;
  var skippedCount = 0;
  var failedCount = 0;
  var exceptionCount = 0;
  var maxDurationMs = 0;

  for (final event in events) {
    final state = event['lifecycleState']?.toString();
    if (state != null && state.isNotEmpty) {
      states.update(state, (count) => count + 1, ifAbsent: () => 1);
      if (state == 'completed') {
        completedCount += 1;
      } else if (state == 'skipped') {
        skippedCount += 1;
      }
    }

    final resultStatus = event['resultStatus']?.toString();
    if (resultStatus != null && resultStatus.isNotEmpty) {
      resultStatuses.update(
        resultStatus,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (resultStatus == 'tool_failure') {
        failedCount += 1;
      } else if (resultStatus == 'exception') {
        exceptionCount += 1;
      }
    }

    final schedulerClass = event['schedulerClass']?.toString();
    if (schedulerClass != null && schedulerClass.isNotEmpty) {
      schedulerClasses.update(
        schedulerClass,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final durationMs = _asInt(event['durationMs']);
    if (durationMs != null && durationMs > maxDurationMs) {
      maxDurationMs = durationMs;
    }

    final toolCallId = _toolCallSummaryId(event);
    final summary = toolSummariesById.putIfAbsent(
      toolCallId,
      () => _ToolLifecycleSummary(
        toolCallId: event['toolCallId']?.toString(),
        toolName: event['toolName']?.toString() ?? 'unknown',
      ),
    );
    summary.add(event);
    final toolName = event['toolName']?.toString();
    if (toolName != null && toolName.isNotEmpty) {
      observedToolNames.add(toolName);
    }
  }

  for (final serviceExecution in serviceExecutions) {
    final toolName = serviceExecution['toolName']?.toString();
    if (toolName != null && toolName.isNotEmpty) {
      observedToolNames.add(toolName);
    }
  }

  final tools = toolSummariesById.values
      .map((summary) => summary.toJson())
      .toList(growable: false);
  final incompleteTools = tools
      .where(
        (tool) =>
            tool['lastState'] != 'completed' && tool['lastState'] != 'skipped',
      )
      .toList(growable: false);

  final sortedObservedToolNames = observedToolNames.toList(growable: false)
    ..sort();

  return <String, Object>{
    'detected': events.isNotEmpty || serviceExecutions.isNotEmpty,
    'eventCount': events.length,
    'serviceExecutionCount': serviceExecutions.length,
    'toolCallCount': toolSummariesById.length,
    'completedCount': completedCount,
    'skippedCount': skippedCount,
    'failedCount': failedCount,
    'exceptionCount': exceptionCount,
    'incompleteToolCount': incompleteTools.length,
    'maxDurationMs': maxDurationMs,
    'states': states,
    'resultStatuses': resultStatuses,
    'schedulerClasses': schedulerClasses,
    'observedToolNames': sortedObservedToolNames,
    'tools': tools,
    'incompleteTools': incompleteTools,
    'serviceExecutions': serviceExecutions,
    'events': events,
  };
}

Map<String, Object?>? _parseToolLifecycleEvent(String log) {
  if (!log.contains(planModeToolLifecycleLogPattern)) {
    return null;
  }
  final jsonStart = log.indexOf('{');
  if (jsonStart < 0) {
    return null;
  }
  try {
    final decoded = jsonDecode(log.substring(jsonStart));
    if (decoded is! Map) {
      return null;
    }
    return <String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    };
  } catch (_) {
    return null;
  }
}

Map<String, Object?>? _parseMcpToolServiceExecution(String log, int logIndex) {
  final markerIndex = log.indexOf(planModeMcpToolExecutionLogPattern);
  if (markerIndex < 0) {
    return null;
  }
  final toolName = log
      .substring(markerIndex + planModeMcpToolExecutionLogPattern.length)
      .trim();
  if (toolName.isEmpty) {
    return null;
  }
  return <String, Object?>{'toolName': toolName, 'logIndex': logIndex};
}

String _toolCallSummaryId(Map<String, Object?> event) {
  final explicitId = event['toolCallId']?.toString().trim();
  if (explicitId != null && explicitId.isNotEmpty) {
    return explicitId;
  }
  final toolName = event['toolName']?.toString().trim();
  final loopIndex = event['loopIndex']?.toString().trim();
  return '${toolName == null || toolName.isEmpty ? 'unknown' : toolName}:'
      '${loopIndex == null || loopIndex.isEmpty ? 'unknown' : loopIndex}';
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

class _ToolLifecycleSummary {
  _ToolLifecycleSummary({required this.toolCallId, required this.toolName});

  final String? toolCallId;
  final String toolName;
  final states = <String>[];
  final loopIndexes = <int>{};
  String? schedulerClass;
  String? resultStatus;
  String? skipReason;
  int? durationMs;

  void add(Map<String, Object?> event) {
    final state = event['lifecycleState']?.toString();
    if (state != null && state.isNotEmpty) {
      states.add(state);
    }
    final loopIndex = _asInt(event['loopIndex']);
    if (loopIndex != null) {
      loopIndexes.add(loopIndex);
    }
    schedulerClass = event['schedulerClass']?.toString() ?? schedulerClass;
    resultStatus = event['resultStatus']?.toString() ?? resultStatus;
    skipReason = event['skipReason']?.toString() ?? skipReason;
    durationMs = _asInt(event['durationMs']) ?? durationMs;
  }

  Map<String, Object?> toJson() {
    final sortedLoopIndexes = loopIndexes.toList(growable: false)..sort();
    return <String, Object?>{
      'toolCallId': toolCallId,
      'toolName': toolName,
      'states': states,
      'lastState': states.isEmpty ? null : states.last,
      'loopIndexes': sortedLoopIndexes,
      'schedulerClass': schedulerClass,
      'resultStatus': resultStatus,
      'skipReason': skipReason,
      'durationMs': durationMs,
    };
  }
}
