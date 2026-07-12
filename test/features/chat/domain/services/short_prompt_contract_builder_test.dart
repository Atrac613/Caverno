import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/short_prompt_contract_builder.dart';

void main() {
  const builder = ShortPromptContractBuilder();

  test('builds a fully sourced minimal contract from a short prompt', () {
    final contract = builder.build(
      userMessageId: 'message-1',
      userRequest: 'Implement the MVP described in docs/todo_app.md.',
    );

    expect(contract, isNotNull);
    expect(contract!.goal, 'Implement the MVP described in docs/todo_app.md.');
    expect(contract.tasks, hasLength(1));
    expect(
      contract.sources.single.kind,
      ConversationContractSourceKind.userMessage,
    );
    expect(contract.provenance, hasLength(2));
    expect(contract.blockingAssumptions, isEmpty);
  });

  test('does not invent acceptance criteria or constraints', () {
    final contract = builder.build(
      userMessageId: 'message-1',
      userRequest: 'Build the requested application.',
    )!;

    expect(contract.constraints, isEmpty);
    expect(contract.acceptanceCriteria, isEmpty);
    expect(contract.openQuestions, isEmpty);
  });

  test('sources scope and acceptance criteria from a specification', () {
    final contract = builder.build(
      userMessageId: 'message-1',
      userRequest: 'Implement the MVP in todo_app.md.',
      specification: const SpecificationContractInput(
        path: 'todo_app.md',
        content: '''
# TODO app

## Scope

In scope:

- Add and list tasks.

Out of scope:

- No due dates or priorities.

## Acceptance criteria

- [ ] Tasks survive a fresh process run.
- [ ] Unknown ids produce a clear error and
      exit non-zero.
''',
      ),
    )!;

    expect(contract.constraints, [
      'In scope: Add and list tasks.',
      'Out of scope: No due dates or priorities.',
    ]);
    expect(contract.acceptanceCriteria, [
      'Tasks survive a fresh process run.',
      'Unknown ids produce a clear error and exit non-zero.',
    ]);
    final specificationSource = contract.sources.singleWhere(
      (source) =>
          source.kind == ConversationContractSourceKind.specificationFile,
    );
    expect(specificationSource.locator, 'todo_app.md');
    expect(specificationSource.contentHash, isNotEmpty);
    expect(
      contract.provenance
          .where(
            (item) =>
                item.kind == ConversationContractItemKind.acceptanceCriterion,
          )
          .every((item) => item.sourceIds.single == specificationSource.id),
      isTrue,
    );
    expect(contract.blockingAssumptions, isEmpty);
  });

  test('normalizes Japanese requirement and completion headings', () {
    final contract = builder.build(
      userMessageId: 'message-2',
      userRequest: 'Implement \u4ed5\u69d8\u66f8.md.',
      specification: const SpecificationContractInput(
        path: '\u4ed5\u69d8\u66f8.md',
        content: '''
# CLI\u4ed5\u69d8

## \u6a5f\u80fd\u8981\u4ef6

- \u30bf\u30b9\u30af\u3092\u8ffd\u52a0\u3067\u304d\u308b\u3002
- \u7d42\u4e86\u5f8c\u3082\u72b6\u614b\u3092\u4fdd\u6301\u3059\u308b\u3002

## \u5b8c\u4e86\u6761\u4ef6

- [ ] \u65b0\u3057\u3044\u30d7\u30ed\u30bb\u30b9\u3067\u4fdd\u5b58\u5185\u5bb9\u3092\u8aad\u307f\u8fbc\u3081\u308b\u3002
- [ ] \u4e0d\u660e\u306aID\u3067\u306f\u975e\u30bc\u30ed\u3067\u7d42\u4e86\u3059\u308b\u3002
''',
      ),
    )!;

    expect(contract.constraints, [
      '\u30bf\u30b9\u30af\u3092\u8ffd\u52a0\u3067\u304d\u308b\u3002',
      '\u7d42\u4e86\u5f8c\u3082\u72b6\u614b\u3092\u4fdd\u6301\u3059\u308b\u3002',
    ]);
    expect(contract.acceptanceCriteria, [
      '\u65b0\u3057\u3044\u30d7\u30ed\u30bb\u30b9\u3067\u4fdd\u5b58\u5185\u5bb9\u3092\u8aad\u307f\u8fbc\u3081\u308b\u3002',
      '\u4e0d\u660e\u306aID\u3067\u306f\u975e\u30bc\u30ed\u3067\u7d42\u4e86\u3059\u308b\u3002',
    ]);
    expect(
      contract.provenance.where((item) => item.sourceIds.isEmpty),
      isEmpty,
    );
  });

  test('treats functional requirements as sourced constraints', () {
    final contract = builder.build(
      userMessageId: 'message-3',
      userRequest: 'Implement spec.md.',
      specification: const SpecificationContractInput(
        path: 'spec.md',
        content: '''
## Functional requirements

- Persist records locally.

## Definition of Done

- [ ] A fresh process reads persisted records.
''',
      ),
    )!;

    expect(contract.constraints, ['Persist records locally.']);
    expect(contract.acceptanceCriteria, [
      'A fresh process reads persisted records.',
    ]);
  });
}
