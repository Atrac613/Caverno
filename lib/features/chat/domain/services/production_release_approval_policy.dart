import 'dart:convert';

import '../../data/datasources/git_tools.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'ask_user_question_turn_cache.dart';
import 'production_release_approval_wording_predicates.dart';
import 'production_release_blocked_result.dart';
import 'tool_call_execution_policy.dart';

export 'production_release_blocked_result.dart'
    show
        productionReleaseApprovalRequiredActionFor,
        productionReleaseApprovalTokenLength;

// ChatNotifier decomposition collaborator: production-release-approval-policy

final class ProductionReleasePrecedingMessage {
  const ProductionReleasePrecedingMessage({
    required this.isAssistant,
    required this.content,
  });

  final bool isAssistant;
  final String content;
}

final class ProductionReleaseApprovalProof {
  const ProductionReleaseApprovalProof({
    required this.owner,
    required this.explicitApproval,
    required this.affirmativePromptReply,
  });

  final ChatTurnOwner owner;
  final bool explicitApproval;
  final bool affirmativePromptReply;

  bool get approved => explicitApproval || affirmativePromptReply;
}

final class ProductionReleaseApprovalEvidence {
  const ProductionReleaseApprovalEvidence({
    required this.owner,
    required this.directlyApproved,
    required this.questionApproved,
  });

  final ChatTurnOwner owner;
  final bool directlyApproved;
  final bool questionApproved;

  bool get approved => directlyApproved || questionApproved;
}

/// Complete release-guard decision for one tool call.
final class ProductionReleaseApprovalDecision {
  const ProductionReleaseApprovalDecision({
    required this.evidence,
    required this.guardResult,
  });

  final ProductionReleaseApprovalEvidence evidence;
  final McpToolResult? guardResult;
}

/// Recognizes production releases and requires capture-time owner approval.
final class ProductionReleaseApprovalPolicy {
  const ProductionReleaseApprovalPolicy();

  static const ToolCallExecutionPolicy _executionPolicy =
      ToolCallExecutionPolicy();
  static const ProductionReleaseApprovalWordingPredicates _wording =
      ProductionReleaseApprovalWordingPredicates();

  ProductionReleaseApprovalProof captureProof({
    required ChatTurnOwner owner,
    required String submittedUserContent,
    required ProductionReleasePrecedingMessage? precedingOwnerMessage,
  }) {
    final submitted = submittedUserContent.trim();
    return ProductionReleaseApprovalProof(
      owner: owner,
      explicitApproval: looksLikeExplicitProductionReleaseApproval(submitted),
      affirmativePromptReply:
          looksLikeAffirmativeReleaseApprovalAnswer(submitted) &&
          precedingOwnerMessage?.isAssistant == true &&
          looksLikeProductionReleaseApprovalPrompt(
            precedingOwnerMessage!.content,
          ),
    );
  }

  /// Evidence for one owner, decided by [approvalToken] alone.
  ///
  /// `directlyApproved` is deliberately always false: approving a production
  /// release from the words of a chat message is what this milestone removes.
  /// The captured prose proof is still computed by the caller, but only so a
  /// divergence can be recorded -- never to grant.
  ProductionReleaseApprovalEvidence evidenceFor({
    required ChatTurnOwner owner,
    required ProductionReleaseApprovalProof? capturedProof,
    required AskUserQuestionTurnCache questionResults,
    required String approvalToken,
  }) {
    return ProductionReleaseApprovalEvidence(
      owner: owner,
      directlyApproved: false,
      questionApproved: questionResults.anyEntry(
        owner,
        (offeredOptionLabels, result) => answerApprovesToken(
          offeredOptionLabels: offeredOptionLabels,
          answerResult: result,
          token: approvalToken,
        ),
      ),
    );
  }

  ProductionReleaseApprovalDecision evaluate({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required ProductionReleaseApprovalProof? capturedProof,
    required AskUserQuestionTurnCache questionResults,
    required String approvalToken,
    String? currentAssistantContent,
  }) {
    final evidence = evidenceFor(
      owner: owner,
      capturedProof: capturedProof,
      questionResults: questionResults,
      approvalToken: approvalToken,
    );
    return ProductionReleaseApprovalDecision(
      evidence: evidence,
      guardResult: buildGuardResult(
        toolCall,
        owner: owner,
        currentAssistantContent: currentAssistantContent,
        approvalEvidence: evidence,
        approvalToken: approvalToken,
      ),
    );
  }

