import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/background_process_tool_handler.dart';
import '../../domain/services/local_command_tool_handler.dart';
import 'background_process_tools.dart';
import 'mcp_tool_result_normalizer.dart';

/// Adapts owner-scoped process storage to the extracted handler contracts.
final class BackgroundProcessToolRuntimeAdapter
    implements BackgroundProcessExecutionPort, BackgroundProcessLookupPort {
  const BackgroundProcessToolRuntimeAdapter(this._tools);

  final BackgroundProcessTools _tools;

  @override
  Future<LocalCommandCompletion<BackgroundProcessStartResult>> start(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest operation,
  ) async {
    final execution = await _tools.startExecution(
      owner: owner,
      command: operation.command,
      workingDirectory: operation.workingDirectory,
      label: (operation.arguments['label'] as String?)?.trim(),
    );
    final payload = _decode(execution.result);
    final terminationUnconfirmed =
        payload?['termination_unconfirmed'] == true &&
        _nonEmptyString(payload?['recovery_token']) != null;
    if (!terminationUnconfirmed &&
        (_tools.isOwnerRetired(owner) || _isOwnerExpiredPayload(payload))) {
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: operation.toolCallId,
      );
    }
    final jobId = _nonEmptyString(payload?['job_id']);
    final runtimeIdentity = jobId == null
        ? null
        : _tools.identity(owner: owner, jobId: jobId);
    final identity = runtimeIdentity == null
        ? null
        : (
            externalProcessId: runtimeIdentity.jobId,
            backendProcessId: runtimeIdentity.processId.toString(),
            isRunning: runtimeIdentity.isRunning,
          );
    final result = McpToolResultNormalizer.success(
      toolName: operation.toolName,
      result: execution.result,
      outcome: execution.outcome,
    );
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: operation.toolCallId,
      value: (
        result: result,
        identity: identity,
        startedByRequest:
            payload?['ok'] == true &&
            payload?['duplicate_existing'] != true &&
            identity != null,
      ),
    );
  }

  @override
  Future<LocalCommandCompletion<McpToolResult>> cancel(
    ChatTurnOwner owner,
    String toolCallId,
    BackgroundProcessIdentity identity, {
    bool requireTermination = false,
  }) async {
    final processId = int.tryParse(identity.backendProcessId);
    if (processId == null ||
        identity.externalProcessId.trim().isEmpty ||
        identity.backendProcessId.trim().isEmpty) {
      throw StateError('Background process cancellation identity is invalid.');
    }
    final execution = await _tools.cancelExactExecution(
      owner: owner,
      jobId: identity.externalProcessId,
      processId: processId,
      requireTermination: requireTermination,
    );
    final payload = _decode(execution.result);
    if (requireTermination && payload?['termination_unconfirmed'] == true) {
      throw StateError(
        'Background process exact termination remains unconfirmed.',
      );
    }
    if (_tools.isOwnerRetired(owner)) {
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: toolCallId,
      );
    }
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: toolCallId,
      value: McpToolResultNormalizer.success(
        toolName: 'process_cancel',
        result: execution.result,
        outcome: execution.outcome,
      ),
    );
  }

  @override
  Future<LocalCommandCompletion<BackgroundProcessIdentity?>> lookup(
    ChatTurnOwner owner,
    String toolCallId,
    String externalProcessId,
  ) async {
    if (_tools.isOwnerRetired(owner)) {
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: toolCallId,
      );
    }
    final identity = _tools.identity(owner: owner, jobId: externalProcessId);
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: toolCallId,
      value: identity == null
          ? null
          : (
              externalProcessId: identity.jobId,
              backendProcessId: identity.processId.toString(),
              isRunning: identity.isRunning,
            ),
    );
  }

  Map<String, dynamic>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  bool _isOwnerExpiredPayload(Map<String, dynamic>? payload) {
    return switch (payload?['code']) {
      'background_process_owner_retired' || 'process_start_cancelled' => true,
      _ => false,
    };
  }

  String? _nonEmptyString(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
