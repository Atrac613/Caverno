import '../../data/datasources/local_shell_tools.dart';
import '../../../settings/domain/services/local_command_permission_service.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'background_process_path_policy.dart';
import 'background_process_start_contract.dart';
import 'background_process_result_ledger.dart';
import 'background_process_tool_contract.dart';
import 'background_process_tool_results.dart';
import 'local_command_tool_handler.dart';
import 'out_of_root_command_paths.dart';
import 'process_start_result_policy.dart';

export 'background_process_tool_contract.dart';

// ChatNotifier decomposition collaborator: background-process-tool-handler
typedef _Request = BackgroundProcessToolRequest;
typedef _Approval = LocalCommandApprovalRequest;

final class BackgroundProcessToolHandler {
  BackgroundProcessToolHandler({
    required BackgroundProcessExecutionPort executionPort,
    required BackgroundProcessLookupPort lookupPort,
    required LocalCommandApprovalPort approvalPort,
    required CommandPermissionRuleStorePort permissionRuleStorePort,
    ProcessStartResultPolicy startResultPolicy =
        const ProcessStartResultPolicy(),
    BackgroundProcessPathPolicy pathPolicy =
        const BackgroundProcessPathPolicy(),
    BackgroundProcessStartContract startContract =
        const BackgroundProcessStartContract(),
    BackgroundProcessToolResults results = const BackgroundProcessToolResults(),
    DateTime Function()? clock,
  }) : _executionPort = executionPort,
       _lookupPort = lookupPort,
       _approvalPort = approvalPort,
       _permissionRuleStorePort = permissionRuleStorePort,
       _startResultPolicy = startResultPolicy,
       _pathPolicy = pathPolicy,
       _startContract = startContract,
       _results = results,
       _ledger = BackgroundProcessResultLedger(
         approvalPort: approvalPort,
         results: results,
       ),
       _clock = clock ?? DateTime.now;

  static const _missingCommandMessage =
      'command is required and working_directory must be provided or inferred '
      'from the selected coding project';
  static const _cancelWarningMessage =
      'This stops a running local command and may leave partial side effects.';

  final BackgroundProcessExecutionPort _executionPort;
  final BackgroundProcessLookupPort _lookupPort;
  final LocalCommandApprovalPort _approvalPort;
  final CommandPermissionRuleStorePort _permissionRuleStorePort;
  final ProcessStartResultPolicy _startResultPolicy;
  final BackgroundProcessPathPolicy _pathPolicy;
  final BackgroundProcessStartContract _startContract;
  final BackgroundProcessToolResults _results;
  final BackgroundProcessResultLedger _ledger;
  final DateTime Function() _clock;

  Future<McpToolResult> handle(BackgroundProcessToolRequest request) {
    return switch (request.toolName) {
      'process_start' => _handleStart(request),
      'process_cancel' => _handleCancel(request),
      _ => throw ArgumentError.value(
        request.toolName,
        'toolName',
        'Unsupported background process tool',
      ),
    };
  }

