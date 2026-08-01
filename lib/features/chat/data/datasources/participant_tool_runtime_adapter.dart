import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/participant_tool_executor.dart';
import '../../domain/services/participant_tool_policy.dart';
import '../../domain/services/turn_tool_approval_coordinator.dart';
import 'participant_tool_runtime_contract.dart';

export 'participant_tool_runtime_contract.dart';

/// Production callback bridge for participant-owned read-only tool calls.
final class ParticipantToolRuntimeAdapter {
  const ParticipantToolRuntimeAdapter({
    required ParticipantToolApprovalCallback resolveApproval,
    required ParticipantToolExecutionCallback execute,
    required ParticipantToolActivityCallback projectActivity,
    required ParticipantToolTaintCallback recordTaint,
  }) : _resolveApproval = resolveApproval,
       _execute = execute,
       _projectActivity = projectActivity,
       _recordTaint = recordTaint;

  final ParticipantToolApprovalCallback _resolveApproval;
  final ParticipantToolExecutionCallback _execute;
  final ParticipantToolActivityCallback _projectActivity;
  final ParticipantToolTaintCallback _recordTaint;

  List<Map<String, dynamic>> definitionsFor(ParticipantToolSession session) {
    if (!session.participant.toolsEnabled ||
        !session.supportsToolAwareRequests) {
      return const <Map<String, dynamic>>[];
    }
    return List<Map<String, dynamic>>.unmodifiable(
      const ParticipantToolPolicy().filterDefinitions(
        session.availableDefinitions,
      ),
    );
  }

  Future<ParticipantToolRuntimeCompletion> handle(
    ParticipantToolSession session,
    ToolCallInfo toolCall,
  ) async {
    final input = ParticipantToolRuntimeInput(
      session: session,
      toolCall: toolCall,
    );
    final bridge = _ParticipantToolRuntimeBridge(
      input: input,
      resolveApproval: _resolveApproval,
      execute: _execute,
      projectActivity: _projectActivity,
      recordTaint: _recordTaint,
    );
    final executor = ParticipantToolExecutor(
      approvalPort: bridge,
      executionPort: bridge,
      activityPort: bridge,
      taintPort: bridge,
    );
    McpToolResult result;
    try {
      result = await executor.execute(input.session, input.toToolCall());
    } catch (error) {
      result = bridge.failureFor(error);
    }
    return ParticipantToolRuntimeCompletion(
      identity: input.identity,
      disposition: bridge.classify(result),
      result: result,
    );
  }
}

