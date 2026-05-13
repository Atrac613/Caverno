import 'dart:convert';
import 'dart:io';

import 'plan_mode_planning_progress.dart';

class PlanModePhaseTrace {
  DateTime? proposalReadyAt;
  DateTime? taskProposalReadyAt;
  DateTime? approvalTappedAt;
  DateTime? firstTaskStartedAt;
  DateTime? firstTaskCompletedAt;
  DateTime? nextTaskStartedAt;
  DateTime? validationStartedAt;
  DateTime? lastTaskProgressAt;
  String? firstTaskTitle;

  Map<String, String?> toJson() {
    return <String, String?>{
      'proposalReadyAt': proposalReadyAt?.toIso8601String(),
      'taskProposalReadyAt': taskProposalReadyAt?.toIso8601String(),
      'approvalTappedAt': approvalTappedAt?.toIso8601String(),
      'firstTaskStartedAt': firstTaskStartedAt?.toIso8601String(),
      'firstTaskCompletedAt': firstTaskCompletedAt?.toIso8601String(),
      'nextTaskStartedAt': nextTaskStartedAt?.toIso8601String(),
      'validationStartedAt': validationStartedAt?.toIso8601String(),
      'lastTaskProgressAt': lastTaskProgressAt?.toIso8601String(),
    };
  }
}

class PlanModeTimeoutBudgets {
  const PlanModeTimeoutBudgets({
    required this.planningTimeout,
    required this.executionTimeout,
    required this.executionStallTimeout,
    required this.overallTimeout,
  });

  final Duration planningTimeout;
  final Duration executionTimeout;
  final Duration executionStallTimeout;
  final Duration? overallTimeout;

  Map<String, int?> toJson() {
    return <String, int?>{
      'planningTimeoutMs': planningTimeout.inMilliseconds,
      'executionTimeoutMs': executionTimeout.inMilliseconds,
      'executionStallTimeoutMs': executionStallTimeout.inMilliseconds,
      'overallTimeoutMs': overallTimeout?.inMilliseconds,
    };
  }
}

String? resolvePlanModeLiveHeartbeatPath({Map<String, String>? environment}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  final value = resolvedEnvironment['CAVERNO_PLAN_MODE_HEARTBEAT_PATH']?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

class PlanModeLiveHeartbeatWriter {
  PlanModeLiveHeartbeatWriter({required this.scenarioName, required this.path});

  final String scenarioName;
  final String? path;

  String? _lastPayload;

  void write({
    required String phase,
    required String subphase,
    required PlanModePhaseTrace phaseTrace,
    required PlanModeTimeoutBudgets budgets,
    String? activeTaskTitle,
    String? workflowSnapshot,
    int? toolResultCount,
    int? fileWriteCount,
    int? messageCount,
    bool? hasPendingApprovals,
    bool? isLoading,
  }) {
    final resolvedPath = path;
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return;
    }

    final payload = <String, Object?>{
      'scenario': scenarioName,
      'updatedAt': DateTime.now().toIso8601String(),
      'phase': phase,
      'subphase': subphase,
      'phaseTimings': phaseTrace.toJson(),
      'budgets': budgets.toJson(),
      'activeTaskTitle': activeTaskTitle,
      'workflowSnapshot': workflowSnapshot,
      'toolResultCount': toolResultCount,
      'fileWriteCount': fileWriteCount,
      'messageCount': messageCount,
      'hasPendingApprovals': hasPendingApprovals,
      'isLoading': isLoading,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    if (_lastPayload == encoded) {
      return;
    }
    _lastPayload = encoded;

    final file = File(resolvedPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$encoded\n');
  }
}

class PlanModePlanningReadyObserver {
  PlanModePlanningReadyObserver({required this.logs});

  final List<String> logs;
  PlanModePhaseTrace? _phaseTrace;
  PlanModeTimeoutBudgets? _budgets;
  PlanModeLiveHeartbeatWriter? _heartbeatWriter;
  String? Function()? _workflowSnapshotResolver;
  int? Function()? _messageCountResolver;

  void configure({
    required PlanModePhaseTrace phaseTrace,
    required PlanModeTimeoutBudgets budgets,
    required PlanModeLiveHeartbeatWriter heartbeatWriter,
    required String? Function() workflowSnapshotResolver,
    required int? Function() messageCountResolver,
  }) {
    _phaseTrace = phaseTrace;
    _budgets = budgets;
    _heartbeatWriter = heartbeatWriter;
    _workflowSnapshotResolver = workflowSnapshotResolver;
    _messageCountResolver = messageCountResolver;
  }

  void clear() {
    _phaseTrace = null;
    _budgets = null;
    _heartbeatWriter = null;
    _workflowSnapshotResolver = null;
    _messageCountResolver = null;
  }

  void observe(String message) {
    final phaseTrace = _phaseTrace;
    final budgets = _budgets;
    final heartbeatWriter = _heartbeatWriter;
    if (phaseTrace == null || budgets == null || heartbeatWriter == null) {
      return;
    }

    final isWorkflowMarker =
        message.contains('[Workflow] Workflow proposal ready') ||
        message.contains('[Workflow] Workflow proposal recovered on retry') ||
        message.contains('[Workflow] Workflow plan artifact draft persisted') ||
        message.contains('[Workflow] Using fallback proposal');
    final isTaskMarker =
        message.contains('[Workflow] Task proposal ready') ||
        message.contains('[Workflow] Task proposal recovered on retry') ||
        message.contains(
          '[Workflow] Task proposal recovered from truncated reasoning fallback',
        ) ||
        message.contains('[Workflow] Task plan artifact draft persisted');
    if (!isWorkflowMarker && !isTaskMarker) {
      return;
    }

    final now = DateTime.now();
    if (isWorkflowMarker) {
      phaseTrace.proposalReadyAt ??= now;
    }
    if (isTaskMarker) {
      phaseTrace.taskProposalReadyAt ??= now;
    }

    final workflowSnapshot = _workflowSnapshotResolver?.call();
    final messageCount = _messageCountResolver?.call();
    final subphase = planningLogsContainReadyDraftState(logs)
        ? 'taskDraftReady'
        : 'workflowDraftReady';
    heartbeatWriter.write(
      phase: 'planning',
      subphase: subphase,
      phaseTrace: phaseTrace,
      budgets: budgets,
      workflowSnapshot: workflowSnapshot,
      messageCount: messageCount,
      hasPendingApprovals: false,
      isLoading: subphase != 'taskDraftReady',
    );
  }
}

Map<String, Object?> readPlanModeLiveHeartbeatSnapshot({String? path}) {
  final resolvedPath = path ?? resolvePlanModeLiveHeartbeatPath();
  if (resolvedPath == null || resolvedPath.isEmpty) {
    return const <String, Object?>{};
  }
  final file = File(resolvedPath);
  if (!file.existsSync()) {
    return const <String, Object?>{};
  }
  final content = file.readAsStringSync().trim();
  if (content.isEmpty) {
    return const <String, Object?>{};
  }
  final decoded = jsonDecode(content);
  if (decoded is Map<String, dynamic>) {
    return Map<String, Object?>.from(decoded);
  }
  return const <String, Object?>{};
}