  McpToolResult? buildGuardResult(
    ToolCallInfo toolCall, {
    required ChatTurnOwner owner,
    required String? currentAssistantContent,
    required ProductionReleaseApprovalEvidence approvalEvidence,
    required String approvalToken,
  }) {
    final ownerApproved =
        approvalEvidence.owner == owner && approvalEvidence.approved;
    if (!isProductionReleaseCommandToolCall(toolCall) || ownerApproved) {
      return null;
    }
    return buildProductionReleaseBlockedResult(
      toolName: toolCall.name,
      command: _executionPolicy.toolCommandArgument(toolCall.arguments) ?? '',
      assistantIntent: currentAssistantContent ?? '',
      approvalToken: approvalToken,
    );
  }

  bool isProductionReleaseCommandToolCall(ToolCallInfo toolCall) {
    final toolName = toolCall.name.trim().toLowerCase();
    if (toolName != 'local_execute_command' && toolName != 'process_start') {
      return false;
    }
    if (_executionPolicy.isReadOnlyCommandExecutionToolCall(toolCall)) {
      return false;
    }
    final command = _executionPolicy.toolCommandArgument(toolCall.arguments);
    return command != null && looksLikeProductionReleaseCommand(command);
  }

  bool looksLikeProductionReleaseCommand(String command) {
    final args = GitTools.splitArgs(command);
    if (args.isEmpty) return false;
    if (args.any((argument) {
      final normalized = argument.trim().toLowerCase();
      return normalized == '--dry-run' ||
          normalized == '-n' ||
          normalized == '--help' ||
          normalized == '-h';
    })) {
      return false;
    }
    const releaseScripts = {
      'release_ios_macos.sh',
      'build_macos_sparkle_release.sh',
      'publish_macos_sparkle_release.sh',
    };
    return args.any((argument) {
      final normalized = argument.trim().toLowerCase();
      if (normalized.isEmpty || normalized.startsWith('-')) return false;
      return releaseScripts.contains(normalized.split('/').last);
    });
  }

  /// Whether one recorded answer approves the release identified by [token].
  ///
  /// Reads no natural language. The verdict is: the harness issued this token,
  /// exactly one of the options actually offered carried it, and the user
  /// selected an option carrying it.
  ///
  /// The "exactly one offered" clause is the part that matters. The model sees
  /// the token in the blocked-release result, so nothing stops it from
  /// attaching the token to both the approving and the declining option -- at
  /// which point a decline would be reported as a selection carrying the
  /// token. Requiring the token to identify a single option makes that
  /// ambiguity a refusal rather than an approval.
  ///
  /// Free text does not approve. `other` is what the user typed rather than
  /// what they picked, so honouring it would put a wording verdict back in the
  /// path through the side door.
  bool answerApprovesToken({
    required Set<String> offeredOptionLabels,
    required McpToolResult answerResult,
    required String token,
  }) {
    final normalizedToken = token.trim().toLowerCase();
    if (normalizedToken.isEmpty) return false;
    if (!answerResult.isSuccess) return false;
    final decoded = _decodeJsonObject(answerResult.result);
    if (decoded == null || decoded['status'] != 'answered') return false;

    final carryingOffered = offeredOptionLabels.where(
      (label) => label.toLowerCase().contains(normalizedToken),
    );
    if (carryingOffered.length != 1) return false;

    final selected = decoded['selected'];
    if (selected is! List) return false;
    for (final option in selected) {
      final label = option is Map ? option['label'] : option;
      if (label is String && label.toLowerCase().contains(normalizedToken)) {
        return true;
      }
    }
    return false;
  }

  /// Legacy wording-based verdicts, kept for shadow comparison only.
  ///
  /// Do not grant approval from any of these. See [answerApprovesToken], and
  /// [ProductionReleaseApprovalWordingPredicates] for why they are wrong.
  bool answerApproves(McpToolResult answerResult) =>
      _wording.answerApproves(answerResult);

  bool looksLikeExplicitProductionReleaseApproval(String content) =>
      _wording.looksLikeExplicitProductionReleaseApproval(content);

  bool looksLikeProductionReleaseApprovalPrompt(String content) =>
      _wording.looksLikeProductionReleaseApprovalPrompt(content);

  bool mentionsProductionRelease(String content) =>
      _wording.mentionsProductionRelease(content);

  bool looksLikeAffirmativeReleaseApprovalAnswer(String content) =>
      _wording.looksLikeAffirmativeReleaseApprovalAnswer(content);

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
