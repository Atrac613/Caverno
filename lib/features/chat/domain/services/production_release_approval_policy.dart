import 'dart:convert';

import '../../data/datasources/git_tools.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'ask_user_question_turn_cache.dart';
import 'tool_call_execution_policy.dart';

// ChatNotifier decomposition collaborator: production-release-approval-policy

/// The immediately preceding owner message captured before a turn begins.
final class ProductionReleasePrecedingMessage {
  const ProductionReleasePrecedingMessage({
    required this.isAssistant,
    required this.content,
  });

  final bool isAssistant;
  final String content;
}

/// Immutable release-approval proof captured for one exact turn owner.
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

/// Owner-scoped approval evidence used by the command guard.
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

  ProductionReleaseApprovalEvidence evidenceFor({
    required ChatTurnOwner owner,
    required ProductionReleaseApprovalProof? capturedProof,
    required AskUserQuestionTurnCache questionResults,
  }) {
    final directlyApproved =
        capturedProof?.owner == owner && capturedProof?.approved == true;
    return ProductionReleaseApprovalEvidence(
      owner: owner,
      directlyApproved: directlyApproved,
      questionApproved: questionResults.anyResult(owner, answerApproves),
    );
  }

  ProductionReleaseApprovalDecision evaluate({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required ProductionReleaseApprovalProof? capturedProof,
    required AskUserQuestionTurnCache questionResults,
    String? currentAssistantContent,
  }) {
    final evidence = evidenceFor(
      owner: owner,
      capturedProof: capturedProof,
      questionResults: questionResults,
    );
    return ProductionReleaseApprovalDecision(
      evidence: evidence,
      guardResult: buildGuardResult(
        toolCall,
        owner: owner,
        currentAssistantContent: currentAssistantContent,
        approvalEvidence: evidence,
      ),
    );
  }

  McpToolResult? buildGuardResult(
    ToolCallInfo toolCall, {
    required ChatTurnOwner owner,
    required String? currentAssistantContent,
    required ProductionReleaseApprovalEvidence approvalEvidence,
  }) {
    final ownerApproved =
        approvalEvidence.owner == owner && approvalEvidence.approved;
    if (!isProductionReleaseCommandToolCall(toolCall) || ownerApproved) {
      return null;
    }

    final command =
        _executionPolicy.toolCommandArgument(toolCall.arguments) ?? '';
    final assistantIntent = currentAssistantContent?.trim() ?? '';
    final payload = jsonEncode({
      'ok': false,
      'code': 'production_release_explicit_approval_required',
      'error':
          'A production release command was blocked because the latest user '
          'message or ask_user_question answer did not explicitly approve '
          'production release execution.',
      'command': command,
      if (assistantIntent.isNotEmpty)
        'assistant_intent': _clipForDiagnostic(assistantIntent),
      'required_action':
          'Ask the user to explicitly approve the production release command '
          'after any dry run, then retry only after that user approval.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: true,
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

  bool answerApproves(McpToolResult answerResult) {
    if (!answerResult.isSuccess) return false;
    final decoded = _decodeJsonObject(answerResult.result);
    if (decoded == null || decoded['status'] != 'answered') return false;

    var questionText = '';
    final answerEvidence = <String>[];
    void addEvidence(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        answerEvidence.add(value.trim());
      }
    }

    final questionValue = decoded['question'];
    if (questionValue is String && questionValue.trim().isNotEmpty) {
      questionText = questionValue.trim();
    }
    addEvidence(decoded['answer']);
    addEvidence(decoded['other']);
    final selected = decoded['selected'];
    if (selected is List) {
      for (final option in selected) {
        if (option is Map) {
          addEvidence(option['label']);
          addEvidence(option['description']);
          addEvidence(option['preview']);
        } else {
          addEvidence(option);
        }
      }
    }

    if (answerEvidence.isEmpty) return false;
    if (answerEvidence.any(looksLikeExplicitProductionReleaseApproval)) {
      return true;
    }
    if (!looksLikeExplicitProductionReleaseApproval(questionText)) {
      return false;
    }
    return answerEvidence.any(looksLikeAffirmativeReleaseApprovalAnswer);
  }

  bool looksLikeExplicitProductionReleaseApproval(String content) {
    final lowerContent = content.toLowerCase();
    if (RegExp(r'^\s*(release|ship)\b').hasMatch(lowerContent)) return true;
    if (!mentionsProductionRelease(content)) return false;
    return _containsAny(lowerContent, const [
          'run',
          'execute',
          'start',
          'publish',
          'upload',
          'ship',
          'production',
          'prod',
          'go ahead',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x5b9f, 0x884c],
          [0x9032, 0x3081],
          [0x516c, 0x958b],
          [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9],
          [0x672c, 0x756a],
          [0x3057, 0x3066],
          [0x304a, 0x9858, 0x3044],
          [0x3084, 0x3063, 0x3066],
        ]);
  }

  bool looksLikeProductionReleaseApprovalPrompt(String content) {
    if (!mentionsProductionRelease(content)) return false;
    final lowerContent = content.toLowerCase();
    final asksForApproval =
        _containsAny(lowerContent, const [
          'approve',
          'approval',
          'confirm',
          'permission',
          'authorize',
          'run',
          'execute',
          'proceed',
        ]) ||
        content.contains('?') ||
        content.contains(String.fromCharCode(0xff1f)) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x627f, 0x8a8d],
          [0x8a31, 0x53ef],
          [0x5b9f, 0x884c],
          [0x9032, 0x3081],
          [0x3057, 0x307e, 0x3059, 0x304b],
        ]);
    if (!asksForApproval) return false;
    return _containsAny(lowerContent, const [
          'production',
          'prod',
          'command',
          'release',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x672c, 0x756a],
          [0x30b3, 0x30de, 0x30f3, 0x30c9],
          [0x30ea, 0x30ea, 0x30fc, 0x30b9],
        ]);
  }

  bool mentionsProductionRelease(String content) {
    final lowerContent = content.toLowerCase();
    return _containsAny(lowerContent, const [
          'release',
          'publish',
          'upload',
          'app store connect',
          'sparkle',
          's3',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x30ea, 0x30ea, 0x30fc, 0x30b9],
          [0x672c, 0x756a],
          [0x516c, 0x958b],
          [0x30a2, 0x30c3, 0x30d7, 0x30fc, 0x30c9],
        ]);
  }

  bool looksLikeAffirmativeReleaseApprovalAnswer(String content) {
    final lowerContent = content.toLowerCase();
    if (_containsAny(lowerContent, const [
      'do not',
      "don't",
      'dont',
      'no',
      'cancel',
      'decline',
      'deny',
      'reject',
      'skip',
      'stop',
      'block',
      'not release',
      'not now',
    ])) {
      return false;
    }
    return _containsAny(lowerContent, const [
          'approve',
          'approved',
          'yes',
          'go ahead',
          'proceed',
          'run',
          'execute',
          'release',
          'ship',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x627f, 0x8a8d],
          [0x306f, 0x3044],
          [0x9032, 0x3081],
          [0x5b9f, 0x884c],
          [0x516c, 0x958b],
          [0x672c, 0x756a],
          [0x304a, 0x9858, 0x3044],
          [0x3084, 0x3063, 0x3066],
        ]);
  }

  String _clipForDiagnostic(String value, {int maxLength = 240}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}...';
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) {
    return sequences.any(
      (sequence) => text.contains(String.fromCharCodes(sequence)),
    );
  }

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
