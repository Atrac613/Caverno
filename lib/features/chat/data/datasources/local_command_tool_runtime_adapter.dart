import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:uuid/uuid.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/local_command_permission_service.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/local_command_execution_authority.dart';
import '../../domain/services/local_command_tool_handler.dart';

export '../../domain/services/local_command_execution_authority.dart';
export '../../domain/services/local_command_tool_handler.dart';

typedef LocalCommandOwnerAcknowledgementCallback =
    LocalCommandRuntimeOwnerAcknowledgement Function(
      LocalCommandOperationIdentity identity,
    );
typedef LocalCommandExecutionCallback =
    Future<LocalCommandRuntimeExecutionAcknowledgement> Function(
      LocalCommandRuntimeExecution operation,
    );
typedef LocalCommandOwnerCurrentCallback = bool Function(ChatTurnOwner owner);
typedef LocalCommandDenialLookupCallback =
    McpToolResult? Function(
      ChatTurnOwner owner,
      LocalCommandApprovalRequest request,
    );
typedef LocalCommandGateCallback =
    Future<ToolApprovalGateDecision> Function(
      ChatTurnOwner owner,
      LocalCommandApprovalRequest request,
    );
typedef LocalCommandManualApprovalCallback =
    Future<LocalCommandManualApproval> Function(
      ChatTurnOwner owner,
      LocalCommandApprovalRequest request,
      ToolApprovalGateDecision gate,
    );
typedef LocalCommandApprovalCacheWriteCallback =
    void Function(
      ChatTurnOwner owner,
      LocalCommandApprovalRequest request,
      McpToolResult result,
    );
typedef LocalCommandPermissionRuleUpsertCallback =
    Future<void> Function(LocalCommandPermissionRule rule);
typedef LocalCommandPermissionRuleRemoveCallback =
    Future<void> Function(String ruleId);

enum LocalCommandRuntimeOwnerDisposition {
  current,
  ownerExpired,
  effectUncertain,
}

/// Exact lifecycle acknowledgement captured at a runtime boundary.
final class LocalCommandRuntimeOwnerAcknowledgement {
  const LocalCommandRuntimeOwnerAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  const LocalCommandRuntimeOwnerAcknowledgement.current({
    required this.identity,
  }) : disposition = LocalCommandRuntimeOwnerDisposition.current;

  const LocalCommandRuntimeOwnerAcknowledgement.ownerExpired({
    required this.identity,
  }) : disposition = LocalCommandRuntimeOwnerDisposition.ownerExpired;

  const LocalCommandRuntimeOwnerAcknowledgement.effectUncertain({
    required this.identity,
  }) : disposition = LocalCommandRuntimeOwnerDisposition.effectUncertain;

  final LocalCommandOperationIdentity identity;
  final LocalCommandRuntimeOwnerDisposition disposition;
}

enum LocalCommandRuntimeExecutionDisposition {
  completed,
  rejected,
  ownerExpired,
  effectUncertain,
}

/// Immutable operation passed to the raw local-command runtime.
final class LocalCommandRuntimeExecution {
  LocalCommandRuntimeExecution({
    required this.identity,
    required LocalCommandExecutionRequest request,
    required LocalCommandEffectPermit effectPermit,
  }) : command = request.command,
       workingDirectory = request.workingDirectory,
       arguments = request.arguments,
       timeout = request.timeout,
       _effectPermit = effectPermit;

  final LocalCommandOperationIdentity identity;
  final String command;
  final String workingDirectory;
  final Map<String, dynamic> arguments;
  final Duration timeout;
  final LocalCommandEffectPermit _effectPermit;

  Future<T> runEffect<T>(Future<T> Function() effect) {
    return _effectPermit.runEffect(effect);
  }
}

/// Exact raw-runtime receipt, including explicit ambiguous-effect outcomes.
final class LocalCommandRuntimeExecutionAcknowledgement {
  const LocalCommandRuntimeExecutionAcknowledgement.completed({
    required this.identity,
    required this.result,
  }) : disposition = LocalCommandRuntimeExecutionDisposition.completed,
       message = null;

