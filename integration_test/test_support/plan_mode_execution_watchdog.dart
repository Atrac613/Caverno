class PlanModeExecutionHeartbeat {
  const PlanModeExecutionHeartbeat({
    required this.activeTaskTitle,
    required this.workflowSnapshot,
    required this.toolResultCount,
    required this.fileWriteCount,
    required this.hasPendingApprovals,
    required this.isLoading,
  });

  final String? activeTaskTitle;
  final String workflowSnapshot;
  final int toolResultCount;
  final int fileWriteCount;
  final bool hasPendingApprovals;
  final bool isLoading;

  String get progressKey {
    return <Object?>[
      activeTaskTitle,
      workflowSnapshot,
      toolResultCount,
      fileWriteCount,
      hasPendingApprovals,
      isLoading,
    ].join('|');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'activeTaskTitle': activeTaskTitle,
      'workflowSnapshot': workflowSnapshot,
      'toolResultCount': toolResultCount,
      'fileWriteCount': fileWriteCount,
      'hasPendingApprovals': hasPendingApprovals,
      'isLoading': isLoading,
    };
  }
}

class PlanModeExecutionStallSample {
  const PlanModeExecutionStallSample({
    required this.stalledFor,
    required this.heartbeat,
  });

  final Duration stalledFor;
  final PlanModeExecutionHeartbeat heartbeat;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'stalledForMs': stalledFor.inMilliseconds,
      'heartbeat': heartbeat.toJson(),
    };
  }
}

class PlanModeExecutionWatchdog {
  PlanModeExecutionWatchdog({required this.stallTimeout});

  final Duration stallTimeout;

  String? _lastProgressKey;
  DateTime? _lastProgressAt;

  PlanModeExecutionStallSample? recordHeartbeat(
    PlanModeExecutionHeartbeat heartbeat,
    DateTime now,
  ) {
    if (_lastProgressKey != heartbeat.progressKey) {
      _lastProgressKey = heartbeat.progressKey;
      _lastProgressAt = now;
      return null;
    }
    final lastProgressAt = _lastProgressAt;
    if (lastProgressAt == null) {
      _lastProgressAt = now;
      return null;
    }
    final stalledFor = now.difference(lastProgressAt);
    if (stalledFor >= stallTimeout) {
      return PlanModeExecutionStallSample(
        stalledFor: stalledFor,
        heartbeat: heartbeat,
      );
    }
    return null;
  }
}
