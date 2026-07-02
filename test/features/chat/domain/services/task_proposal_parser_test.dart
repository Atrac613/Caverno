import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/task_proposal_parser.dart';
import 'package:caverno/features/chat/domain/services/workflow_task_proposal_quality_service.dart';

void main() {
  late int taskIdIndex;
  late int fallbackIdIndex;
  late TaskProposalParser parser;

  setUp(() {
    taskIdIndex = 0;
    fallbackIdIndex = 0;
    final qualityService = WorkflowTaskProposalQualityService(
      createId: () => 'fallback-${++fallbackIdIndex}',
    );
    parser = TaskProposalParser(
      qualityService: qualityService,
      createId: () => 'task-${++taskIdIndex}',
    );
  });

  test('parses structured task proposal payloads', () {
    final proposal = parser.parse('''
{"tasks":[
  {"title":"Add workflow proposal card","targetFiles":["lib/features/chat/presentation/pages/chat_page.dart"],"validationCommand":"flutter analyze","notes":"Keep approval UI compact"},
  {"title":"Hook proposal state into ChatState","targetFiles":["lib/features/chat/presentation/providers/chat_state.dart"],"validationCommand":"","notes":""}
]}
''');

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(2));
    expect(proposal.tasks.first.id, 'task-1');
    expect(proposal.tasks.first.title, 'Add workflow proposal card');
    expect(proposal.tasks.first.targetFiles, [
      'lib/features/chat/presentation/pages/chat_page.dart',
    ]);
    expect(proposal.tasks.first.validationCommand, 'flutter analyze');
    expect(proposal.tasks.first.notes, 'Keep approval UI compact');
    expect(
      proposal.tasks.every(
        (task) => task.status == ConversationWorkflowTaskStatus.pending,
      ),
      isTrue,
    );
  });

  test('parses task proposals from plain text sections', () {
    final proposal = parser.parse('''
Task: Add workflow proposal card
Target files:
- lib/features/chat/presentation/pages/chat_page.dart
Validation command: flutter analyze
Notes: Keep approval UI compact
''');

    expect(proposal, isNotNull);
    expect(proposal!.tasks, hasLength(1));
    expect(proposal.tasks.single.id, 'task-1');
    expect(proposal.tasks.single.title, 'Add workflow proposal card');
    expect(proposal.tasks.single.targetFiles, [
      'lib/features/chat/presentation/pages/chat_page.dart',
    ]);
    expect(proposal.tasks.single.validationCommand, 'flutter analyze');
    expect(proposal.tasks.single.notes, 'Keep approval UI compact');
  });

  test('builds truncation fallback tasks from workflow context', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Ping CLI',
      messages: [
        Message(
          id: 'user-1',
          content: 'Build a Python CLI tool that pings specific hosts',
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 20, 21, 30),
        ),
      ],
      createdAt: DateTime(2026, 4, 20, 21, 30),
      updatedAt: DateTime(2026, 4, 20, 21, 30),
      workflowSpec: const ConversationWorkflowSpec(
        goal:
            'Develop a Python CLI tool for continuous pinging with JSON output support.',
        constraints: ['Python-based implementation', 'CLI-driven interface'],
        acceptanceCriteria: [
          'Support continuous pinging',
          'Output valid JSON behind a flag',
        ],
      ),
    );

    final proposal = parser.buildTruncationFallback(
      currentConversation: conversation,
      rawContent:
          '<think>Use argparse, add a ping loop, and validate JSON output.</think>',
      projectLooksEmpty: true,
    );

    expect(proposal, isNotNull);
    expect(proposal!.tasks.length, greaterThanOrEqualTo(2));
    expect(proposal.tasks.first.id, 'fallback-1');
    expect(
      proposal.tasks.map((task) => task.title),
      contains('Initialize project structure and requirements.txt'),
    );
  });
}
