import 'dart:convert';

import '../../data/datasources/local_shell_tools.dart';
import '../../../settings/domain/services/local_command_permission_service.dart';
import '../entities/mcp_tool_entity.dart';
import 'local_command_tool_contract.dart';
import 'local_command_working_directory.dart';
import 'out_of_root_command_paths.dart';

export 'local_command_tool_contract.dart';

// ChatNotifier decomposition collaborator: local-command-tool-handler
final class LocalCommandToolHandler {
  const LocalCommandToolHandler({
    required LocalCommandExecutionPort executionPort,
    required LocalCommandApprovalPort approvalPort,
    required CommandPermissionRuleStorePort permissionRuleStorePort,
  }) : _executionPort = executionPort,
       _approvalPort = approvalPort,
       _permissionRuleStorePort = permissionRuleStorePort;
  static const Duration defaultTimeout = localCommandDefaultTimeout;
  static const String _missingArgumentsMessage =
      'command is required and working_directory must be provided or inferred '
      'from the selected coding project';
  static const String _outsideProjectMessage =
      'working_directory must resolve inside the selected coding project';
  static const _expiredMessage = 'The approval turn expired before execution';
  static const String _effectUncertainMessage =
      'The local command may have completed after its owner expired; inspect '
      'possible process and filesystem effects before retrying';
  final LocalCommandExecutionPort _executionPort;
  final LocalCommandApprovalPort _approvalPort;
  final CommandPermissionRuleStorePort _permissionRuleStorePort;

