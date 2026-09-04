import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/delegated_premise_audit.dart';
import 'package:test/test.dart';

const _audit = DelegatedPremiseAudit();
const _provenance = ConversationContractProvenanceService();

const _premise = 'Existing entities have stable UUIDs';

Conversation _conversation({
  String claim = _premise,
  bool confirmed = true,
  bool includeItem = true,
}) {
  return Conversation(
    id: 'conversation-1',
    title: 'Delegation',
    messages: const <Message>[],
    createdAt: DateTime(2026, 9, 4),
    updatedAt: DateTime(2026, 9, 4),
    workflowSpec: ConversationWorkflowSpec(
      goal: 'Add iCloud synchronization',
      constraints: [claim],
      provenance: [
        if (includeItem)
          ConversationContractItemProvenance(
            itemId: _provenance.itemId(
              kind: ConversationContractItemKind.constraint,
              value: claim,
            ),
            kind: ConversationContractItemKind.constraint,
            assumption: true,
            material: true,
            confirmed: confirmed,
          ),
      ],
    ),
  );
}

void main() {
  test('a premise that is still confirmed has not lapsed', () {
    expect(_audit.lapsed(_conversation(), const [_premise]), isEmpty);
    expect(_audit.mayAcceptResult(_conversation(), const [_premise]), isTrue);
  });

  test('a confirmation that was withdrawn bars acceptance', () {
    final conversation = _conversation(confirmed: false);

    expect(_audit.lapsed(conversation, const [_premise]), [_premise]);
    expect(
      _audit.mayAcceptResult(conversation, const [_premise]),
      isFalse,
      reason:
          'The child is not stopped — a worktree child leaves a branch and an '
          'inspecting child leaves findings, mostly unrelated to the premise. '
          'What must fail is the promotion past `produced`, because a lapsed '
          'premise is missing evidence.',
    );
  });

  test('re-approving a plan, which rebuilds provenance, lapses it', () {
    // ANA0 PR 2 recorded this: attachApprovedPlanSource rebuilds provenance
    // wholesale, so a re-approved plan starts from unconfirmed. Contradiction
    // is therefore reachable without anyone declining anything.
    final conversation = _conversation(includeItem: false);

    expect(_audit.lapsed(conversation, const [_premise]), [_premise]);
  });

  test('an edited claim is a different premise, not a confirmed one', () {
    final conversation = _conversation(
      claim: 'Existing entities have stable UUIDs after the v3 migration',
    );

    expect(
      _audit.lapsed(conversation, const [_premise]),
      [_premise],
      reason:
          'The item id is a hash of the claim text, so an edit changes it. '
          'Matching on the text is what stops a confirmation being carried '
          'across a change of meaning.',
    );
  });

  test('a child sent out with no premises can always be accepted', () {
    expect(
      _audit.mayAcceptResult(_conversation(confirmed: false), const []),
      isTrue,
      reason:
          'Nothing was assumed on its behalf, so nothing about it can lapse.',
    );
  });
}
