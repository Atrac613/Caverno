import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/chat_turn_owner.dart';
import 'background_process_tools_legacy_api.dart';
import 'background_process_types.dart';
import 'first_party_tool_execution_result.dart';
import 'local_shell_tools.dart';

export 'background_process_tools_legacy_api.dart';
export 'background_process_types.dart'
    show BackgroundProcessRuntimeIdentity, BackgroundProcessStarter;

part 'background_process_carry_over.dart';
part 'background_process_job.dart';
part 'background_process_launch_recovery.dart';
part 'background_process_recovery_registry.dart';
part 'background_process_result_codec.dart';

class BackgroundProcessTools with BackgroundProcessToolsLegacyApi {
  BackgroundProcessTools({
    BackgroundProcessStarter? processStarter,
    BackgroundProcessTerminator? processTerminator,
  }) : _processStarter = processStarter ?? startBackgroundProcess,
       _processTerminator =
           processTerminator ?? _defaultBackgroundProcessTerminator;

  static const int _maxBufferChars = 24000;
  static const int _defaultTailChars = 4000;
  static const int _maxTailChars = 12000;
  static const int _minWaitMs = 5000;
  static const int _maxWaitMs = 30000;
  static const String _duplicateNote = 'A matching command is already running.';
  static const String _carriedNote =
      'This command is still running from an earlier turn and has been '
      'adopted.';

  final BackgroundProcessStarter _processStarter;
  final BackgroundProcessTerminator _processTerminator;
  final Map<ChatTurnOwner, _OwnerProcessState> _ownerStates = {};
  final Set<ChatTurnOwner> _retiredOwners = {};
  final Map<String, Set<String>> _resourceFences = {};
  final Map<String, _BackgroundProcessRecoveryRecord> _recoveries = {};
  final Map<String, _ResolvedBackgroundProcessRecovery> _resolvedRecoveries =
      {};

  /// Still-running jobs whose starting turn has ended, by conversation.
  /// See [BackgroundProcessCarryOver] for why they survive it.
  final Map<String, Map<String, _CarriedBackgroundProcessJob>> _carriedJobs =
      {};
  final Random _random = Random.secure();
  int _nextId = 0;
  bool _disposed = false;

  bool get isSupported => LocalShellTools.isDesktopPlatform;

  @override
  Future<FirstPartyToolExecutionResult> startExecution({
    required ChatTurnOwner owner,
    required String command,
    required String workingDirectory,
    String? label,
  }) async {
    if (_disposed) {
      return _error(
        'background_process_tools_disposed',
        message: 'Background process tools have been disposed.',
      );
    }
    if (_retiredOwners.contains(owner)) {
      return _error(
        'background_process_owner_retired',
        message: 'The background process owner has already been cleared.',
      );
    }
    final normalizedCommand = LocalShellTools.normalizeCommand(command);
    if (normalizedCommand.isEmpty) return _error('command_required');

    final directory = Directory(workingDirectory);
    if (!directory.existsSync()) {
      return _error(
        'working_directory_not_found',
        message: 'Working directory does not exist: $workingDirectory',
      );
    }
    final cwd = directory.absolute.path;
    final gitWriteBlockedResult = LocalShellTools.gitWriteCommandBlockedResult(
      command: normalizedCommand,
      workingDirectory: cwd,
    );
    if (gitWriteBlockedResult != null) {
      return FirstPartyToolExecutionResult.payloadOnly(gitWriteBlockedResult);
    }

    final state = _ownerStates.putIfAbsent(owner, _OwnerProcessState.new);
    final running = _runningJobFor(state, normalizedCommand, cwd);
    final carried = running == null
        ? _adoptCarriedRunningJob(owner, normalizedCommand, cwd)
        : null;
    final existing = running ?? carried;
    if (existing != null) {
      return _statusResult(existing, {
        'duplicate_existing': true,
        if (carried != null) 'carried_from_earlier_turn': true,
        'note':
            '${carried != null ? _carriedNote : _duplicateNote} Reuse this '
            'job_id and monitor it instead of starting another process.',
      });
    }

    final resourceKey = _resourceKey(normalizedCommand, directory);
    final startedAt = DateTime.now();
    final id = _newJobId(startedAt);
    final lease = _acquireLaunchLease(
      state: state,
      owner: owner,
      jobId: id,
      command: normalizedCommand,
      workingDirectory: cwd,
      resourceKey: resourceKey,
    );
    if (lease == null) {
      return _error(
        'background_process_resource_fenced',
        command: normalizedCommand,
        workingDirectory: cwd,
        message:
            'A matching process launch is awaiting exact termination '
            'reconciliation.',
      );
    }

    final executable = Platform.isWindows ? 'cmd' : 'sh';
    final arguments = Platform.isWindows
        ? ['/C', normalizedCommand]
        : ['-c', normalizedCommand];
    late final Process process;
    try {
      process = await _processStarter(executable, arguments, cwd);
    } catch (error) {
      final ownerWasActive = _stateIsActive(owner, state);
      _settleLaunchLease(state, lease);
      return ownerWasActive
          ? _error(
              'process_start_failed',
              command: normalizedCommand,
              workingDirectory: cwd,
              message: error.toString(),
            )
          : _retiredStartResult(normalizedCommand, cwd);
    }

    final job = _BackgroundProcessJob(
      id: id,
      command: normalizedCommand,
      workingDirectory: cwd,
      label: label,
      process: process,
      startedAt: startedAt,
      terminator: _processTerminator,
      processGroupId: null,
    );
    final recovery = _registerRecovery(state, lease, job);
    Object? attachmentError;
    try {
      job.attach();
    } catch (error) {
      attachmentError = error;
    }
    if (_stateIsActive(owner, state) && attachmentError == null) {
      _promoteRecovery(state, recovery);
      return _statusResult(job, {
        'status': 'running',
        'note':
            'The process is running in the background. Use process_status, process_tail, or process_wait with this job_id.',
      });
    }

    final acknowledgement = await _attemptRecovery(recovery);
    if (acknowledgement.terminationConfirmed) {
      return attachmentError == null
          ? _retiredStartResult(normalizedCommand, cwd)
          : _error(
              'process_start_failed',
              command: normalizedCommand,
              workingDirectory: cwd,
              message: attachmentError.toString(),
            );
    }
    return _unconfirmedStartResult(recovery, attachmentError);
  }