  const LocalCommandRuntimeExecutionAcknowledgement.rejected({
    required this.identity,
    required this.result,
  }) : disposition = LocalCommandRuntimeExecutionDisposition.rejected,
       message = null;

  const LocalCommandRuntimeExecutionAcknowledgement.ownerExpired({
    required this.identity,
    this.message,
  }) : disposition = LocalCommandRuntimeExecutionDisposition.ownerExpired,
       result = null;

  const LocalCommandRuntimeExecutionAcknowledgement.effectUncertain({
    required this.identity,
    this.message,
  }) : disposition = LocalCommandRuntimeExecutionDisposition.effectUncertain,
       result = null;

  final LocalCommandOperationIdentity identity;
  final LocalCommandRuntimeExecutionDisposition disposition;
  final McpToolResult? result;
  final String? message;
}

/// Runtime boundary used by the owner-aware local-command execution adapter.
abstract interface class LocalCommandRuntimePort {
  LocalCommandRuntimeOwnerAcknowledgement acknowledgeOwner(
    LocalCommandOperationIdentity identity,
  );

  Future<LocalCommandRuntimeExecutionAcknowledgement> execute(
    LocalCommandRuntimeExecution operation,
  );
}

/// Callback bridge for the existing owner registry and MCP service.
final class CallbackLocalCommandRuntimePort implements LocalCommandRuntimePort {
  const CallbackLocalCommandRuntimePort({
    required LocalCommandOwnerAcknowledgementCallback acknowledgeOwner,
    required LocalCommandExecutionCallback execute,
  }) : _acknowledgeOwner = acknowledgeOwner,
       _execute = execute;

  final LocalCommandOwnerAcknowledgementCallback _acknowledgeOwner;
  final LocalCommandExecutionCallback _execute;

  @override
  LocalCommandRuntimeOwnerAcknowledgement acknowledgeOwner(
    LocalCommandOperationIdentity identity,
  ) => _acknowledgeOwner(identity);

  @override
  Future<LocalCommandRuntimeExecutionAcknowledgement> execute(
    LocalCommandRuntimeExecution operation,
  ) => _execute(operation);
}

/// Owner-validating bridge for the existing approval UI and approval cache.
final class CallbackLocalCommandApprovalPort
    implements LocalCommandApprovalPort {
  const CallbackLocalCommandApprovalPort({
    required LocalCommandOwnerCurrentCallback ownerIsCurrent,
    required LocalCommandDenialLookupCallback lookupDenial,
    required LocalCommandGateCallback resolveGate,
    required LocalCommandManualApprovalCallback requestManualApproval,
    required LocalCommandApprovalCacheWriteCallback rememberDenial,
    required LocalCommandApprovalCacheWriteCallback rememberResult,
  }) : _ownerIsCurrent = ownerIsCurrent,
       _lookupDenial = lookupDenial,
       _resolveGate = resolveGate,
       _requestManualApproval = requestManualApproval,
       _rememberDenial = rememberDenial,
       _rememberResult = rememberResult;

  final LocalCommandOwnerCurrentCallback _ownerIsCurrent;
  final LocalCommandDenialLookupCallback _lookupDenial;
  final LocalCommandGateCallback _resolveGate;
  final LocalCommandManualApprovalCallback _requestManualApproval;
  final LocalCommandApprovalCacheWriteCallback _rememberDenial;
  final LocalCommandApprovalCacheWriteCallback _rememberResult;

  @override
  bool isExpired(ChatTurnOwner owner, String toolCallId) => !_isCurrent(owner);

  @override
  LocalCommandCompletion<McpToolResult>? lookupDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  ) {
    if (!_isCurrent(owner)) {
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
      );
    }
    final result = _lookupDenial(owner, request);
    if (result == null) return null;
    return _acknowledge(owner, request.toolCallId, result);
  }

  @override
  Future<LocalCommandCompletion<ToolApprovalGateDecision>> resolveGate(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  ) async {
    if (!_isCurrent(owner)) {
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
      );
    }
    final gate = await _resolveGate(owner, request);
    return _acknowledge(owner, request.toolCallId, gate);
  }

  @override
  Future<LocalCommandCompletion<LocalCommandManualApproval>>
  requestManualApproval(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    ToolApprovalGateDecision gate,
  ) async {
    if (!_isCurrent(owner)) {
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
      );
    }
    final approval = await _requestManualApproval(owner, request, gate);
    return _acknowledge(owner, request.toolCallId, approval);
  }

  @override
  LocalCommandCompletion<Object?> rememberDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) => _writeCache(_rememberDenial, owner, request, result);

  @override
  LocalCommandCompletion<Object?> rememberResult(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) => _writeCache(_rememberResult, owner, request, result);

  LocalCommandCompletion<Object?> _writeCache(
    LocalCommandApprovalCacheWriteCallback write,
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) {
    if (!_isCurrent(owner)) {
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
      );
    }
    write(owner, request, result);
    return _acknowledge<Object?>(owner, request.toolCallId, null);
  }

  LocalCommandCompletion<T> _acknowledge<T>(
    ChatTurnOwner owner,
    String toolCallId,
    T value,
  ) {
    return _isCurrent(owner)
        ? LocalCommandCompletion.completed(
            owner: owner,
            toolCallId: toolCallId,
            value: value,
          )
        : LocalCommandCompletion.ownerExpired(
            owner: owner,
            toolCallId: toolCallId,
          );
  }

  bool _isCurrent(ChatTurnOwner owner) {
    try {
      return _ownerIsCurrent(owner);
    } catch (_) {
      return false;
    }
  }
}