final class _ParticipantToolRuntimeBridge
    implements
        ParticipantToolApprovalPort,
        ParticipantToolExecutionPort,
        ParticipantToolActivityPort,
        ParticipantToolTaintPort {
  _ParticipantToolRuntimeBridge({
    required this.input,
    required ParticipantToolApprovalCallback resolveApproval,
    required ParticipantToolExecutionCallback execute,
    required ParticipantToolActivityCallback projectActivity,
    required ParticipantToolTaintCallback recordTaint,
  }) : _resolveApproval = resolveApproval,
       _execute = execute,
       _projectActivity = projectActivity,
       _recordTaint = recordTaint;

  final ParticipantToolRuntimeInput input;
  final ParticipantToolApprovalCallback _resolveApproval;
  final ParticipantToolExecutionCallback _execute;
  final ParticipantToolActivityCallback _projectActivity;
  final ParticipantToolTaintCallback _recordTaint;

  ParticipantToolRuntimeDisposition? _observedDisposition;
  bool _executionDispatched = false;
  bool _executionCompleted = false;
  bool _effectCertifiedAbsent = false;

  @override
  Future<ParticipantToolApprovalResult> resolve(
    ParticipantToolApprovalRequest request,
  ) async {
    if (!_approvalMatches(request)) {
      _observe(ParticipantToolRuntimeDisposition.boundaryMismatch);
      return _approvalFailure(
        request,
        ParticipantToolRuntimeDisposition.boundaryMismatch,
      );
    }
    final ParticipantToolApprovalAcknowledgement acknowledgement;
    try {
      acknowledgement = await _resolveApproval(
        ParticipantToolRuntimeApprovalRequest(
          identity: input.identity,
          request: request,
        ),
      );
    } catch (_) {
      _observe(ParticipantToolRuntimeDisposition.effectUncertain);
      return _approvalFailure(
        request,
        ParticipantToolRuntimeDisposition.effectUncertain,
      );
    }
    if (acknowledgement.identity != input.identity) {
      _observe(ParticipantToolRuntimeDisposition.boundaryMismatch);
      return _approvalFailure(
        request,
        ParticipantToolRuntimeDisposition.boundaryMismatch,
      );
    }
    return switch (acknowledgement.disposition) {
      ParticipantToolApprovalDisposition.resolved =>
        acknowledgement.outcome == null ||
                !_approvalOutcomeMatches(acknowledgement.outcome!)
            ? _malformedApproval(request)
            : ParticipantToolApprovalResult(
                scope: input.identity.scope,
                outcome: acknowledgement.outcome!,
              ),
      ParticipantToolApprovalDisposition.ownerExpired => _approvalFailure(
        request,
        ParticipantToolRuntimeDisposition.ownerExpired,
      ),
      ParticipantToolApprovalDisposition.effectUncertain => _approvalFailure(
        request,
        ParticipantToolRuntimeDisposition.effectUncertain,
      ),
    };
  }

  @override
  Future<ParticipantToolExecutionResult> execute(
    ParticipantToolExecutionRequest request,
  ) async {
    if (!_executionMatches(request)) {
      _failBoundary('Participant execution request identity mismatch.');
    }
    _executionDispatched = true;
    final ParticipantToolExecutionAcknowledgement acknowledgement;
    try {
      acknowledgement = await _execute(
        ParticipantToolRuntimeExecutionRequest(
          identity: input.identity,
          arguments: request.arguments,
        ),
      );
    } catch (_) {
      _observe(ParticipantToolRuntimeDisposition.effectUncertain);
      return _uncertainExecution();
    }
    if (acknowledgement.identity != input.identity) {
      _observe(ParticipantToolRuntimeDisposition.effectUncertain);
      return _uncertainExecution();
    }
    return _mapExecutionAcknowledgement(acknowledgement);
  }

  @override
  ParticipantToolScopeAcknowledgement update(
    ParticipantToolActivityUpdate update,
  ) {
    final isValidName =
        update.activeToolName.isEmpty ||
        update.activeToolName == input.identity.toolName;
    if (update.scope != input.identity.scope || !isValidName) {
      _failBoundary('Participant activity request identity mismatch.');
    }
    final request = ParticipantToolRuntimeActivityRequest(
      identity: input.identity,
      activeToolName: update.activeToolName,
    );
    final ParticipantToolActivityAcknowledgement acknowledgement;
    try {
      acknowledgement = _projectActivity(request);
    } catch (_) {
      _failUncertain('Participant activity acknowledgement failed.');
    }
    if (acknowledgement.identity != input.identity ||
        acknowledgement.activeToolName != update.activeToolName) {
      if (_executionDispatched) {
        _failUncertain('Participant activity acknowledgement mismatch.');
      }
      _failBoundary('Participant activity acknowledgement mismatch.');
    }
    switch (acknowledgement.disposition) {
      case ParticipantToolActivityDisposition.applied:
        break;
      case ParticipantToolActivityDisposition.rejected:
        _fail(
          _executionDispatched
              ? ParticipantToolRuntimeDisposition.effectUncertain
              : ParticipantToolRuntimeDisposition.rejected,
          'Participant activity projection was rejected.',
        );
      case ParticipantToolActivityDisposition.ownerExpired:
        if (_effectCertifiedAbsent) break;
        _fail(
          _executionDispatched
              ? ParticipantToolRuntimeDisposition.effectUncertain
              : ParticipantToolRuntimeDisposition.ownerExpired,
          'The participant tool owner expired.',
        );
      case ParticipantToolActivityDisposition.effectUncertain:
        _failUncertain('Participant activity projection is uncertain.');
    }
    return ParticipantToolScopeAcknowledgement(scope: input.identity.scope);
  }

  @override
  ParticipantToolScopeAcknowledgement record(ParticipantToolTaintEvent event) {
    if (event.scope != input.identity.scope ||
        event.result.toolName != input.identity.toolName ||
        !_executionCompleted) {
      _failUncertain('Participant taint request identity mismatch.');
    }
    final request = ParticipantToolRuntimeTaintRequest(
      identity: input.identity,
      result: event.result,
    );
    final ParticipantToolTaintAcknowledgement acknowledgement;
    try {
      acknowledgement = _recordTaint(request);
    } catch (_) {
      _failUncertain('Participant taint acknowledgement failed.');
    }
    if (acknowledgement.identity != input.identity ||
        acknowledgement.resultFingerprint != request.resultFingerprint) {
      _failUncertain('Participant taint acknowledgement mismatch.');
    }
    switch (acknowledgement.disposition) {
      case ParticipantToolTaintDisposition.recorded:
        break;
      case ParticipantToolTaintDisposition.rejected:
      case ParticipantToolTaintDisposition.effectUncertain:
        _failUncertain('Participant taint recording is uncertain.');
      case ParticipantToolTaintDisposition.ownerExpired:
        if (!_effectCertifiedAbsent) {
          _failUncertain('Participant taint recording is uncertain.');
        }
    }
    return ParticipantToolScopeAcknowledgement(scope: input.identity.scope);
  }

  ParticipantToolExecutionResult _mapExecutionAcknowledgement(
    ParticipantToolExecutionAcknowledgement acknowledgement,
  ) {
    final result = acknowledgement.result;
    switch (acknowledgement.disposition) {
      case ParticipantToolExecutionDisposition.completed:
        if (result == null || result.toolName != input.identity.toolName) {
          _observe(ParticipantToolRuntimeDisposition.effectUncertain);
          return _uncertainExecution();
        }
        _executionCompleted = true;
        return ParticipantToolExecutionResult(
          scope: input.identity.scope,
          result: result,
        );
      case ParticipantToolExecutionDisposition.rejected:
        if (result == null ||
            result.isSuccess ||
            result.toolName != input.identity.toolName) {
          _observe(ParticipantToolRuntimeDisposition.effectUncertain);
          return _uncertainExecution();
        }
        _observe(ParticipantToolRuntimeDisposition.rejected);
        _executionCompleted = true;
        return ParticipantToolExecutionResult(
          scope: input.identity.scope,
          result: result,
        );
      case ParticipantToolExecutionDisposition.ownerExpiredBeforeEffect:
        _observe(ParticipantToolRuntimeDisposition.ownerExpired);
        _executionCompleted = true;
        _effectCertifiedAbsent = true;
        return ParticipantToolExecutionResult(
          scope: input.identity.scope,
          result: _failure(
            ParticipantToolRuntimeDisposition.ownerExpired,
            'The participant tool owner expired before execution.',
          ),
        );
      case ParticipantToolExecutionDisposition.effectUncertain:
        _observe(ParticipantToolRuntimeDisposition.effectUncertain);
        return _uncertainExecution();
    }
  }

  ParticipantToolApprovalResult _malformedApproval(
    ParticipantToolApprovalRequest request,
  ) {
    _observe(ParticipantToolRuntimeDisposition.boundaryMismatch);
    return _approvalFailure(
      request,
      ParticipantToolRuntimeDisposition.boundaryMismatch,
    );
  }

  ParticipantToolApprovalResult _approvalFailure(
    ParticipantToolApprovalRequest request,
    ParticipantToolRuntimeDisposition disposition,
  ) {
    _observe(disposition);
    return ParticipantToolApprovalResult(
      scope: input.identity.scope,
      outcome: ToolApprovalOutcome.denied(
        denialResult: _failure(disposition, _message(disposition)),
      ),
    );
  }

  ParticipantToolExecutionResult _uncertainExecution() {
    return ParticipantToolExecutionResult(
      scope: input.identity.scope,
      result: _failure(
        ParticipantToolRuntimeDisposition.effectUncertain,
        _message(ParticipantToolRuntimeDisposition.effectUncertain),
      ),
    );
  }

  bool _approvalMatches(ParticipantToolApprovalRequest request) {
    final coordinator = request.coordinatorRequest;
    final reviewedArguments = coordinator.arguments['toolArguments'];
    return request.scope == input.identity.scope &&
        coordinator.owner == input.identity.owner &&
        coordinator.toolCallId == input.identity.toolCallId &&
        coordinator.toolName == input.identity.toolName &&
        coordinator.arguments['participantId'] ==
            input.identity.participantId &&
        reviewedArguments is Map<String, dynamic> &&
        participantToolArgumentDigest(request.manualArguments) ==
            input.identity.argumentDigest &&
        participantToolArgumentDigest(reviewedArguments) ==
            input.identity.argumentDigest;
  }

  bool _approvalOutcomeMatches(ToolApprovalOutcome outcome) {
    final denial = outcome.denialResult;
    return denial == null || denial.toolName == input.identity.toolName;
  }

  bool _executionMatches(ParticipantToolExecutionRequest request) {
    return request.scope == input.identity.scope &&
        request.toolCallId == input.identity.toolCallId &&
        request.toolName == input.identity.toolName &&
        participantToolArgumentDigest(request.arguments) ==
            input.identity.argumentDigest;
  }

  ParticipantToolRuntimeDisposition classify(McpToolResult result) {
    final observed = _observedDisposition;
    if (observed != null) return observed;
    return result.isSuccess
        ? ParticipantToolRuntimeDisposition.completed
        : ParticipantToolRuntimeDisposition.rejected;
  }

  McpToolResult failureFor(Object error) {
    final disposition =
        _observedDisposition ??
        (_executionDispatched
            ? ParticipantToolRuntimeDisposition.effectUncertain
            : ParticipantToolRuntimeDisposition.rejected);
    _observe(disposition);
    return _failure(disposition, '${_message(disposition)} $error');
  }

  Never _failBoundary(String message) =>
      _fail(ParticipantToolRuntimeDisposition.boundaryMismatch, message);

  Never _failUncertain(String message) =>
      _fail(ParticipantToolRuntimeDisposition.effectUncertain, message);

  Never _fail(ParticipantToolRuntimeDisposition disposition, String message) {
    _observe(disposition);
    throw StateError(message);
  }

  void _observe(ParticipantToolRuntimeDisposition disposition) {
    final current = _observedDisposition;
    if (current == ParticipantToolRuntimeDisposition.effectUncertain) return;
    if (disposition == ParticipantToolRuntimeDisposition.effectUncertain ||
        current == null ||
        disposition == ParticipantToolRuntimeDisposition.boundaryMismatch) {
      _observedDisposition = disposition;
    }
  }

  McpToolResult _failure(
    ParticipantToolRuntimeDisposition disposition,
    String message,
  ) {
    final code = switch (disposition) {
      ParticipantToolRuntimeDisposition.ownerExpired => 'turn_owner_expired',
      ParticipantToolRuntimeDisposition.effectUncertain =>
        'participant_tool_effect_uncertain',
      ParticipantToolRuntimeDisposition.boundaryMismatch =>
        'participant_tool_boundary_mismatch',
      ParticipantToolRuntimeDisposition.rejected => 'participant_tool_rejected',
      ParticipantToolRuntimeDisposition.completed => throw StateError(
        'Completed participant tools do not use failure results.',
      ),
    };
    return McpToolResult(
      toolName: input.identity.toolName,
      result: jsonEncode({
        'ok': false,
        'code': code,
        'error': message,
        'next_action': 'Retry the participant tool in the current turn.',
      }),
      isSuccess: false,
      errorMessage: message,
    );
  }

  String _message(ParticipantToolRuntimeDisposition disposition) =>
      switch (disposition) {
        ParticipantToolRuntimeDisposition.ownerExpired =>
          'The participant tool owner expired.',
        ParticipantToolRuntimeDisposition.effectUncertain =>
          'The participant tool effect could not be verified.',
        ParticipantToolRuntimeDisposition.boundaryMismatch =>
          'The participant tool acknowledgement identity did not match.',
        ParticipantToolRuntimeDisposition.rejected =>
          'The participant tool request was rejected.',
        ParticipantToolRuntimeDisposition.completed =>
          'The participant tool completed.',
      };
}
