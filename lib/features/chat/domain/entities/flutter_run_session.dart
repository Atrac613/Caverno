import 'flutter_run_device.dart';

enum FlutterRunStatus {
  /// Nothing started, or the last run has been acknowledged.
  idle,

  /// `flutter devices` is running, before the picker can be shown.
  listingDevices,

  /// The process is spawning, up to the first line of output.
  starting,

  /// The app is up and streaming logs.
  running,

  /// A stop was requested and the process has not exited yet.
  stopping,

  /// The process exited, on its own or because it was stopped.
  exited,

  /// The run could not be started, or the toolchain reported a failure.
  failed,
}

enum FlutterRunLogSource { stdout, stderr, harness }

/// One line of run output.
///
/// Carries its source because the panel dims tool chatter and highlights
/// stderr, and because a future reader (the planned issue-list agent) needs to
/// know which lines the toolchain itself considered errors.
class FlutterRunLogLine {
  const FlutterRunLogLine({
    required this.text,
    required this.source,
    required this.at,
  });

  final String text;
  final FlutterRunLogSource source;
  final DateTime at;

  bool get isError => source == FlutterRunLogSource.stderr;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FlutterRunLogLine &&
            text == other.text &&
            source == other.source &&
            at == other.at;
  }

  @override
  int get hashCode => Object.hash(text, source, at);
}

/// The run panel's whole state for one project.
class FlutterRunSessionState {
  const FlutterRunSessionState({
    this.status = FlutterRunStatus.idle,
    this.device,
    this.command = '',
    this.logs = const <FlutterRunLogLine>[],
    this.exitCode,
    this.failure,
  });

  final FlutterRunStatus status;
  final FlutterRunDevice? device;

  /// The command as spawned, shown so the user can reproduce it in a terminal.
  final String command;
  final List<FlutterRunLogLine> logs;
  final int? exitCode;
  final String? failure;

  /// Cap on retained lines. A Flutter app in a hot-reload loop emits output
  /// indefinitely; the panel keeps the recent window rather than the session.
  static const maxRetainedLines = 2000;

  bool get isBusy =>
      status == FlutterRunStatus.listingDevices ||
      status == FlutterRunStatus.starting ||
      status == FlutterRunStatus.stopping;

  bool get isActive =>
      status == FlutterRunStatus.starting ||
      status == FlutterRunStatus.running ||
      status == FlutterRunStatus.stopping;

  bool get hasLogs => logs.isNotEmpty;

  FlutterRunSessionState copyWith({
    FlutterRunStatus? status,
    FlutterRunDevice? device,
    String? command,
    List<FlutterRunLogLine>? logs,
    int? exitCode,
    String? failure,
    bool clearDevice = false,
    bool clearExitCode = false,
    bool clearFailure = false,
  }) {
    return FlutterRunSessionState(
      status: status ?? this.status,
      device: clearDevice ? null : (device ?? this.device),
      command: command ?? this.command,
      logs: logs ?? this.logs,
      exitCode: clearExitCode ? null : (exitCode ?? this.exitCode),
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  /// Appends [line], dropping the oldest lines past [maxRetainedLines].
  FlutterRunSessionState appendLog(FlutterRunLogLine line) {
    final next = [...logs, line];
    return copyWith(
      logs: next.length <= maxRetainedLines
          ? next
          : next.sublist(next.length - maxRetainedLines),
    );
  }
}