  Future<McpToolResult> _handleStart(_Request request) async {
    final dispatchedAt = _clock();
    final command = LocalShellTools.normalizeCommand(
      (request.arguments['command'] as String?)?.trim() ?? '',
    );
    final workingDirectory = _pathPolicy.resolveWorkingDirectory(request);
    if (command.isEmpty || workingDirectory == null) {
      return _results.failure(request.toolName, _missingCommandMessage);
    }
    if (!_pathPolicy.isAllowedWorkingDirectory(
      workingDirectory,
      request.allowedWorkingDirectoryRoot,
    )) {
      return _results.outsideProject(request.toolName);
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
    final permission = _permissionRuleStorePort.evaluate(
      request.owner,
      CommandPermissionRuleRequest(
        command: command,
        workingDirectory: workingDirectory,
      ),
    );
    final approvalScope = LocalCommandApprovalScope.of(
      command: command,
      projectRoot: request.allowedWorkingDirectoryRoot,
      reachesNativeShell: true,
      commandShapeRequiresApproval:
          LocalCommandPermissionService.requiresExplicitApproval,
    );
    final requiresExplicit = approvalScope.requiresExplicitApproval;
    if (permission == CommandPermissionRuleDecision.deny) {
      return _results.failure(
        request.toolName,
        'Local command was denied by a saved permission rule',
      );
    }
    if (_ledger.isExpired(request)) return _results.expired(request.toolName);
    if (!request.isRemoteInteraction &&
        permission == CommandPermissionRuleDecision.allow &&
        !requiresExplicit) {
      return _executeStart(request, execution, dispatchedAt);
    }

    final warning = LocalCommandPermissionService.riskWarningFor(command);
    final approval = LocalCommandApprovalRequest(
      toolCallId: request.toolCallId,
      execution: execution,
      reason: request.arguments['reason'] as String?,
      warningTitle: warning?.title,
      warningMessage: warning?.message,
      outOfRootPaths: approvalScope.outOfRootPaths,
      requiredManualDecision: approvalScope.requiredManualDecision,
      requiredManualDecisionSource: approvalScope.requiredManualDecisionSource,
    );
    return _withApproval(
      request,
      approval,
      denialMessage: 'User denied background process start',
      ruleRequest: CommandPermissionRuleRequest(
        command: command,
        workingDirectory: workingDirectory,
      ),
      canRememberRule: !request.isRemoteInteraction,
      run: (cacheRequest) => _executeStart(
        request,
        execution,
        dispatchedAt,
        cacheRequest: cacheRequest,
      ),
    );
  }

  Future<McpToolResult> _handleCancel(_Request request) async {
    final processId = request.arguments['job_id']?.toString().trim() ?? '';
    if (processId.isEmpty) {
      return _results.missingProcessId(request.toolName);
    }
    final execution = LocalCommandExecutionRequest(
      toolCallId: request.toolCallId,
      toolName: request.toolName,
      command: 'process_cancel $processId',
      workingDirectory: _pathPolicy.cancelWorkingDirectory(request),
      arguments: {'job_id': processId},
    );
    final approval = LocalCommandApprovalRequest(
      toolCallId: request.toolCallId,
      execution: execution,
      reason: 'Cancel background process $processId',
      warningTitle: 'Cancel background process?',
      warningMessage: _cancelWarningMessage,
    );
    return _withApproval(
      request,
      approval,
      denialMessage: 'User denied background process cancellation',
      run: (cacheRequest) => _executeCancel(request, processId, cacheRequest),
    );
  }

  Future<McpToolResult> _executeCancel(
    _Request request,
    String processId,
    _Approval? cacheRequest,
  ) async {
    final lookupCompletion = await _lookupPort.lookup(
      request.owner,
      request.toolCallId,
      processId,
    );
    if (_ledger.completionExpired(lookupCompletion, request)) {
      return _results.expired(request.toolName);
    }
    final identity = lookupCompletion.value;
    if (_ledger.isExpired(request)) return _results.expired(request.toolName);
    if (identity == null) {
      return _ledger.cacheResult(
        request,
        cacheRequest,
        _results.processNotFound(request.toolName, processId),
      );
    }
    if (identity.externalProcessId != processId) {
      throw StateError('Background process lookup ID mismatch.');
    }
    late final LocalCommandCompletion<McpToolResult> cancelCompletion;
    try {
      cancelCompletion = await _executionPort.cancel(
        request.owner,
        request.toolCallId,
        identity,
      );
    } catch (_) {
      if (_ledger.isExpired(request)) {
        return _results.effectUncertain(request.toolName);
      }
      rethrow;
    }
    if (!_ledger.belongsToRequest(cancelCompletion, request) ||
        cancelCompletion.disposition ==
            LocalCommandCompletionDisposition.ownerExpired ||
        _ledger.isExpired(request)) {
      return _results.effectUncertain(request.toolName);
    }
    final cancelled = cancelCompletion.value!;
    return _ledger.cacheResult(
      request,
      cacheRequest,
      cancelled,
      sideEffectMayHaveOccurred: true,
    );
  }

  Future<McpToolResult> _withApproval(
    _Request request,
    _Approval approval, {
    required String denialMessage,
    required Future<McpToolResult> Function(_Approval? cacheRequest) run,
    CommandPermissionRuleRequest? ruleRequest,
    bool canRememberRule = false,
  }) async {
    if (_ledger.isExpired(request)) return _results.expired(request.toolName);
    final cached = _approvalPort.lookupDenial(request.owner, approval);
    if (cached != null) {
      if (!_ledger.belongsToRequest(cached, request) ||
          cached.disposition ==
              LocalCommandCompletionDisposition.ownerExpired ||
          _ledger.isExpired(request)) {
        return _results.expired(request.toolName);
      }
      return _results.requireToolName(cached.value!, request.toolName);
    }
    final gateCompletion = await _approvalPort.resolveGate(
      request.owner,
      approval,
    );
    if (_ledger.completionExpired(gateCompletion, request)) {
      return _results.expired(request.toolName);
    }
    final gate = gateCompletion.value!;
    if (gate.isDenied) {
      return _ledger.rememberDenial(
        request,
        approval,
        _results.autoReviewDenied(
          request.toolName,
          gate.deniedRationale ?? 'No rationale was provided.',
        ),
      );
    }
    if (gate.needsManual) {
      final completion = await _approvalPort.requestManualApproval(
        request.owner,
        approval,
        gate,
      );
      if (_ledger.completionExpired(completion, request)) {
        return _results.expired(request.toolName);
      }
      final manual = completion.value!;
      if (_ledger.isExpired(request)) return _results.expired(request.toolName);
      if (manual.shouldRemember &&
          canRememberRule &&
          ruleRequest != null &&
          (!approval.requiresFreshManualApproval ||
              manual.rememberedAction ==
                  RememberedCommandPermissionAction.deny)) {
        final ruleCompletion = await _permissionRuleStorePort.remember(
          request.owner,
          request.toolCallId,
          RememberedCommandPermissionRule(
            action: manual.rememberedAction!,
            match: manual.rememberedMatch!,
            command: ruleRequest.command,
            workingDirectory: ruleRequest.workingDirectory,
          ),
        );
        if (_ledger.completionExpired(ruleCompletion, request)) {
          return _results.expired(request.toolName);
        }
      }
      if (!manual.approved) {
        return _ledger.rememberDenial(
          request,
          approval,
          _results.failure(request.toolName, denialMessage),
        );
      }
    }
    if (_ledger.isExpired(request)) return _results.expired(request.toolName);
    return run(
      gate.bypassedApproval || approval.requiresFreshManualApproval
          ? null
          : approval,
    );
  }

  Future<McpToolResult> _executeStart(
    _Request request,
    LocalCommandExecutionRequest execution,
    DateTime dispatchedAt, {
    _Approval? cacheRequest,
  }) async {
    late final LocalCommandCompletion<BackgroundProcessStartResult> completion;
    try {
      completion = await _executionPort.start(request.owner, execution);
    } catch (_) {
      if (_ledger.isExpired(request)) {
        return _results.effectUncertain(request.toolName);
      }
      rethrow;
    }
    if (!_ledger.belongsToRequest(completion, request) ||
        completion.disposition ==
            LocalCommandCompletionDisposition.ownerExpired) {
      return _results.effectUncertain(request.toolName);
    }
    final started = completion.value!;
    final rawResult = started.result;
    final assessment = _startContract.assess(
      started,
      expectedToolName: request.toolName,
    );
    if (!assessment.isValid) {
      return _results.effectUncertain(request.toolName);
    }
    if (_ledger.isExpired(request)) {
      return _rollbackStart(request, assessment);
    }
    final result =
        _startResultPolicy.buildStaleGuardResult(
          ToolCallInfo(
            id: request.toolCallId,
            name: execution.toolName,
            arguments: execution.arguments,
          ),
          rawResult,
          dispatchedAt: dispatchedAt,
        ) ??
        rawResult;
    if (result.toolName != request.toolName) {
      return _results.effectUncertain(request.toolName);
    }
    return _ledger.cacheResult(
      request,
      cacheRequest,
      result,
      sideEffectMayHaveOccurred: true,
    );
  }

  Future<McpToolResult> _rollbackStart(
    _Request request,
    BackgroundProcessStartAssessment assessment,
  ) async {
    final identity = assessment.identity;
    if (!assessment.startedNewProcess ||
        identity == null ||
        !identity.isRunning) {
      return _results.expired(request.toolName);
    }
    try {
      final completion = await _executionPort.cancel(
        request.owner,
        request.toolCallId,
        identity,
        requireTermination: true,
      );
      if (!_ledger.belongsToRequest(completion, request)) {
        return _results.effectUncertain(request.toolName);
      }
      if (completion.disposition ==
          LocalCommandCompletionDisposition.ownerExpired) {
        return _results.expired(request.toolName);
      }
    } catch (_) {
      return _results.effectUncertain(request.toolName);
    }
    return _results.expired(request.toolName);
  }
}
