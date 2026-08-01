// ChatNotifier decomposition collaborator: create-routine-tool-handler

import 'dart:convert';

import '../../../routines/domain/entities/routine.dart';
import '../../../routines/domain/services/routine_schedule_service.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'create_routine_operation_identity.dart';

export 'create_routine_operation_identity.dart';

final class CreateRoutineToolRequest {
  CreateRoutineToolRequest({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required Map<String, dynamic> arguments,
  }) : identity = CreateRoutineOperationIdentity(
         owner: owner,
         toolCallId: toolCallId,
         toolName: toolName,
       ),
       arguments = freezeCreateRoutineArguments(arguments);

  final ChatTurnOwner owner;
  final String toolCallId, toolName;
  final CreateRoutineOperationIdentity identity;
  final Map<String, dynamic> arguments;

  String get name => (arguments['name'] as String?)?.trim() ?? '';
  String get prompt => (arguments['prompt'] as String?)?.trim() ?? '';
  String? get reason => (arguments['reason'] as String?)?.trim();
}

final class RoutineStoreCreateRequest {
  const RoutineStoreCreateRequest({
    required this.name,
    required this.prompt,
    required this.intervalValue,
    required this.intervalUnit,
    required this.scheduleMode,
    required this.timeOfDayMinutes,
    required this.enabled,
    required this.notifyOnCompletion,
    required this.toolsEnabled,
    required this.completionAction,
    required this.googleChatRule,
    required this.workspaceDirectory,
    required this.allowWorkspaceWrites,
  });

  final String name, prompt, workspaceDirectory;
  final int intervalValue;
  final RoutineIntervalUnit intervalUnit;
  final RoutineScheduleMode scheduleMode;
  final int timeOfDayMinutes;
  final bool enabled, notifyOnCompletion, toolsEnabled, allowWorkspaceWrites;
  final RoutineCompletionAction completionAction;
  final RoutineGoogleChatRule googleChatRule;
}

abstract interface class RoutineStorePort {
  Future<RoutineStoreWriteResult> create(
    CreateRoutineOperationIdentity identity,
    RoutineStoreCreateRequest request,
  );

  Future<RoutineStoreCompensationResult> compensate(
    CreateRoutineOperationIdentity identity,
    RoutineStoreWriteResult committedWrite,
  );
}

final class RoutineCreationApprovalRequest {
  const RoutineCreationApprovalRequest({
    required this.toolRequest,
    required this.operation,
    required this.path,
    required this.preview,
    required this.reason,
  });

  final CreateRoutineToolRequest toolRequest;
  final String operation, path, preview;
  final String? reason;
}

final class RoutineCreationApprovalDecision {
  const RoutineCreationApprovalDecision({
    required this.identity,
    required this.approved,
  });

  final CreateRoutineOperationIdentity identity;
  final bool approved;

  ChatTurnOwner get owner => identity.owner;
}

final class RoutineCreationOwnerState {
  const RoutineCreationOwnerState.current({required this.identity})
    : expiredResult = null;

  const RoutineCreationOwnerState.expired({
    required this.identity,
    required McpToolResult result,
  }) : expiredResult = result;

  final CreateRoutineOperationIdentity identity;
  final McpToolResult? expiredResult;

  ChatTurnOwner get owner => identity.owner;
}

abstract interface class RoutineCreationApprovalPort {
  Future<RoutineCreationApprovalDecision> requestApproval(
    CreateRoutineOperationIdentity identity,
    RoutineCreationApprovalRequest request,
  );

  RoutineCreationOwnerState ownerState(
    CreateRoutineOperationIdentity identity,
    CreateRoutineToolRequest request,
  );
}

final class CreateRoutineToolHandler {
  const CreateRoutineToolHandler({
    required RoutineStorePort storePort,
    required RoutineCreationApprovalPort approvalPort,
  }) : _storePort = storePort,
       _approvalPort = approvalPort;

  final RoutineStorePort _storePort;
  final RoutineCreationApprovalPort _approvalPort;

