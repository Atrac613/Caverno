/// Names shared between the verification-evidence producer
/// (`CodingVerificationFeedbackService`) and the advisory guards that read its
/// tool result.
///
/// This lives in its own library for a structural reason, not a stylistic one.
/// A lexical guard must be able to recognise the evidence tool result without
/// importing the producer, whose own imports reach `conversation_workflow.dart`
/// and therefore `ConversationWorkflowTaskStatus` — terminal task state. The
/// LL36 rule ("a heuristic may trigger, it may not judge") is enforced by
/// `test/quality/lexical_guard_advisory_test.dart` as an import-reachability
/// check, so sharing a constant must not drag the producer's graph along.
class CodingVerificationEvidenceContract {
  const CodingVerificationEvidenceContract._();

  static const toolName = 'dart_test_verification_evidence';
  static const schemaName = 'caverno_dart_test_verification_evidence';
}
