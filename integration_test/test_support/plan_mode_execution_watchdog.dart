class PlanModeExecutionWatchdog {
  PlanModeExecutionWatchdog({required this.stallTimeout});

  final Duration stallTimeout;

  String? _lastSnapshot;
  DateTime? _lastProgressAt;

  Duration? recordSnapshot(String snapshot, DateTime now) {
    if (_lastSnapshot != snapshot) {
      _lastSnapshot = snapshot;
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
      return stalledFor;
    }
    return null;
  }
}