/// Owner-bound adapter for one immutable permission-rule snapshot.
final class LocalCommandPermissionRuleRuntimeAdapter
    implements CommandPermissionRuleStorePort {
  LocalCommandPermissionRuleRuntimeAdapter({
    required this.owner,
    required Iterable<LocalCommandPermissionRule> rules,
    required LocalCommandOwnerCurrentCallback ownerIsCurrent,
    required LocalCommandPermissionRuleUpsertCallback upsert,
    required LocalCommandPermissionRuleRemoveCallback remove,
  }) : _rules = List<LocalCommandPermissionRule>.unmodifiable(rules),
       _ownerIsCurrent = ownerIsCurrent,
       _upsert = upsert,
       _remove = remove;

  final ChatTurnOwner owner;
  final List<LocalCommandPermissionRule> _rules;
  final LocalCommandOwnerCurrentCallback _ownerIsCurrent;
  final LocalCommandPermissionRuleUpsertCallback _upsert;
  final LocalCommandPermissionRuleRemoveCallback _remove;

  @override
  CommandPermissionRuleDecision evaluate(
    ChatTurnOwner candidate,
    CommandPermissionRuleRequest request,
  ) {
    if (candidate != owner || !_isCurrent()) {
      return CommandPermissionRuleDecision.deny;
    }
    return switch (LocalCommandPermissionService.evaluate(
      command: request.command,
      workingDirectory: request.workingDirectory,
      rules: _rules,
    ).action) {
      LocalCommandPermissionAction.allow => CommandPermissionRuleDecision.allow,
      LocalCommandPermissionAction.deny => CommandPermissionRuleDecision.deny,
      LocalCommandPermissionAction.ask => CommandPermissionRuleDecision.ask,
    };
  }

  @override
  Future<LocalCommandCompletion<Object?>> remember(
    ChatTurnOwner candidate,
    String toolCallId,
    RememberedCommandPermissionRule rule,
  ) async {
    if (candidate != owner || !_isCurrent()) {
      return LocalCommandCompletion.ownerExpired(
        owner: candidate,
        toolCallId: toolCallId,
      );
    }
    final ruleId = const Uuid().v4();
    await _upsert(
      LocalCommandPermissionService.buildExactRule(
        id: ruleId,
        action: switch (rule.action) {
          RememberedCommandPermissionAction.allow =>
            LocalCommandPermissionAction.allow,
          RememberedCommandPermissionAction.deny =>
            LocalCommandPermissionAction.deny,
        },
        command: rule.command,
        workingDirectory: rule.workingDirectory,
      ).copyWith(
        match: switch (rule.match) {
          RememberedCommandPermissionMatch.exact =>
            LocalCommandPermissionMatch.exact,
          RememberedCommandPermissionMatch.prefix =>
            LocalCommandPermissionMatch.prefix,
        },
      ),
    );
    if (_isCurrent()) {
      return LocalCommandCompletion.completed(
        owner: candidate,
        toolCallId: toolCallId,
        value: null,
      );
    }
    await _remove(ruleId);
    return LocalCommandCompletion.ownerExpired(
      owner: candidate,
      toolCallId: toolCallId,
    );
  }

  bool _isCurrent() {
    try {
      return _ownerIsCurrent(owner);
    } catch (_) {
      return false;
    }
  }
}

