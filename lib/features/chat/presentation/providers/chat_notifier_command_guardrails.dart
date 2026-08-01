// Same-library extension; see chat_notifier_git_handlers.dart for rationale.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

typedef _ReleaseProof = ({int gen, String thread, bool explicit, bool reply});
typedef _ReleaseApprovalEvidence = ({String? conversationId, bool approved});

extension ChatNotifierCommandGuardrails on ChatNotifier {
  McpToolResult? _buildProductionReleaseApprovalGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required _ReleaseApprovalEvidence approvalEvidence,
  }) {
    if (!_isProductionReleaseCommandToolCall(toolCall)) {
      return null;
    }
    if (approvalEvidence.approved) {
      return null;
    }

    final command = _toolCallExecutionPolicy.toolCommandArgument(toolCall.arguments) ?? '';
    final payload = jsonEncode({
      'ok': false,
      'code': 'production_release_explicit_approval_required',
      'error':
          'A production release command was blocked because the latest user '
          'message or ask_user_question answer did not explicitly approve '
          'production release execution.',
      'command': command,
      if ((currentAssistantContent ?? '').trim().isNotEmpty)
        'assistant_intent': _claims.clipForDiagnostic(
          currentAssistantContent!.trim(),
        ),
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

  ConversationWorkflowTask? _savedTaskForGeneration(
    int interactionGeneration,
  ) => _turnOwnerSnapshotForGeneration(interactionGeneration)?.savedTask;

  bool _isProductionReleaseCommandToolCall(ToolCallInfo toolCall) {
    final toolName = toolCall.name.trim().toLowerCase();
    if (toolName != 'local_execute_command' && toolName != 'process_start') {
      return false;
    }
    if (_toolCallExecutionPolicy.isReadOnlyCommandExecutionToolCall(toolCall)) {
      return false;
    }
    final command = _toolCallExecutionPolicy.toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return false;
    }
    return _looksLikeProductionReleaseCommand(command);
  }

  bool _looksLikeProductionReleaseCommand(String command) {
    final args = GitTools.splitArgs(command);
    if (args.isEmpty) {
      return false;
    }
    if (args.any((arg) {
      final normalized = arg.trim().toLowerCase();
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
    return args.any((arg) {
      final normalized = arg.trim().toLowerCase();
      if (normalized.isEmpty || normalized.startsWith('-')) {
        return false;
      }
      final basename = normalized.split('/').last;
      return releaseScripts.contains(basename);
    });
  }

  void _captureProof(int gen, QueuedChatMessage message, Conversation? owner) {
    final conversationId = message.conversationId;
    final conversation = conversationId == null
        ? owner
        : _conversationForId(conversationId);
    if (conversation == null) return;
    final submittedContent = message.content.trim();
    final previous = conversation.messages
        .where(
          (m) => m.role != MessageRole.system && m.content.trim().isNotEmpty,
        )
        .lastOrNull;
    _releaseApprovalSnapshots[gen] = (
      gen: gen,
      thread: conversation.id,
      explicit: _looksLikeExplicitProductionReleaseApproval(submittedContent),
      reply:
          _looksLikeAffirmativeReleaseApprovalAnswer(submittedContent) &&
          previous?.role == MessageRole.assistant &&
          _looksLikeProductionReleaseApprovalPrompt(previous!.content),
    );
  }

  _ReleaseApprovalEvidence _releaseEvidenceFor(int generation) {
    final thread = _activeResponseConversationIdForGeneration(generation);
    final direct = _releaseApprovalSnapshots[generation];
    final directlyApproved =
        direct?.gen == generation &&
        direct?.thread == thread &&
        (direct?.explicit == true || direct?.reply == true);
    final cache = _askUserQuestionTurnCache;
    final questionApproved = cache.anyResult(generation, _answerApproves);
    return (
      conversationId: thread,
      approved: thread != null && (directlyApproved || questionApproved),
    );
  }

  bool _answerApproves(McpToolResult answerResult) {
    if (!answerResult.isSuccess) {
      return false;
    }
    final decoded = decodeJsonObject(answerResult.result);
    if (decoded == null || decoded['status'] != 'answered') {
      return false;
    }

    String questionText = '';
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

    if (answerEvidence.isEmpty) {
      return false;
    }
    if (answerEvidence.any(_looksLikeExplicitProductionReleaseApproval)) {
      return true;
    }
    if (!_looksLikeExplicitProductionReleaseApproval(questionText)) {
      return false;
    }
    return answerEvidence.any(_looksLikeAffirmativeReleaseApprovalAnswer);
  }

  bool _looksLikeExplicitProductionReleaseApproval(String content) {
    final lowerContent = content.toLowerCase();
    if (RegExp(r'^\s*(release|ship)\b').hasMatch(lowerContent)) {
      return true;
    }
    if (!_mentionsProductionRelease(content)) {
      return false;
    }
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

  bool _looksLikeProductionReleaseApprovalPrompt(String content) {
    if (!_mentionsProductionRelease(content)) {
      return false;
    }
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
    if (!asksForApproval) {
      return false;
    }
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

  bool _mentionsProductionRelease(String content) {
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
          [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9],
        ]);
  }

  bool _looksLikeAffirmativeReleaseApprovalAnswer(String content) {
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
}
