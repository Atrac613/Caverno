import '../../entities/mcp_tool_entity.dart';
import '../../entities/tool_call_info.dart';
import '../ask_user_question/ask_user_question_text_normalization.dart';
import '../local_command/local_command_tool_contract.dart';
import '../tool_loop/tool_call_execution_policy.dart';
import 'blocked_production_release_retry_contract.dart';
import 'production_release_approval_conflict_result.dart';
import 'production_release_approval_evidence_snapshot.dart';
import 'production_release_approval_token_registry.dart';
import 'production_release_blocked_result.dart';
import 'production_release_dispatch_evidence.dart';
import 'production_release_dispatch_result.dart';
import 'production_release_execution_identity.dart';

/// Stateful exact-execution gate behind the approval evidence coordinator.
final class ProductionReleaseApprovalGate {
  ProductionReleaseApprovalGate({
    String Function()? approvalTokenFactory,
    ProductionReleaseArgumentResolver? resolveExecutionArguments,
  }) : _resolveArguments = resolveExecutionArguments ?? _identityArguments,
       _tokens = ProductionReleaseApprovalTokenRegistry(
         tokenFactory: approvalTokenFactory,
       );

  static const _policy = ToolCallExecutionPolicy();
  static const _identity = ProductionReleaseExecutionIdentity();
  static const _dispatchEvidence = ProductionReleaseDispatchEvidence();

  final ProductionReleaseArgumentResolver _resolveArguments;
  final ProductionReleaseApprovalTokenRegistry _tokens;
  final _pending = <String, PendingBlockedRelease>{};

  static Map<String, dynamic> _identityArguments(ToolCallInfo toolCall) =>
      toolCall.arguments;

  PendingBlockedRelease? pendingRelease(String conversationId) =>
      _pending[conversationId];
  String? approvalToken(String conversationId) =>
      _tokens.tokenFor(conversationId);

  ({String? optionLabel, String? question}) approvalBinding(
    String? conversationId,
  ) {
    final pending = conversationId == null ? null : _pending[conversationId];
    final token = conversationId == null
        ? null
        : _tokens.tokenFor(conversationId);
    if (pending?.executionIdentity == null || token == null) {
      return (optionLabel: null, question: null);
    }
    return (
      optionLabel: productionReleaseApprovalOptionLabel(
        executionIdentity: pending!.executionIdentity!,
        approvalToken: token,
      ),
      question: _questionFor(pending),
    );
  }

  McpToolResult? buildGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required ProductionReleaseApprovalEvidenceSnapshot evidence,
    required bool isProductionRelease,
    List<ToolResultInfo> executedToolResults = const [],
  }) {
    if (!isProductionRelease) return null;
    final conversationId = evidence.conversationId;
    final command = _policy.toolCommandArgument(toolCall.arguments) ?? '';
    if (_dispatchEvidence.hasDispatched(
      toolCall: toolCall,
      executedToolResults: executedToolResults,
      resolveExecutionArguments: _resolveArguments,
    )) {
      return buildProductionReleaseAlreadyExecutedResult(
        toolName: toolCall.name,
        command: command,
      );
    }

    if (evidence.approved) {
      final pending = conversationId == null ? null : _pending[conversationId];
      if (pending == null ||
          pending.executionIdentity == null ||
          _executionIdentityFor(toolCall) != pending.executionIdentity) {
        return pending == null
            ? buildProductionReleaseBlockedResult(
                toolName: toolCall.name,
                command: command,
                assistantIntent: currentAssistantContent ?? '',
                approvalToken: _tokens.issueFor(conversationId),
              )
            : buildProductionReleaseApprovalConflictResult(
                toolName: toolCall.name,
                command: command,
                pending: pending,
              );
      }
      if (conversationId != null) removePendingRelease(conversationId);
      return null;
    }

    if (conversationId != null && command.trim().isNotEmpty) {
      final existing = _pending[conversationId];
      final resolved = _resolveArguments(toolCall);
      final executionIdentity = _identity.forToolCall(
        toolCall,
        resolvedArguments: resolved,
      );
      if (existing != null && existing.executionIdentity != executionIdentity) {
        return buildProductionReleaseApprovalConflictResult(
          toolName: toolCall.name,
          command: command,
          pending: existing,
        );
      }
      _pending.putIfAbsent(
        conversationId,
        () => PendingBlockedRelease(
          toolName: toolCall.name.trim(),
          command: command.trim(),
          executionIdentity: executionIdentity,
          workingDirectory: (resolved['working_directory'] as String?)?.trim(),
          background:
              toolCall.name.trim().toLowerCase() == 'process_start' ||
              argumentIsTruthy(resolved['background']),
        ),
      );
    }
    final token = _tokens.issueFor(conversationId);
    final binding = approvalBinding(conversationId);
    return buildProductionReleaseBlockedResult(
      toolName: toolCall.name,
      command: command,
      assistantIntent: currentAssistantContent ?? '',
      approvalToken: token,
      approvalOptionLabel: binding.optionLabel,
    );
  }

  ToolCallInfo bindPendingApprovalQuestion(
    String conversationId,
    ToolCallInfo toolCall,
  ) {
    if (toolCall.name.trim().toLowerCase() != 'ask_user_question') {
      return toolCall;
    }
    final binding = approvalBinding(conversationId);
    final label = binding.optionLabel;
    final question = binding.question;
    if (label == null || question == null) return toolCall;
    final expected = normalizeAskUserQuestionText(label);
    final offersApproval = _optionLabels(
      toolCall.arguments['options'],
    ).any((candidate) => normalizeAskUserQuestionText(candidate) == expected);
    if (!offersApproval) return toolCall;
    return ToolCallInfo(
      id: toolCall.id,
      name: toolCall.name,
      arguments: {
        'question': question,
        'help':
            'This execution summary was generated by Caverno from the blocked '
            'tool call.',
        'options': [
          {
            'id': 'approve-exact-production-release',
            'label': label,
            'description': 'Run exactly the production release shown above.',
          },
          {
            'id': 'decline-production-release',
            'label': 'Do not run this production release',
            'description': 'Keep the production release blocked.',
          },
        ],
        'allow_multiple': false,
        'allow_other': false,
      },
    );
  }

  void removePendingRelease(String conversationId) {
    _pending.remove(conversationId);
    _tokens.release(conversationId);
  }

  void clear() {
    _pending.clear();
    _tokens.clear();
  }

  String _executionIdentityFor(ToolCallInfo toolCall) => _identity.forToolCall(
    toolCall,
    resolvedArguments: _resolveArguments(toolCall),
  );

  String _questionFor(PendingBlockedRelease pending) =>
      productionReleaseApprovalQuestion(
        toolName: pending.toolName,
        command: pending.command,
        workingDirectory: pending.workingDirectory,
        background: pending.background,
      );

  Iterable<String> _optionLabels(Object? rawOptions) sync* {
    if (rawOptions is! List) return;
    for (final option in rawOptions) {
      if (option is String) {
        yield option;
      } else if (option is Map && option['label'] is String) {
        yield option['label'] as String;
      }
    }
  }
}