  Future<McpToolResult> handle(LocalCommandToolRequest request) async {
    final command = LocalShellTools.normalizeCommand(
      (request.arguments['command'] as String?)?.trim() ?? '',
    );
    final workingDirectory = LocalCommandWorkingDirectory.resolve(request);
    if (command.isEmpty || workingDirectory == null) {
      return _failure(request.toolName, _missingArgumentsMessage);
    }
    if (!LocalCommandWorkingDirectory.isAllowed(
      workingDirectory,
      request.allowedWorkingDirectoryRoot,
    )) {
      return _outsideProjectFailure(request.toolName);
    }

    final execution = LocalCommandExecutionRequest(
      toolCallId: request.toolCallId,
      toolName: request.toolName,
      command: command,
      workingDirectory: workingDirectory,
      arguments: {
        ...request.arguments,
        'command': command,
        'working_directory': workingDirectory,
        'allowed_read_root': request.allowedWorkingDirectoryRoot,
      },
    );
    final ruleRequest = CommandPermissionRuleRequest(
      command: command,
      workingDirectory: workingDirectory,
    );
    if (_approvalPort.isExpired(request.owner, request.toolCallId)) {
      return _expiredFailure(request.toolName);
    }
    final permission = _permissionRuleStorePort.evaluate(
      request.owner,
      ruleRequest,
    );
    final approvalScope = LocalCommandApprovalScope.of(
      command: command,
      projectRoot: request.allowedWorkingDirectoryRoot,
      reachesNativeShell:
          argumentIsTruthy(request.arguments['background']) ||
          !LocalShellTools.isReadOnly(command),
      commandShapeRequiresApproval:
          LocalCommandPermissionService.requiresExplicitApproval,
    );
    final requiresExplicitApproval = approvalScope.requiresExplicitApproval;
    if (permission == CommandPermissionRuleDecision.deny) {
      return _failure(
        request.toolName,
        'Local command was denied by a saved permission rule',
      );
    }

    if (!request.isRemoteInteraction &&
        permission == CommandPermissionRuleDecision.allow &&
        !requiresExplicitApproval) {
      return _execute(request, execution);
    }
    if (!argumentIsTruthy(request.arguments['background']) &&
        LocalShellTools.isReadOnly(command) &&
        !requiresExplicitApproval) {
      return _execute(request, execution);
    }

    final riskWarning = LocalCommandPermissionService.riskWarningFor(command);
    final approvalRequest = LocalCommandApprovalRequest(
      toolCallId: request.toolCallId,
      execution: execution,
      reason: request.arguments['reason'] as String?,
      warningTitle: riskWarning?.title,
      warningMessage: riskWarning?.message,
      outOfRootPaths: approvalScope.outOfRootPaths,
      requiredManualDecision: approvalScope.requiredManualDecision,
      requiredManualDecisionSource: approvalScope.requiredManualDecisionSource,
    );
    final cachedDenial = _approvalPort.lookupDenial(
      request.owner,
      approvalRequest,
    );
    if (cachedDenial != null) {
      if (!cachedDenial.belongsTo(request.owner, request.toolCallId) ||
          cachedDenial.disposition ==
              LocalCommandCompletionDisposition.ownerExpired ||
          _approvalPort.isExpired(request.owner, request.toolCallId)) {
        return _expiredFailure(request.toolName);
      }
      return _validResult(cachedDenial.value!, request.toolName);
    }

    final gateCompletion = await _approvalPort.resolveGate(
      request.owner,
      approvalRequest,
    );
    if (_completionExpired(gateCompletion, request, 'Local command gate')) {
      return _expiredFailure(request.toolName);
    }
    final gate = gateCompletion.value!;
    if (gate.isDenied) {
      return _rememberDenial(
        request,
        approvalRequest,
        _autoReviewDeniedResult(
          request.toolName,
          gate.deniedRationale ?? 'No rationale was provided.',
        ),
      );
    }
    if (gate.needsManual) {
      final manualCompletion = await _approvalPort.requestManualApproval(
        request.owner,
        approvalRequest,
        gate,
      );
      if (_completionExpired(
        manualCompletion,
        request,
        'Local command manual approval',
      )) {
        return _expiredFailure(request.toolName);
      }
      final manual = manualCompletion.value!;
      if (_approvalPort.isExpired(request.owner, request.toolCallId)) {
        return _expiredFailure(request.toolName);
      }
      if (manual.shouldRemember &&
          !request.isRemoteInteraction &&
          (!approvalRequest.requiresFreshManualApproval ||
              manual.rememberedAction ==
                  RememberedCommandPermissionAction.deny)) {
        final ruleCompletion = await _permissionRuleStorePort.remember(
          request.owner,
          request.toolCallId,
          RememberedCommandPermissionRule(
            action: manual.rememberedAction!,
            match: manual.rememberedMatch!,
            command: command,
            workingDirectory: workingDirectory,
          ),
        );
        if (_completionExpired(
          ruleCompletion,
          request,
          'Local command permission rule write',
        )) {
          return _expiredFailure(request.toolName);
        }
        if (_approvalPort.isExpired(request.owner, request.toolCallId)) {
          return _expiredFailure(request.toolName);
        }
      }
      if (!manual.approved) {
        return _rememberDenial(
          request,
          approvalRequest,
          _failure(request.toolName, 'User denied local command execution'),
        );
      }
    }

    if (_approvalPort.isExpired(request.owner, request.toolCallId)) {
      return _expiredFailure(request.toolName);
    }
    return _execute(
      request,
      execution,
      cacheRequest:
          gate.bypassedApproval || approvalRequest.requiresFreshManualApproval
          ? null
          : approvalRequest,
    );
  }

