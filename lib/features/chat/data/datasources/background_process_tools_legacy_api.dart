import '../../domain/entities/chat_turn_owner.dart';
import 'first_party_tool_execution_result.dart';

/// Compatibility surface for callers that still consume JSON payloads.
mixin BackgroundProcessToolsLegacyApi {
  Future<FirstPartyToolExecutionResult> startExecution({
    required ChatTurnOwner owner,
    required String command,
    required String workingDirectory,
    String? label,
  });

  Future<FirstPartyToolExecutionResult> statusExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? tailChars,
  });

  Future<FirstPartyToolExecutionResult> tailExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? maxChars,
  });

  Future<FirstPartyToolExecutionResult> waitExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? waitMs,
  });

  Future<FirstPartyToolExecutionResult> cancelExecution({
    required ChatTurnOwner owner,
    required String jobId,
  });

  Future<FirstPartyToolExecutionResult> cancelExactExecution({
    required ChatTurnOwner owner,
    required String jobId,
    required int processId,
    bool requireTermination = false,
  });

  Future<String> start({
    required ChatTurnOwner owner,
    required String command,
    required String workingDirectory,
    String? label,
  }) async => (await startExecution(
    owner: owner,
    command: command,
    workingDirectory: workingDirectory,
    label: label,
  )).result;

  Future<String> status({
    required ChatTurnOwner owner,
    required String jobId,
    int? tailChars,
  }) async => (await statusExecution(
    owner: owner,
    jobId: jobId,
    tailChars: tailChars,
  )).result;

  Future<String> tail({
    required ChatTurnOwner owner,
    required String jobId,
    int? maxChars,
  }) async => (await tailExecution(
    owner: owner,
    jobId: jobId,
    maxChars: maxChars,
  )).result;

  Future<String> wait({
    required ChatTurnOwner owner,
    required String jobId,
    int? waitMs,
  }) async =>
      (await waitExecution(owner: owner, jobId: jobId, waitMs: waitMs)).result;

  Future<String> cancel({
    required ChatTurnOwner owner,
    required String jobId,
  }) async => (await cancelExecution(owner: owner, jobId: jobId)).result;

  Future<String> cancelExact({
    required ChatTurnOwner owner,
    required String jobId,
    required int processId,
    bool requireTermination = false,
  }) async => (await cancelExactExecution(
    owner: owner,
    jobId: jobId,
    processId: processId,
    requireTermination: requireTermination,
  )).result;
}
