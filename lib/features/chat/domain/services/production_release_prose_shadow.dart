import '../entities/chat_turn_owner.dart';
import '../entities/conversation.dart';
import '../entities/message.dart';
import 'ask_user_question_turn_cache.dart';
import 'production_release_approval_wording_predicates.dart';

/// Records what the retired wording predicates would have decided.
///
/// Never grants anything. It exists so the token verdict and the prose verdict
/// can be compared over real turns before the predicates are deleted, and it
/// is kept apart from the coordinator so that deletion is a file removal
/// rather than an edit through live approval code.
final class ProductionReleaseProseShadow {
  static const _wording = ProductionReleaseApprovalWordingPredicates();

  final _proofs = <int, _ProseProof>{};

  void capture({
    required int generation,
    required Conversation conversation,
    required String submittedContent,
  }) {
    final submitted = submittedContent.trim();
    Message? precedingMessage;
    for (final message in conversation.messages.reversed) {
      if (message.role != MessageRole.system &&
          message.content.trim().isNotEmpty) {
        precedingMessage = message;
        break;
      }
    }
    _proofs[generation] = _ProseProof(
      conversationId: conversation.id,
      explicit: _wording.looksLikeExplicitProductionReleaseApproval(submitted),
      promptReply:
          _wording.looksLikeAffirmativeReleaseApprovalAnswer(submitted) &&
          precedingMessage?.role == MessageRole.assistant &&
          _wording.looksLikeProductionReleaseApprovalPrompt(
            precedingMessage!.content,
          ),
    );
  }

  /// Whether prose alone would have approved the release in [generation].
  bool wouldApprove({
    required int generation,
    required String? conversationId,
    required ChatTurnOwner? owner,
    required AskUserQuestionTurnCache questionResults,
  }) {
    if (conversationId == null) return false;
    final proof = _proofs[generation];
    final direct =
        proof != null &&
        proof.conversationId == conversationId &&
        (proof.explicit || proof.promptReply);
    return direct ||
        (owner != null &&
            questionResults.anyResult(owner, _wording.answerApproves));
  }

  void clearGeneration(int generation) => _proofs.remove(generation);

  void clear() => _proofs.clear();
}

final class _ProseProof {
  const _ProseProof({
    required this.conversationId,
    required this.explicit,
    required this.promptReply,
  });

  final String conversationId;
  final bool explicit;
  final bool promptReply;
}
