import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_planning_prompt_service.dart';
import 'package:caverno/features/chat/domain/services/material_contract_assumption_arming.dart';
import 'package:test/test.dart';

/// Anabasis ANA0 PR 3b — the planning prompt is the producer, and it is the
/// only one that runs against a model.
///
/// PR 3a proved the mechanism carries marks once something writes them. This
/// file covers the something. Two things can go wrong that a prompt test
/// usually cannot see:
///
/// 1. The prompt teaches a marker the parser does not accept. Both halves are
///    string literals in different files, so nothing but a test relates them.
///    The assertions below therefore feed the prompt's own wording back
///    through `ContractItemMarks.parseBullet` rather than restating it.
/// 2. A revision quietly launders assumptions into facts. The saved contract
///    is echoed to the model before it rewrites it, and an echo without marks
///    describes a plan in which nothing was ever assumed.
///
/// The producer stays in shadow: marks are written and projected, and
/// `MaterialContractAssumptionArming` still hands the guard nothing until
/// ANA0 PR 4 builds the confirm surface.

const _service = ConversationContractProvenanceService();

const _assumedConstraint = 'The backend exposes incremental sync';
const _plainConstraint = 'Must support iOS 17 and later';

String _constraintId(String value) =>
    _service.itemId(kind: ConversationContractItemKind.constraint, value: value);

Conversation _conversation({ConversationWorkflowSpec? spec}) => Conversation(
  id: 'conversation-1',
  title: 'Plan thread',
  messages: const [],
  createdAt: DateTime(2026, 9, 3, 10),
  updatedAt: DateTime(2026, 9, 3, 10, 5),
  workflowStage: ConversationWorkflowStage.plan,
  workflowSpec: spec ?? const ConversationWorkflowSpec(),
);

String _proposalPrompt({required bool compact, ConversationWorkflowSpec? spec}) =>
    ConversationPlanningPromptService.buildWorkflowProposalRequest(
      currentConversation: _conversation(spec: spec),
      messages: const [],
      languageCode: 'ja',
      compact: compact,
    );

/// Every `(...)` form the prompt quotes back to the model.
///
/// Read out of the prompt rather than hard-coded, so a reworded rule is tested
/// as it will actually be sent.
List<String> _quotedMarkers(String prompt) => RegExp(r'"(\([^"]*\))"')
    .allMatches(prompt)
    .map((match) => match.group(1)!)
    .toList(growable: false);