  Future<McpToolResult> handle(CreateRoutineToolRequest request) async {
    final identity = request.identity;
    final name = request.name;
    final prompt = request.prompt;
    final reason = request.reason;
    if (name.isEmpty) {
      return _failure(request.toolName, 'name is required');
    }
    if (prompt.isEmpty) {
      return _failure(request.toolName, 'prompt is required');
    }

    final arguments = request.arguments;
    final scheduleMode = _parseScheduleMode(arguments['schedule_mode']);
    final intervalValue = RoutineScheduleService.normalizeIntervalValue(
      (arguments['interval_value'] as num?)?.toInt() ?? 1,
    );
    final intervalUnit = _parseIntervalUnit(arguments['interval_unit']);
    final timeOfDayMinutes = RoutineScheduleService.normalizeTimeOfDayMinutes(
      _parseTimeOfDayMinutes(arguments['time_of_day']),
    );
    final toolsEnabled = (arguments['tools_enabled'] as bool?) ?? false;
    final notifyOnCompletion =
        (arguments['notify_on_completion'] as bool?) ?? true;
    final completionAction = _parseCompletionAction(
      arguments['completion_action'],
    );
    final googleChatRule = _parseGoogleChatRule(arguments['google_chat_rule']);
    final workspaceDirectory =
        (arguments['workspace_directory'] as String?)?.trim() ?? '';
    final allowWorkspaceWrites =
        (arguments['allow_workspace_writes'] as bool?) ?? false;
    final scheduleSummary = _scheduleSummary(
      scheduleMode: scheduleMode,
      intervalValue: intervalValue,
      intervalUnit: intervalUnit,
      timeOfDayMinutes: timeOfDayMinutes,
    );
    final preview = _buildPreview(
      name: name,
      prompt: prompt,
      scheduleSummary: scheduleSummary,
      toolsEnabled: toolsEnabled,
      notifyOnCompletion: notifyOnCompletion,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      workspaceDirectory: workspaceDirectory,
      allowWorkspaceWrites: allowWorkspaceWrites,
    );

    final decision = await _approvalPort.requestApproval(
      identity,
      RoutineCreationApprovalRequest(
        toolRequest: request,
        operation: 'Create Routine',
        path: name,
        preview: preview,
        reason: reason,
      ),
    );
    _requireIdentity(decision.identity, identity, 'Routine creation approval');
    final ownerState = _approvalPort.ownerState(identity, request);
    _requireIdentity(
      ownerState.identity,
      identity,
      'Routine creation owner state',
    );
    if (ownerState.expiredResult case final expired?) {
      return expired;
    }
    if (!decision.approved) {
      return _failure(request.toolName, 'User denied creating the routine');
    }

    final createRequest = RoutineStoreCreateRequest(
      name: name,
      prompt: prompt,
      intervalValue: intervalValue,
      intervalUnit: intervalUnit,
      scheduleMode: scheduleMode,
      timeOfDayMinutes: timeOfDayMinutes,
      enabled: true,
      notifyOnCompletion: notifyOnCompletion,
      toolsEnabled: toolsEnabled,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      workspaceDirectory: workspaceDirectory,
      allowWorkspaceWrites: allowWorkspaceWrites,
    );
    try {
      final writeResult = await _storePort.create(identity, createRequest);
      if (!writeResult.identity.belongsTo(identity)) {
        return _uncertain(
          request,
          'the routine store returned a completion for another tool call',
        );
      }
      final compensationToken = writeResult.compensationToken;
      if (writeResult.didCommit &&
          (compensationToken == null ||
              !compensationToken.belongsTo(identity))) {
        return _uncertain(
          request,
          'the committed write lacked an exact compensation token',
        );
      }
      late final RoutineCreationOwnerState ownerStateAfterWrite;
      try {
        ownerStateAfterWrite = _approvalPort.ownerState(identity, request);
      } catch (error) {
        return await _resolveInvalidatedWrite(
          request: request,
          writeResult: writeResult,
          invalidatedResult: _failure(
            request.toolName,
            'Routine creation owner state could not be verified after '
            'persistence: $error',
          ),
        );
      }
      if (!ownerStateAfterWrite.identity.belongsTo(identity)) {
        return await _resolveInvalidatedWrite(
          request: request,
          writeResult: writeResult,
          invalidatedResult: _failure(
            request.toolName,
            'Routine creation post-write identity mismatch.',
          ),
        );
      }
      if (ownerStateAfterWrite.expiredResult case final expired?) {
        return await _resolveInvalidatedWrite(
          request: request,
          writeResult: writeResult,
          invalidatedResult: expired,
        );
      }
      if (!writeResult.didCommit) {
        if (writeResult.disposition == RoutineStoreWriteDisposition.rejected) {
          return _failure(
            request.toolName,
            writeResult.errorMessage ??
                'Failed to create routine: routine persistence was rejected.',
          );
        }
        return _failure(
          request.toolName,
          'Routine store rejected an owner that is still current.',
        );
      }
      final snapshot = writeResult.snapshot;
      if (snapshot == null) {
        return await _resolveInvalidatedWrite(
          request: request,
          writeResult: writeResult,
          invalidatedResult: _failure(
            request.toolName,
            'Routine store committed without an exact snapshot.',
          ),
        );
      }
      if (!snapshot.identity.belongsTo(identity)) {
        return await _resolveInvalidatedWrite(
          request: request,
          writeResult: writeResult,
          invalidatedResult: _failure(
            request.toolName,
            'Failed to create routine: Bad state: '
            'Routine store snapshot identity mismatch.',
          ),
        );
      }
      final created = snapshot.createdRoutine;
      return McpToolResult(
        toolName: request.toolName,
        result: jsonEncode({
          'ok': true,
          'action': 'created',
          'id': created.id,
          'name': name,
          'schedule': scheduleSummary,
          'tools_enabled': toolsEnabled,
          'notify_on_completion': notifyOnCompletion,
          'completion_action': completionAction.name,
          if (created.nextRunAt != null)
            'next_run_at': created.nextRunAt!.toIso8601String(),
        }),
        isSuccess: true,
      );
    } catch (error) {
      return _uncertain(request, 'the routine store failed: $error');
    }
  }

