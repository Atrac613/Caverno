import '../../domain/entities/chat_turn_owner.dart';
import 'turn_tool_result_ledger.dart';

void publishTurnEvidence(
  TurnToolResultLedger ledger,
  int generation,
  String? conversationId,
) {
  if (conversationId == null) return;
  ledger.publish(
    ChatTurnOwner(
      conversationId: conversationId,
      interactionGeneration: generation,
    ),
  );
}
