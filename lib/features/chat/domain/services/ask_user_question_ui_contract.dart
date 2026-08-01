import '../entities/chat_turn_owner.dart';
import 'ask_user_question_policy.dart';

typedef AskUserQuestionOwnerCurrentCallback =
    bool Function(AskUserQuestionOperationIdentity identity);
typedef AskUserQuestionUiStartCallback =
    AskUserQuestionUiStartAcknowledgement Function(
      AskUserQuestionOperationIdentity identity,
      AskUserQuestionRequest request,
    );
typedef AskUserQuestionUiCancelCallback =
    AskUserQuestionUiCancellationAcknowledgement Function(
      AskUserQuestionOperationIdentity identity,
      String pendingQuestionId,
    );

enum AskUserQuestionUiStartDisposition { started, alreadyPending, ownerRetired }

/// Conditional acknowledgement for projecting one question into UI state.
final class AskUserQuestionUiStartAcknowledgement {
  const AskUserQuestionUiStartAcknowledgement.started({
    required this.identity,
    required this.pendingQuestionId,
    required this.completion,
  }) : disposition = AskUserQuestionUiStartDisposition.started;

  const AskUserQuestionUiStartAcknowledgement.alreadyPending({
    required this.identity,
  }) : disposition = AskUserQuestionUiStartDisposition.alreadyPending,
       pendingQuestionId = null,
       completion = null;

  const AskUserQuestionUiStartAcknowledgement.ownerRetired({
    required this.identity,
  }) : disposition = AskUserQuestionUiStartDisposition.ownerRetired,
       pendingQuestionId = null,
       completion = null;

  final AskUserQuestionOperationIdentity identity;
  final AskUserQuestionUiStartDisposition disposition;
  final String? pendingQuestionId;
  final Future<AskUserQuestionUiCompletionAcknowledgement>? completion;
}

enum AskUserQuestionUiCompletionDisposition {
  answered,
  cancelled,
  ownerRetired,
  effectUncertain,
}

/// Exact completion of one pending UI question.
final class AskUserQuestionUiCompletionAcknowledgement {
  const AskUserQuestionUiCompletionAcknowledgement.answered({
    required this.identity,
    required this.pendingQuestionId,
    required AskUserQuestionAnswer this.answer,
  }) : disposition = AskUserQuestionUiCompletionDisposition.answered;

  const AskUserQuestionUiCompletionAcknowledgement.cancelled({
    required this.identity,
    required this.pendingQuestionId,
  }) : disposition = AskUserQuestionUiCompletionDisposition.cancelled,
       answer = null;

  const AskUserQuestionUiCompletionAcknowledgement.ownerRetired({
    required this.identity,
    required this.pendingQuestionId,
  }) : disposition = AskUserQuestionUiCompletionDisposition.ownerRetired,
       answer = null;

  const AskUserQuestionUiCompletionAcknowledgement.effectUncertain({
    required this.identity,
    required this.pendingQuestionId,
  }) : disposition = AskUserQuestionUiCompletionDisposition.effectUncertain,
       answer = null;

  final AskUserQuestionOperationIdentity identity;
  final String pendingQuestionId;
  final AskUserQuestionUiCompletionDisposition disposition;
  final AskUserQuestionAnswer? answer;

  bool belongsTo(
    AskUserQuestionOperationIdentity expectedIdentity,
    String expectedPendingQuestionId,
  ) {
    return identity == expectedIdentity &&
        pendingQuestionId == expectedPendingQuestionId;
  }
}

enum AskUserQuestionUiCancellationDisposition {
  cancelled,
  alreadySettled,
  rejected,
  effectUncertain,
}

/// Conditional cancellation result for one exact pending UI question.
final class AskUserQuestionUiCancellationAcknowledgement {
  const AskUserQuestionUiCancellationAcknowledgement({
    required this.identity,
    required this.pendingQuestionId,
    required this.disposition,
  });

  final AskUserQuestionOperationIdentity identity;
  final String pendingQuestionId;
  final AskUserQuestionUiCancellationDisposition disposition;

  bool belongsTo(
    AskUserQuestionOperationIdentity expectedIdentity,
    String expectedPendingQuestionId,
  ) {
    return identity == expectedIdentity &&
        pendingQuestionId == expectedPendingQuestionId;
  }
}

enum AskUserQuestionOwnerRetirementDisposition {
  noPendingQuestion,
  cancelled,
  alreadySettled,
  rejected,
  boundaryMismatch,
  effectUncertain,
}

/// Result of retiring one owner and conditionally dismissing its UI question.
final class AskUserQuestionOwnerRetirementAcknowledgement {
  const AskUserQuestionOwnerRetirementAcknowledgement({
    required this.owner,
    required this.disposition,
    this.identity,
    this.pendingQuestionId,
  });

  final ChatTurnOwner owner;
  final AskUserQuestionOwnerRetirementDisposition disposition;
  final AskUserQuestionOperationIdentity? identity;
  final String? pendingQuestionId;
}
