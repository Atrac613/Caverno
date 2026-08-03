import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/ask_user_question_policy.dart';
import '../../domain/services/ask_user_question_turn_cache.dart';
import '../../domain/services/ask_user_question_ui_contract.dart';
import '../../domain/services/tool_terminal_response_policy.dart';

export '../../domain/services/ask_user_question_policy.dart';
export '../../domain/services/ask_user_question_ui_contract.dart';

/// Production bridge from exact tool calls to owner-keyed pending UI state.
final class AskUserQuestionToolRuntimeAdapter {
  factory AskUserQuestionToolRuntimeAdapter({
    required AskUserQuestionTurnCache cache,
    required ToolTerminalResponsePolicy terminalResponsePolicy,
    required AskUserQuestionOwnerCurrentCallback ownerIsCurrent,
    required AskUserQuestionUiStartCallback startQuestion,
    required AskUserQuestionUiCancelCallback cancelQuestion,
  }) {
    final uiPort = _AskUserQuestionUiPortAdapter(
      ownerIsCurrent: ownerIsCurrent,
      startQuestion: startQuestion,
      cancelQuestion: cancelQuestion,
    );
    return AskUserQuestionToolRuntimeAdapter._(
      cache: cache,
      uiPort: uiPort,
      policy: AskUserQuestionPolicy(
        port: uiPort,
        cache: cache,
        terminalResponsePolicy: terminalResponsePolicy,
      ),
    );
  }

  const AskUserQuestionToolRuntimeAdapter._({
    required AskUserQuestionTurnCache cache,
    required _AskUserQuestionUiPortAdapter uiPort,
    required AskUserQuestionPolicy policy,
  }) : _cache = cache,
       _uiPort = uiPort,
       _policy = policy;

  final AskUserQuestionTurnCache _cache;
  final _AskUserQuestionUiPortAdapter _uiPort;
  final AskUserQuestionPolicy _policy;

  Future<McpToolResult> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    ConversationWorkflowTask? savedTask,
  }) async {
    final input = AskUserQuestionToolInput(
      owner: owner,
      toolCallId: toolCall.id,
      toolName: toolCall.name,
      arguments: toolCall.arguments,
      savedTask: savedTask,
    );
    if (!_uiPort.isCurrent(input.identity)) {
      _cache.removeOwner(owner);
      return _failure(
        'The ask_user_question turn expired before the question completed.',
      );
    }
    try {
      final result = await _policy.handle(input);
      if (!_uiPort.isCurrent(input.identity)) {
        _cache.removeOwner(owner);
        return _failure(
          'The ask_user_question turn expired before the question completed.',
        );
      }
      return result;
    } on _AskUserQuestionUiBoundaryException catch (error) {
      if (error.disposition == _AskUserQuestionUiFailure.ownerRetired) {
        _cache.removeOwner(owner);
        return _failure(
          'The ask_user_question turn expired before the question completed.',
        );
      }
      if (error.disposition == _AskUserQuestionUiFailure.effectUncertain) {
        return _failure(
          'The ask_user_question UI completion could not be acknowledged '
          'safely.',
        );
      }
      return _failure(
        'The ask_user_question UI boundary returned another pending question.',
      );
    }
  }

  AskUserQuestionOwnerRetirementAcknowledgement retireOwner(
    ChatTurnOwner owner,
  ) {
    _cache.removeOwner(owner);
    return _uiPort.retireOwner(owner);
  }

  static McpToolResult _failure(String message) {
    return McpToolResult(
      toolName: askUserQuestionToolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }
}

final class _AskUserQuestionUiPortAdapter implements AskUserQuestionPort {
  _AskUserQuestionUiPortAdapter({
    required AskUserQuestionOwnerCurrentCallback ownerIsCurrent,
    required AskUserQuestionUiStartCallback startQuestion,
    required AskUserQuestionUiCancelCallback cancelQuestion,
  }) : _ownerIsCurrent = ownerIsCurrent,
       _startQuestion = startQuestion,
       _cancelQuestion = cancelQuestion;