  Future<McpToolResult> _resolveInvalidatedWrite({
    required CreateRoutineToolRequest request,
    required RoutineStoreWriteResult writeResult,
    required McpToolResult invalidatedResult,
  }) async {
    if (!writeResult.didCommit) return invalidatedResult;
    try {
      final compensation = await _storePort.compensate(
        request.identity,
        writeResult,
      );
      _requireIdentity(
        compensation.identity,
        request.identity,
        'Routine store compensation',
      );
      if (compensation.disposition !=
          RoutineStoreCompensationDisposition.failed) {
        return invalidatedResult;
      }
      final detail = compensation.errorMessage?.trim();
      return _failure(
        request.toolName,
        'Routine creation may still be persisted after owner invalidation '
        'because compensation failed'
        '${detail == null || detail.isEmpty ? '' : ': $detail'}; '
        'inspect scheduled routines before retrying.',
      );
    } catch (error) {
      return _failure(
        request.toolName,
        'Routine creation may still be persisted after owner invalidation '
        'because compensation failed: $error; '
        'inspect scheduled routines before retrying.',
      );
    }
  }

  String _scheduleSummary({
    required RoutineScheduleMode scheduleMode,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required int timeOfDayMinutes,
  }) {
    if (scheduleMode == RoutineScheduleMode.dailyTime) {
      return 'daily at '
          '${RoutineScheduleService.formatTimeOfDayMinutes(timeOfDayMinutes)}';
    }
    final unit = intervalUnit.name;
    final singular = unit.substring(0, unit.length - 1);
    return 'every $intervalValue ${intervalValue == 1 ? singular : unit}';
  }

  String _buildPreview({
    required String name,
    required String prompt,
    required String scheduleSummary,
    required bool toolsEnabled,
    required bool notifyOnCompletion,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
    required String workspaceDirectory,
    required bool allowWorkspaceWrites,
  }) {
    final delivery = <String>[
      if (notifyOnCompletion) 'local notification',
      if (completionAction == RoutineCompletionAction.googleChat)
        'Google Chat (${googleChatRule.name})'
      else if (completionAction == RoutineCompletionAction.promptGoogleChat)
        'Google Chat (prompt before posting)',
    ];
    return [
      'Routine: $name',
      'Schedule: $scheduleSummary',
      'Runs automatically without further confirmation once scheduled.',
      'Tools enabled: ${toolsEnabled ? 'yes' : 'no'}',
      'Delivery: ${delivery.isEmpty ? 'none' : delivery.join(', ')}',
      if (workspaceDirectory.isNotEmpty)
        'Workspace: $workspaceDirectory'
            '${allowWorkspaceWrites ? ' (writes allowed)' : ' (read-only)'}',
      '',
      'Prompt:',
      prompt,
    ].join('\n');
  }

  RoutineScheduleMode _parseScheduleMode(Object? value) {
    final normalized = (value as String?)?.trim().toLowerCase() ?? '';
    if (normalized == 'daily' ||
        normalized == 'dailytime' ||
        normalized == 'daily_time' ||
        normalized == 'time_of_day') {
      return RoutineScheduleMode.dailyTime;
    }
    return RoutineScheduleMode.interval;
  }

  RoutineIntervalUnit _parseIntervalUnit(Object? value) {
    return switch ((value as String?)?.trim().toLowerCase()) {
      'minute' || 'minutes' => RoutineIntervalUnit.minutes,
      'day' || 'days' => RoutineIntervalUnit.days,
      _ => RoutineIntervalUnit.hours,
    };
  }

  RoutineCompletionAction _parseCompletionAction(Object? value) {
    return switch ((value as String?)?.trim().toLowerCase()) {
      'google_chat' || 'googlechat' => RoutineCompletionAction.googleChat,
      'prompt_google_chat' ||
      'promptgooglechat' => RoutineCompletionAction.promptGoogleChat,
      _ => RoutineCompletionAction.none,
    };
  }

  RoutineGoogleChatRule _parseGoogleChatRule(Object? value) {
    return switch ((value as String?)?.trim().toLowerCase()) {
      'on_success' || 'onsuccess' => RoutineGoogleChatRule.onSuccess,
      'always' => RoutineGoogleChatRule.always,
      _ => RoutineGoogleChatRule.onFailure,
    };
  }

  int _parseTimeOfDayMinutes(Object? value) {
    if (value is num) return value.toInt();
    final text = (value as String?)?.trim() ?? '';
    if (text.isEmpty) return 480;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (match != null) {
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      return hours * 60 + minutes;
    }
    return int.tryParse(text) ?? 480;
  }

  void _requireIdentity(
    CreateRoutineOperationIdentity actual,
    CreateRoutineOperationIdentity expected,
    String source,
  ) {
    if (!actual.belongsTo(expected)) {
      throw StateError('$source identity mismatch');
    }
  }

  McpToolResult _uncertain(CreateRoutineToolRequest request, String detail) =>
      _failure(
        request.toolName,
        'Routine creation may have persisted because $detail. '
        'Inspect scheduled routines before retrying.',
      );

  McpToolResult _failure(String toolName, String message) => McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}
