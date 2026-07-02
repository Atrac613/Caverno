import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/workflow_proposal_parser.dart';
import 'package:caverno/features/chat/domain/services/workflow_task_proposal_quality_service.dart';

void main() {
  late WorkflowProposalParser parser;

  setUp(() {
    parser = WorkflowProposalParser(
      qualityService: WorkflowTaskProposalQualityService(),
    );
  });

  test('parses structured workflow draft payloads', () {
    final result = parser.parse('''
```json
{"workflowStage":"plan","goal":"Ship workflow approvals","constraints":["Keep the UI lightweight"],"acceptanceCriteria":["Users can review before saving"],"openQuestions":["Should quick fixes skip this flow?"]}
```
''');

    expect(result, isA<WorkflowProposalParsedDraft>());
    final proposal = (result as WorkflowProposalParsedDraft).proposal;
    expect(proposal.workflowStage, ConversationWorkflowStage.plan);
    expect(proposal.workflowSpec.goal, 'Ship workflow approvals');
    expect(proposal.workflowSpec.constraints, ['Keep the UI lightweight']);
    expect(proposal.workflowSpec.acceptanceCriteria, [
      'Users can review before saving',
    ]);
    expect(proposal.workflowSpec.openQuestions, [
      'Should quick fixes skip this flow?',
    ]);
  });

  test('parses workflow planning decision payloads', () {
    final result = parser.parse('''
{"kind":"decision","decisions":[
  {"id":"scope","question":"Which implementation scope should the plan target?","help":"Pick the slice you want first.","options":[
    {"id":"minimal","label":"Minimal slice","description":"Ship the smallest end-to-end version first."},
    {"id":"full","label":"Broader slice","description":"Cover the full workflow in one pass."}
  ]}
]}
''');

    expect(result, isA<WorkflowProposalParsedDecisions>());
    final decisions = (result as WorkflowProposalParsedDecisions).decisions;
    expect(decisions, hasLength(1));
    expect(
      decisions.first.question,
      'Which implementation scope should the plan target?',
    );
    expect(decisions.first.help, 'Pick the slice you want first.');
    expect(decisions.first.options, hasLength(2));
    expect(decisions.first.options.first.label, 'Minimal slice');
  });

  test('uses narrative fallback for plain-text proposal retries', () {
    final result = parser.parseWithFallback(
      'The user wants a workflow proposal for build a Python CLI that pings hosts. '
      'Constraints: Python only. Acceptance criteria: It reports host reachability.',
    );

    expect(result, isA<WorkflowProposalParsedDraft>());
    final proposal = (result as WorkflowProposalParsedDraft).proposal;
    expect(proposal.workflowStage, ConversationWorkflowStage.plan);
    expect(proposal.workflowSpec.goal, 'build a Python CLI that pings hosts.');
    expect(proposal.workflowSpec.constraints, ['Python only']);
    expect(proposal.workflowSpec.acceptanceCriteria, [
      'It reports host reachability',
    ]);
  });
}