ConversationWorkflowSpec _savedSpecWithMarks() => ConversationWorkflowSpec(
  goal: 'Add iCloud synchronization',
  constraints: const [_assumedConstraint, _plainConstraint],
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

void main() {
  group('the prompt teaches a marker the parser accepts', () {
    for (final compact in const [false, true]) {
      final label = compact ? 'compact' : 'full';

      test('$label: both marker forms round-trip through parseBullet', () {
        final markers = _quotedMarkers(_proposalPrompt(compact: compact));

        expect(
          markers,
          isNotEmpty,
          reason:
              'The $label proposal prompt must tell the model how to mark an '
              'assumption, or ANA0 PR 3c measures a rate the model was never '
              'asked to produce.',
        );

        for (final marker in markers) {
          final parsed = ContractItemMarks.parseBullet('An item $marker');
          expect(
            parsed.marks.assumption,
            isTrue,
            reason:
                'The prompt quotes "$marker" but parseBullet does not read it '
                'as an assumption. The prompt and the parser are string '
                'literals in different files; only this test relates them.',
          );
          expect(parsed.text, 'An item');
        }

        expect(
          markers.any(
            (marker) =>
                ContractItemMarks.parseBullet('An item $marker').marks.material,
          ),
          isTrue,
          reason:
              'Materiality is what decides whether an assumption blocks, so '
              'the model has to be given the material form as well.',
        );
      });

      test('$label: the marker stays English while the text does not', () {
        final prompt = _proposalPrompt(compact: compact);

        expect(
          prompt,
          contains('Write all text fields in Japanese'),
          reason: 'Precondition: the fields themselves are translated.',
        );
        expect(
          prompt.toLowerCase(),
          contains('marker in english'),
          reason:
              'parseBullet matches "assumed"/"material" and nothing else, so a '
              'translated marker is silently dropped. Language-bound behaviour '
              'is exactly what this codebase keeps out of its heuristics.',
        );
      });
    }
  });

  group('a revision is shown what the contract assumed', () {
    test('the saved-workflow echo carries the marks', () {
      final prompt = _proposalPrompt(
        compact: false,
        spec: _savedSpecWithMarks(),
      );

      expect(prompt, contains('$_assumedConstraint (assumed, material)'));
      expect(
        prompt,
        contains('- constraints: $_assumedConstraint (assumed, material) | '
            '$_plainConstraint'),
        reason:
            'The plain constraint must stay plain: marking everything is the '
            'same loss of signal as marking nothing.',
      );
    });

    test('an unmarked contract echoes exactly as it did before ANA0', () {
      final prompt = _proposalPrompt(
        compact: false,
        spec: const ConversationWorkflowSpec(
          goal: 'Add dark mode',
          constraints: [_plainConstraint],
        ),
      );

      expect(prompt, contains('- constraints: $_plainConstraint\n'));
      expect(prompt, isNot(contains('$_plainConstraint (')));
    });
  });

  group('marks are for what the plan asserts', () {
    test('a marked open question projects to no assumption', () {
      // Measured: on 36 live requests the model put "(assumed, material)" on
      // four open questions and on one constraint. blocksExecution does not
      // look at kind, so before PR 3d each of those four would have refused
      // every workspace mutation -- for asking a question.
      final markdown = ConversationPlanDocumentBuilder.build(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Add iCloud synchronization',
          constraints: [_plainConstraint],
          openQuestions: ['Which persistence layer is in use? (assumed, material)'],
        ),
      );

      final projected =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: markdown,
            requireTasks: false,
          );

      expect(projected.workflowSpec.openQuestions, [
        'Which persistence layer is in use?',
      ], reason: 'The marker is still stripped, so the question reads cleanly.');
      expect(
        projected.workflowSpec.blockingAssumptions,
        isEmpty,
        reason:
            'A question already says the answer is unknown. Marking it as an '
            'assumption claims nothing further, and must not block.',
      );
      expect(
        projected.workflowSpec.provenance
            .singleWhere(
              (item) => item.kind == ConversationContractItemKind.openQuestion,
            )
            .assumption,
        isFalse,
      );
    });

    test('a marked constraint in the same document still carries its mark', () {
      final markdown = ConversationPlanDocumentBuilder.build(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Add iCloud synchronization',
          constraints: ['$_assumedConstraint (assumed, material)'],
          openQuestions: ['Which persistence layer is in use? (assumed)'],
        ),
      );

      final projected =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: markdown,
            requireTasks: false,
          );

      expect(
        projected.workflowSpec.blockingAssumptions,
        hasLength(1),
        reason: 'Dropping question marks must not disarm the constraint case.',
      );
      expect(
        projected.workflowSpec.blockingAssumptions.single.kind,
        ConversationContractItemKind.constraint,
      );
    });

    test('the rule is enforced centrally, not only in the projection', () {
      expect(
        ConversationContractProvenanceService.marksApplyTo(
          ConversationContractItemKind.openQuestion,
        ),
        isFalse,
      );
      for (final kind in const [
        ConversationContractItemKind.constraint,
        ConversationContractItemKind.acceptanceCriterion,
      ]) {
        expect(
          ConversationContractProvenanceService.marksApplyTo(kind),
          isTrue,
          reason: '$kind is something the plan asserts.',
        );
      }
    });

    test('materiality is defined by consequence, not left to taste', () {
      // ANA0 PR 3e. Materiality is the only thing that blocks, and 3d measured
      // it as the model's weakest judgement: marks overall separated the arms
      // 67% to 17%, material marks only 28% to 11%. "Would change the plan
      // materially" restates the word. This asks for a consequence the model
      // can actually check against its own task list.
      for (final compact in const [false, true]) {
        expect(
          _proposalPrompt(compact: compact),
          contains('thrown away rather than adjusted'),
          reason:
              'A definition that names what goes wrong is checkable; one that '
              'repeats the term is not.',
        );
      }
    });

    test('the prompt says so too, so the model is not left to guess', () {
      for (final compact in const [false, true]) {
        expect(
          _proposalPrompt(compact: compact),
          contains('Never mark an openQuestions item'),
          reason:
              'The projection drops these silently. Without the rule the model '
              'keeps spending marks where they cannot mean anything, and the '
              'measured marking rate reads as a capability limit.',
        );
      }
    });
  });

  group('the producer runs in shadow', () {
    test('a marked proposal item projects to a blocking assumption', () {
      // What the model returns: the marker rides inside the JSON string, so it
      // reaches the plan document as text and becomes a mark only there. The
      // document is the authoritative middle; the proposal is not.
      final markdown = ConversationPlanDocumentBuilder.build(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Add iCloud synchronization',
          constraints: ['$_assumedConstraint (assumed, material)'],
        ),
      );

      final projected =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: markdown,
            requireTasks: false,
          );

      expect(projected.workflowSpec.constraints, [_assumedConstraint]);
      expect(projected.workflowSpec.blockingAssumptions, hasLength(1));

      expect(
        MaterialContractAssumptionArming.armed(projected.workflowSpec),
        isEmpty,
        reason:
            'Shadow: PR 3b writes the marks and PR 4 acts on them. Arming here '
            'would refuse every mutation in the conversation with nothing able '
            'to call confirmMaterialAssumption.',
      );
    });

    test('rebuilding the document does not double the marker', () {
      final once = ConversationPlanDocumentBuilder.build(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Add iCloud synchronization',
          constraints: ['$_assumedConstraint (assumed, material)'],
        ),
      );
      final projected =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: once,
            requireTasks: false,
          );
      final twice = ConversationPlanDocumentBuilder.build(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: projected.workflowSpec,
      );

      expect(twice, contains('- $_assumedConstraint (assumed, material)'));
      expect(twice, isNot(contains('(assumed, material) (assumed, material)')));
    });
  });
}
