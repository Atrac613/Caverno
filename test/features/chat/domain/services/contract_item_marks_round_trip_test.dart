import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:test/test.dart';

/// Anabasis ANA0 PR 3a — the epistemic marks round-trip.
///
/// The plan document is the authoritative middle of the contract: the workflow
/// spec is derived from approved Markdown, not from the planning JSON. So an
/// assumption only survives if it survives that document. Nothing produces
/// marks yet — the planning prompt change is PR 3b — so this file proves the
/// mechanism carries them once something does.

const _service = ConversationContractProvenanceService();

const _assumedConstraint = 'Existing entities have stable UUIDs';
const _plainConstraint = 'Must support iOS 17 and later';

String _constraintId(String value) => _service.itemId(
  kind: ConversationContractItemKind.constraint,
  value: value,
);

ConversationWorkflowSpec _specWithMarks() {
  return ConversationWorkflowSpec(
    goal: 'Add iCloud synchronization',
    constraints: const [_assumedConstraint, _plainConstraint],
    acceptanceCriteria: const ['Records converge within one sync cycle'],
    provenance: [
      ConversationContractItemProvenance(
        itemId: _constraintId(_assumedConstraint),
        kind: ConversationContractItemKind.constraint,
        assumption: true,
        material: true,
      ),
      ConversationContractItemProvenance(
        itemId: _constraintId(_plainConstraint),
        kind: ConversationContractItemKind.constraint,
      ),
    ],
  );
}

void main() {
  group('ContractItemMarks.parseBullet', () {
    test('reads both marker forms, case and spacing tolerant', () {
      expect(
        ContractItemMarks.parseBullet('The API is REST (assumed)'),
        (
          text: 'The API is REST',
          marks: const ContractItemMarks(assumption: true),
        ),
      );
      expect(
        ContractItemMarks.parseBullet('Stable IDs  ( Assumed ,  Material )'),
        (
          text: 'Stable IDs',
          marks: const ContractItemMarks(assumption: true, material: true),
        ),
      );
    });

    test('leaves an unmarked bullet alone', () {
      expect(
        ContractItemMarks.parseBullet('  Must support iOS 17  '),
        (text: 'Must support iOS 17', marks: ContractItemMarks.none),
      );
    });

    test('does not eat text that merely looks like a marker', () {
      for (final line in const [
        'Sync is (material) to the release',
        'Nothing is assumed',
        'The plan (assumed) is reviewed first',
      ]) {
        final parsed = ContractItemMarks.parseBullet(line);
        expect(
          parsed.marks,
          ContractItemMarks.none,
          reason: 'Only a trailing marker counts: $line',
        );
        expect(parsed.text, line);
      }
    });

    test('marking an item does not change its identity', () {
      final marked = ContractItemMarks.parseBullet(
        '$_assumedConstraint (assumed, material)',
      );
      expect(
        _constraintId(marked.text),
        _constraintId(_assumedConstraint),
        reason:
            'itemId hashes the stripped text. If the marker changed the id, '
            'confirming an assumption would not survive a re-derivation.',
      );
    });
  });

  group('document round-trip', () {
    test('marks survive build then project', () {
      final markdown = ConversationPlanDocumentBuilder.build(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: _specWithMarks(),
      );

      expect(markdown, contains('- $_assumedConstraint (assumed, material)'));
      expect(markdown, contains('- $_plainConstraint\n'));

      final projected =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: markdown,
            requireTasks: false,
          );

      expect(projected.workflowSpec.constraints, [
        _assumedConstraint,
        _plainConstraint,
      ]);

      final assumed = projected.workflowSpec.provenance.singleWhere(
        (item) => item.itemId == _constraintId(_assumedConstraint),
      );
      expect(assumed.assumption, isTrue);
      expect(assumed.material, isTrue);
      expect(assumed.blocksExecution, isTrue);

      final plain = projected.workflowSpec.provenance.singleWhere(
        (item) => item.itemId == _constraintId(_plainConstraint),
      );
      expect(plain.assumption, isFalse);
      expect(plain.blocksExecution, isFalse);
    });

    test('an unmarked document still projects to no assumptions', () {
      final markdown = ConversationPlanDocumentBuilder.build(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Add dark mode',
          constraints: ['Must not regress existing themes'],
        ),
      );

      expect(markdown, isNot(contains('assumed')));

      final projected =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: markdown,
            requireTasks: false,
          );

      expect(
        projected.workflowSpec.blockingAssumptions,
        isEmpty,
        reason:
            'Every plan document written before ANA0 is unmarked, so the '
            'projection must keep producing exactly what it produced before.',
      );
      expect(projected.workflowSpec.provenance, isNotEmpty);
    });

    test('a hand-typed marker is honoured', () {
      const handEdited = '''
# Plan

## Stage
implement

## Goal
Add iCloud synchronization

## Constraints
- The backend exposes incremental sync (assumed, material)
''';

      final projected =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: handEdited,
            requireTasks: false,
          );

      expect(projected.workflowSpec.constraints, [
        'The backend exposes incremental sync',
      ]);
      expect(projected.workflowSpec.blockingAssumptions, hasLength(1));
    });
  });
}