/// Production execution adapter for one exact owner-scoped local command.
final class LocalCommandToolRuntimeAdapter
    implements LocalCommandExecutionPort {
  const LocalCommandToolRuntimeAdapter({
    required LocalCommandRuntimePort runtimePort,
    required LocalCommandExecutionAuthority executionAuthority,
  }) : _runtimePort = runtimePort,
       _executionAuthority = executionAuthority;

  static const _uncertainMessage =
      'The local command may have partially completed; inspect process and '
      'filesystem effects before retrying';

  final LocalCommandRuntimePort _runtimePort;
  final LocalCommandExecutionAuthority _executionAuthority;

  LocalCommandEffectReceipt? get pendingEffectRecovery {
    return _executionAuthority.pendingRecovery;
  }

  bool clearEffectRecovery(LocalCommandEffectReceipt receipt) {
    return _executionAuthority.clearEffectRecovery(receipt);
  }

  LocalCommandEffectReceipt? clearOwner(ChatTurnOwner owner) {
    return _executionAuthority.clearOwner(owner);
  }

  LocalCommandEffectReceipt? clearAll() {
    return _executionAuthority.clearAll();
  }

  @override
  Future<LocalCommandCompletion<McpToolResult>> execute(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest request,
  ) async {
    final identity = request.identityFor(owner);
    final before = _ownerAcknowledgement(identity);
    if (before == null) {
      return _failureCompletion(
        identity,
        code: 'local_command_owner_state_unavailable',
        message:
            'The local command owner state could not be verified before '
            'execution.',
      );
    }
    if (!before.identity.belongsTo(identity)) {
      return _failureCompletion(
        identity,
        code: 'local_command_boundary_mismatch',
        message:
            'The local command was not started because its owner identity '
            'did not match.',
      );
    }
    if (before.disposition != LocalCommandRuntimeOwnerDisposition.current) {
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
      );
    }

    final reservation = _executionAuthority.reserve(
      identity,
      ownerIsCurrent: () => _ownerIsCurrent(identity),
    );
    final permit = reservation.permit;
    if (permit == null) {
      return reservation.disposition ==
              LocalCommandReservationDisposition.ownerExpired
          ? LocalCommandCompletion.ownerExpired(
              owner: owner,
              toolCallId: request.toolCallId,
            )
          : _failureCompletion(
              identity,
              code: 'local_command_execution_busy',
              message:
                  'Another local command effect is awaiting completion or '
                  'reconciliation.',
            );
    }

    final LocalCommandRuntimeExecutionAcknowledgement acknowledgement;
    try {
      acknowledgement = await _runtimePort.execute(
        LocalCommandRuntimeExecution(
          identity: identity,
          request: request,
          effectPermit: permit,
        ),
      );
    } on LocalCommandEffectPermitExpired {
      _executionAuthority.abandonBeforeEffect(permit);
      return LocalCommandCompletion.ownerExpired(
        owner: owner,
        toolCallId: request.toolCallId,
      );
    } catch (error) {
      _executionAuthority.retainUncertainDispatch(permit);
      return _uncertainCompletion(
        identity,
        'The local command runtime failed after dispatch: $error',
      );
    }
    if (!acknowledgement.identity.belongsTo(identity)) {
      _executionAuthority.retainUncertainDispatch(permit);
      return _uncertainCompletion(
        identity,
        'The local command runtime returned a receipt for another operation.',
      );
    }

    switch (acknowledgement.disposition) {
      case LocalCommandRuntimeExecutionDisposition.ownerExpired:
        if (permit.receipt == null) {
          _executionAuthority.abandonBeforeEffect(permit);
          return LocalCommandCompletion.ownerExpired(
            owner: owner,
            toolCallId: request.toolCallId,
          );
        }
        return _uncertainCompletion(
          identity,
          acknowledgement.message ?? _uncertainMessage,
        );
      case LocalCommandRuntimeExecutionDisposition.effectUncertain:
        _executionAuthority.retainUncertainDispatch(permit);
        return _uncertainCompletion(
          identity,
          acknowledgement.message ?? _uncertainMessage,
        );
      case LocalCommandRuntimeExecutionDisposition.completed:
      case LocalCommandRuntimeExecutionDisposition.rejected:
        break;
    }

    final result = acknowledgement.result;
    if (result == null || result.toolName != identity.toolName) {
      _executionAuthority.retainUncertainDispatch(permit);
      return _uncertainCompletion(
        identity,
        'The local command runtime returned a result for another tool.',
      );
    }
    if (acknowledgement.disposition ==
            LocalCommandRuntimeExecutionDisposition.rejected &&
        result.isSuccess) {
      _executionAuthority.retainUncertainDispatch(permit);
      return _uncertainCompletion(
        identity,
        'The local command runtime returned a successful result for a '
        'rejected launch.',
      );
    }
    if (acknowledgement.disposition ==
            LocalCommandRuntimeExecutionDisposition.rejected &&
        permit.receipt == null) {
      _executionAuthority.abandonBeforeEffect(permit);
      return LocalCommandCompletion.completed(
        owner: owner,
        toolCallId: request.toolCallId,
        value: result,
      );
    }
    if (permit.receipt == null) {
      _executionAuthority.retainUncertainDispatch(permit);
      return _uncertainCompletion(
        identity,
        'The local command runtime bypassed its exact launch permit.',
      );
    }
    if (!_executionAuthority.prepareSettlement(permit)) {
      return _uncertainCompletion(
        identity,
        'The local command owner changed while execution was in flight.',
      );
    }
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: result,
      effectDisposition: LocalCommandEffectDisposition.settlementRequired,
      effectSettlement: LocalCommandEffectSettlement(
        identity: identity,
        settle: () => _executionAuthority.accept(permit),
      ),
    );
  }

  bool _ownerIsCurrent(LocalCommandOperationIdentity identity) {
    final acknowledgement = _ownerAcknowledgement(identity);
    return acknowledgement != null &&
        acknowledgement.identity.belongsTo(identity) &&
        acknowledgement.disposition ==
            LocalCommandRuntimeOwnerDisposition.current;
  }

  LocalCommandRuntimeOwnerAcknowledgement? _ownerAcknowledgement(
    LocalCommandOperationIdentity identity,
  ) {
    try {
      return _runtimePort.acknowledgeOwner(identity);
    } catch (_) {
      return null;
    }
  }

  LocalCommandCompletion<McpToolResult> _uncertainCompletion(
    LocalCommandOperationIdentity identity,
    String message,
  ) {
    return _failureCompletion(
      identity,
      code: 'local_command_effect_uncertain',
      message: message,
      effectDisposition: LocalCommandEffectDisposition.effectUncertain,
      nextAction:
          'Inspect process and filesystem state with read-only tools before '
          'retrying this command.',
    );
  }

  LocalCommandCompletion<McpToolResult> _failureCompletion(
    LocalCommandOperationIdentity identity, {
    required String code,
    required String message,
    LocalCommandEffectDisposition effectDisposition =
        LocalCommandEffectDisposition.noEffect,
    String? nextAction,
  }) {
    return LocalCommandCompletion.completed(
      owner: identity.owner,
      toolCallId: identity.toolCallId,
      effectDisposition: effectDisposition,
      value: McpToolResult(
        toolName: identity.toolName,
        result: jsonEncode({
          'ok': false,
          'code': code,
          'error': message,
          'required_action': ?nextAction,
        }),
        isSuccess: false,
        errorMessage: message,
      ),
    );
  }
}