  final AskUserQuestionOwnerCurrentCallback _ownerIsCurrent;
  final AskUserQuestionUiStartCallback _startQuestion;
  final AskUserQuestionUiCancelCallback _cancelQuestion;
  final Map<ChatTurnOwner, _ActiveAskUserQuestion> _activeByOwner = {};
  final Set<ChatTurnOwner> _retiredOwners = {};

  bool isCurrent(AskUserQuestionOperationIdentity identity) {
    return _isCurrent(identity);
  }

  @override
  Future<AskUserQuestionPortResult> ask(
    AskUserQuestionOperationIdentity identity,
    AskUserQuestionRequest request,
  ) async {
    _requireCurrent(identity);
    if (_activeByOwner.containsKey(identity.owner)) {
      return AskUserQuestionPortResult(identity: identity);
    }

    late final AskUserQuestionUiStartAcknowledgement start;
    try {
      start = _startQuestion(identity, request);
    } catch (_) {
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.effectUncertain,
      );
    }
    if (start.identity != identity) {
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.boundaryMismatch,
      );
    }
    if (start.disposition == AskUserQuestionUiStartDisposition.ownerRetired) {
      _retiredOwners.add(identity.owner);
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.ownerRetired,
      );
    }
    if (start.disposition == AskUserQuestionUiStartDisposition.alreadyPending) {
      return AskUserQuestionPortResult(identity: identity);
    }

    final pendingQuestionId = start.pendingQuestionId?.trim() ?? '';
    final completionFuture = start.completion;
    if (pendingQuestionId.isEmpty || completionFuture == null) {
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.boundaryMismatch,
      );
    }
    final active = _ActiveAskUserQuestion(
      identity: identity,
      pendingQuestionId: pendingQuestionId,
    );
    _activeByOwner[identity.owner] = active;
    if (!_isCurrent(identity)) {
      _cancelActive(active);
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.ownerRetired,
      );
    }

    late final AskUserQuestionUiCompletionAcknowledgement completion;
    try {
      completion = await completionFuture;
    } catch (_) {
      _cancelActive(active);
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.effectUncertain,
      );
    }
    if (!_isCurrent(identity)) {
      _removeExact(active);
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.ownerRetired,
      );
    }
    if (!_isActive(active) ||
        !completion.belongsTo(identity, pendingQuestionId)) {
      _cancelActive(active);
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.boundaryMismatch,
      );
    }
    _removeExact(active);

    return switch (completion.disposition) {
      AskUserQuestionUiCompletionDisposition.answered =>
        completion.answer == null
            ? throw const _AskUserQuestionUiBoundaryException(
                _AskUserQuestionUiFailure.boundaryMismatch,
              )
            : AskUserQuestionPortResult(
                identity: identity,
                answer: completion.answer,
              ),
      AskUserQuestionUiCompletionDisposition.cancelled =>
        AskUserQuestionPortResult(identity: identity),
      AskUserQuestionUiCompletionDisposition.ownerRetired =>
        throw const _AskUserQuestionUiBoundaryException(
          _AskUserQuestionUiFailure.ownerRetired,
        ),
      AskUserQuestionUiCompletionDisposition.effectUncertain =>
        throw const _AskUserQuestionUiBoundaryException(
          _AskUserQuestionUiFailure.effectUncertain,
        ),
    };
  }

  AskUserQuestionOwnerRetirementAcknowledgement retireOwner(
    ChatTurnOwner owner,
  ) {
    _retiredOwners.add(owner);
    final active = _activeByOwner.remove(owner);
    if (active == null) {
      return AskUserQuestionOwnerRetirementAcknowledgement(
        owner: owner,
        disposition:
            AskUserQuestionOwnerRetirementDisposition.noPendingQuestion,
      );
    }

    late final AskUserQuestionUiCancellationAcknowledgement cancellation;
    try {
      cancellation = _cancelQuestion(active.identity, active.pendingQuestionId);
    } catch (_) {
      return _retirement(
        active,
        AskUserQuestionOwnerRetirementDisposition.effectUncertain,
      );
    }
    if (!cancellation.belongsTo(active.identity, active.pendingQuestionId)) {
      return _retirement(
        active,
        AskUserQuestionOwnerRetirementDisposition.boundaryMismatch,
      );
    }
    final disposition = switch (cancellation.disposition) {
      AskUserQuestionUiCancellationDisposition.cancelled =>
        AskUserQuestionOwnerRetirementDisposition.cancelled,
      AskUserQuestionUiCancellationDisposition.alreadySettled =>
        AskUserQuestionOwnerRetirementDisposition.alreadySettled,
      AskUserQuestionUiCancellationDisposition.rejected =>
        AskUserQuestionOwnerRetirementDisposition.rejected,
      AskUserQuestionUiCancellationDisposition.effectUncertain =>
        AskUserQuestionOwnerRetirementDisposition.effectUncertain,
    };
    return _retirement(active, disposition);
  }

  void _requireCurrent(AskUserQuestionOperationIdentity identity) {
    if (!_isCurrent(identity)) {
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.ownerRetired,
      );
    }
  }

  bool _isCurrent(AskUserQuestionOperationIdentity identity) {
    if (_retiredOwners.contains(identity.owner)) return false;
    try {
      return _ownerIsCurrent(identity);
    } catch (_) {
      return false;
    }
  }

  bool _isActive(_ActiveAskUserQuestion active) {
    return _activeByOwner[active.identity.owner] == active;
  }

  void _removeExact(_ActiveAskUserQuestion active) {
    if (_isActive(active)) {
      _activeByOwner.remove(active.identity.owner);
    }
  }

  void _cancelActive(_ActiveAskUserQuestion active) {
    _removeExact(active);
    try {
      final cancellation = _cancelQuestion(
        active.identity,
        active.pendingQuestionId,
      );
      if (!cancellation.belongsTo(active.identity, active.pendingQuestionId)) {
        throw const _AskUserQuestionUiBoundaryException(
          _AskUserQuestionUiFailure.boundaryMismatch,
        );
      }
      if (cancellation.disposition ==
              AskUserQuestionUiCancellationDisposition.rejected ||
          cancellation.disposition ==
              AskUserQuestionUiCancellationDisposition.effectUncertain) {
        throw const _AskUserQuestionUiBoundaryException(
          _AskUserQuestionUiFailure.effectUncertain,
        );
      }
    } on _AskUserQuestionUiBoundaryException {
      rethrow;
    } catch (_) {
      throw const _AskUserQuestionUiBoundaryException(
        _AskUserQuestionUiFailure.effectUncertain,
      );
    }
  }

  AskUserQuestionOwnerRetirementAcknowledgement _retirement(
    _ActiveAskUserQuestion active,
    AskUserQuestionOwnerRetirementDisposition disposition,
  ) {
    return AskUserQuestionOwnerRetirementAcknowledgement(
      owner: active.identity.owner,
      identity: active.identity,
      pendingQuestionId: active.pendingQuestionId,
      disposition: disposition,
    );
  }
}

final class _ActiveAskUserQuestion {
  const _ActiveAskUserQuestion({
    required this.identity,
    required this.pendingQuestionId,
  });

  final AskUserQuestionOperationIdentity identity;
  final String pendingQuestionId;
}

enum _AskUserQuestionUiFailure {
  ownerRetired,
  boundaryMismatch,
  effectUncertain,
}

final class _AskUserQuestionUiBoundaryException implements Exception {
  const _AskUserQuestionUiBoundaryException(this.disposition);

  final _AskUserQuestionUiFailure disposition;
}