  @override
  Future<FirstPartyToolExecutionResult> statusExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? tailChars,
  }) async {
    return _withJob(
      owner,
      jobId,
      (job) => _statusResult(
        job,
        const {},
        tailChars: _normalizeTailChars(tailChars),
      ),
    );
  }

  @override
  Future<FirstPartyToolExecutionResult> tailExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? maxChars,
  }) async {
    return _withJob(owner, jobId, (job) {
      final tailChars = _normalizeTailChars(maxChars);
      return _jobResult(job, {
        'ok': true,
        'job_id': job.id,
        'status': job.status,
        'stdout_tail': job.stdout.tail(tailChars),
        'stderr_tail': job.stderr.tail(tailChars),
        'stdout_truncated': job.stdout.truncated,
        'stderr_truncated': job.stderr.truncated,
      });
    });
  }

  @override
  Future<FirstPartyToolExecutionResult> waitExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? waitMs,
  }) async {
    final job = _jobFor(owner, jobId);
    if (job == null) return _notFound(jobId);
    if (job.isRunning) {
      final retiredSignal = _ownerStates[owner]?.retiredSignal.future;
      try {
        await Future.any(<Future<void>>[
          job.done,
          ?retiredSignal,
        ]).timeout(Duration(milliseconds: _normalizeWaitMs(waitMs)));
      } on TimeoutException {
        // Returning the current running status is the expected outcome.
      }
    }
    return identical(_jobFor(owner, jobId), job)
        ? _statusResult(job, const {})
        : _notFound(jobId);
  }

  @override
  Future<FirstPartyToolExecutionResult> cancelExecution({
    required ChatTurnOwner owner,
    required String jobId,
  }) async {
    return _withJob(owner, jobId, (job) {
      job.requestCancel();
      return _statusResult(job, const {'cancel_requested': true});
    });
  }

  BackgroundProcessRuntimeIdentity? identity({
    required ChatTurnOwner owner,
    required String jobId,
  }) {
    final recovery = _recoveryForJob(owner, jobId);
    final job = _jobFor(owner, jobId) ?? recovery?.job;
    return job == null
        ? null
        : (
            jobId: job.id,
            processId: job.process.pid,
            isRunning: recovery != null || job.isRunning,
          );
  }

  @override
  Future<FirstPartyToolExecutionResult> cancelExactExecution({
    required ChatTurnOwner owner,
    required String jobId,
    required int processId,
    bool requireTermination = false,
  }) async {
    final job = _jobFor(owner, jobId);
    if (job == null) {
      final recovery = _recoveryForJob(owner, jobId);
      if (recovery == null) return _notFound(jobId);
      if (recovery.receipt.processId != processId) {
        return _error(
          'background_process_identity_mismatch',
          jobId: jobId,
          message:
              'The background process identity changed before cancellation.',
        );
      }
      final acknowledgement = await reconcileTermination(recovery.receipt);
      return acknowledgement.terminationConfirmed
          ? _statusResult(recovery.job, const {'cancel_requested': true})
          : _terminationUnconfirmedResult(recovery, acknowledgement.error);
    }
    if (job.process.pid != processId) {
      return _error(
        'background_process_identity_mismatch',
        jobId: jobId,
        message: 'The background process identity changed before cancellation.',
      );
    }
    if (job.isRunning) {
      if (requireTermination) {
        final report = await job.terminate();
        if (!report.isConfirmed) {
          final state = _ownerStates[owner]!;
          final recovery = _registerExistingJobRecovery(owner, state, job);
          return _terminationUnconfirmedResult(recovery, report.error);
        }
      } else {
        job.requestCancel();
      }
    }
    return _statusResult(job, const {'cancel_requested': true});
  }

  bool isOwnerRetired(ChatTurnOwner owner) =>
      _disposed || _retiredOwners.contains(owner);

  /// Retires [owner]. A retired turn stays retired, but its still-running jobs
  /// are carried for the conversation rather than killed; see
  /// [BackgroundProcessCarryOver].
  Future<void> clearOwner({required ChatTurnOwner owner}) {
    _retiredOwners.add(owner);
    final state = _ownerStates[owner];
    if (state == null) return Future<void>.value();
    state.markRetired();
    _carryRunningJobs(owner, state);
    return state.retirement ??= _retireState(owner, state);
  }

  /// Terminates every job carried past a turn in [conversationId].
  ///
  /// The exit that `clearOwner` no longer performs. Carried jobs outlive
  /// turns, so something has to end them when the conversation itself does.
  Future<void> clearConversation({required String conversationId}) =>
      _terminateCarriedJobs(conversationId: conversationId);

  /// Job IDs still running from an earlier turn of the owner's conversation.
  ///
  /// Reporting, not adoption: these are what the next reference would adopt.
  List<String> carriedJobIds({required ChatTurnOwner owner}) {
    if (!_canAdopt(owner)) return const <String>[];
    return List<String>.unmodifiable(
      _carriedJobs[owner.conversationId]?.keys ?? const <String>[],
    );
  }

  Future<void> dispose() {
    if (!_disposed) {
      _disposed = true;
      for (final entry in _ownerStates.entries) {
        _retiredOwners.add(entry.key);
        entry.value.markRetired();
        entry.value.retirement ??= _retireState(entry.key, entry.value);
      }
    }
    return Future.wait<void>([
      ..._ownerStates.values
          .map((state) => state.retirement)
          .whereType<Future<void>>(),
      _terminateCarriedJobs(),
    ]);
  }

  FirstPartyToolExecutionResult _withJob(
    ChatTurnOwner owner,
    String jobId,
    FirstPartyToolExecutionResult Function(_BackgroundProcessJob job) found,
  ) {
    final job = _jobFor(owner, jobId);
    return job == null ? _notFound(jobId) : found(job);
  }

  _BackgroundProcessJob? _jobFor(ChatTurnOwner owner, String jobId) {
    final state = _ownerStates[owner];
    final owned = state == null || state.retired ? null : state.jobs[jobId];
    return owned ?? _adoptCarriedJob(owner, jobId);
  }

  _BackgroundProcessJob? _runningJobFor(
    _OwnerProcessState state,
    String command,
    String workingDirectory,
  ) {
    for (final job in state.jobs.values) {
      if (job.isRunning &&
          job.command == command &&
          job.workingDirectory == workingDirectory) {
        return job;
      }
    }
    return null;
  }

  bool _stateIsActive(ChatTurnOwner owner, _OwnerProcessState state) =>
      !_disposed &&
      !_retiredOwners.contains(owner) &&
      !state.retired &&
      identical(_ownerStates[owner], state);
}