  Future<McpToolResult> _execute(
    LocalCommandToolRequest request,
    LocalCommandExecutionRequest execution, {
    LocalCommandApprovalRequest? cacheRequest,
  }) async {
    late final LocalCommandCompletion<McpToolResult> completion;
    try {
      completion = await _executionPort.execute(request.owner, execution);
    } catch (_) {
      if (_approvalPort.isExpired(request.owner, request.toolCallId)) {
        return _effectUncertainFailure(request.toolName);
      }
      rethrow;
    }
    if (!completion.belongsTo(request.owner, request.toolCallId) ||
        completion.disposition ==
            LocalCommandCompletionDisposition.ownerExpired) {
      return _effectUncertainFailure(request.toolName);
    }
    final completionResult = completion.value!;
    if (completionResult.toolName != request.toolName) {
      return _effectUncertainFailure(request.toolName);
    }
    final effectDisposition = completion.effectDisposition;
    final settlement = completion.effectSettlement;
    if (effectDisposition == LocalCommandEffectDisposition.effectUncertain) {
      return completionResult;
    }
    if (effectDisposition == LocalCommandEffectDisposition.settlementRequired) {
      if (settlement == null ||
          !settlement.identity.belongsTo(
            execution.identityFor(request.owner),
          )) {
        return _effectUncertainFailure(request.toolName);
      }
    } else if (completionResult.isSuccess) {
      return _effectUncertainFailure(request.toolName);
    }
    final result = completionResult;
    if (_approvalPort.isExpired(request.owner, request.toolCallId)) {
      return _effectUncertainFailure(request.toolName);
    }
    if (cacheRequest == null) {
      return _settleExecutionEffect(
        request,
        effectDisposition,
        settlement,
        result,
      );
    }
    final LocalCommandCompletion<Object?> acknowledgement;
    try {
      acknowledgement = _approvalPort.rememberResult(
        request.owner,
        cacheRequest,
        result,
      );
    } catch (_) {
      return _effectUncertainFailure(request.toolName);
    }
    final cacheAccepted =
        acknowledgement.belongsTo(request.owner, request.toolCallId) &&
        acknowledgement.disposition ==
            LocalCommandCompletionDisposition.completed &&
        !_approvalPort.isExpired(request.owner, request.toolCallId);
    return cacheAccepted
        ? _settleExecutionEffect(request, effectDisposition, settlement, result)
        : _effectUncertainFailure(request.toolName);
  }

  McpToolResult _settleExecutionEffect(
    LocalCommandToolRequest request,
    LocalCommandEffectDisposition disposition,
    LocalCommandEffectSettlement? settlement,
    McpToolResult result,
  ) {
    if (disposition == LocalCommandEffectDisposition.noEffect) return result;
    if (disposition != LocalCommandEffectDisposition.settlementRequired ||
        settlement == null) {
      return _effectUncertainFailure(request.toolName);
    }
    try {
      return settlement.settle()
          ? result
          : _effectUncertainFailure(request.toolName);
    } catch (_) {
      return _effectUncertainFailure(request.toolName);
    }
  }

  bool _completionExpired<T>(
    LocalCommandCompletion<T> completion,
    LocalCommandToolRequest request,
    String source,
  ) {
    if (completion.owner != request.owner) {
      throw StateError('$source owner mismatch.');
    }
    if (completion.toolCallId != request.toolCallId) {
      throw StateError('$source tool call mismatch.');
    }
    return completion.disposition ==
        LocalCommandCompletionDisposition.ownerExpired;
  }

  McpToolResult _validResult(McpToolResult result, String toolName) {
    if (result.toolName != toolName) {
      throw StateError('Local command result tool name mismatch.');
    }
    return result;
  }

  McpToolResult _rememberDenial(
    LocalCommandToolRequest request,
    LocalCommandApprovalRequest approval,
    McpToolResult result,
  ) {
    final exactResult = _validResult(result, request.toolName);
    if (_approvalPort.isExpired(request.owner, request.toolCallId)) {
      return _expiredFailure(request.toolName);
    }
    final acknowledgement = _approvalPort.rememberDenial(
      request.owner,
      approval,
      exactResult,
    );
    return acknowledgement.belongsTo(request.owner, request.toolCallId) &&
            acknowledgement.disposition ==
                LocalCommandCompletionDisposition.completed &&
            !_approvalPort.isExpired(request.owner, request.toolCallId)
        ? exactResult
        : _expiredFailure(request.toolName);
  }

  McpToolResult _expiredFailure(String toolName) =>
      _failure(toolName, _expiredMessage);

  McpToolResult _effectUncertainFailure(String toolName) =>
      _failure(toolName, _effectUncertainMessage);

  McpToolResult _outsideProjectFailure(String toolName) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'code': 'working_directory_outside_project',
        'error': _outsideProjectMessage,
      }),
      isSuccess: false,
      errorMessage: _outsideProjectMessage,
    );
  }

  McpToolResult _autoReviewDeniedResult(String toolName, String rationale) {
    return McpToolResult(
      toolName: toolName,
      result: 'Auto-review denied this action. Rationale: $rationale',
      isSuccess: false,
      errorMessage: 'Auto-review denied: $rationale',
    );
  }

  McpToolResult _failure(String toolName, String message) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }
}
