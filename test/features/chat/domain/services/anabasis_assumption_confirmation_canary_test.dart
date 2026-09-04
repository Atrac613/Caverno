@Tags(['canary'])
library;

import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/material_contract_assumption_arming.dart';
import 'package:caverno/features/chat/domain/services/material_contract_assumption_guard.dart';
import 'package:test/test.dart';

/// Anabasis MVP 0, PR 1 — the canary that defines the confirmation path.
///
/// See `docs/ANABASIS_ORCHESTRATOR_ARCHITECTURE.md` §7. The short version:
/// `MaterialContractAssumptionGuard` is already wired into the tool-loop guard
/// chain and already refuses mutations while a material assumption is
/// unconfirmed. What does not exist is any production path that records a
/// user's confirmation, so `confirmed` can never become true and a blocked
/// contract can never be unblocked.
///
/// That ordering matters: shipping the assumption *producer* (PR 3) before the
/// confirmation path would arm the guard with no way to disarm it, and every
/// mutation in the conversation would be refused permanently.
///
/// This file therefore does two things.
///
/// 1. It locks in the behaviour that already works, so PR 2 and PR 3 cannot
///    regress it while adding the missing half.
/// 2. It fails on the missing half — deliberately — until PR 2 lands.
///
/// The producer canary (PR 3) is intentionally not here; this PR covers the
/// confirmation path only.

const _guard = MaterialContractAssumptionGuard();

/// A workspace mutation: the class of call the guard is meant to refuse.
final _mutationCall = ToolCallInfo(
  id: 'call-write',
  name: 'write_file',
  arguments: const {'path': 'lib/sync/engine.dart', 'content': '// ...'},
);

/// An inspection: allowed even while the contract is blocked, because
/// investigating the assumption is exactly what the user is being asked to do.
final _inspectionCall = ToolCallInfo(
  id: 'call-read',
  name: 'read_file',
  arguments: const {'path': 'pubspec.yaml'},
);

const _assumptionItemId = 'constraint:stable-entity-ids';
const _clarification = 'Do existing entities have stable UUIDs?';

ConversationWorkflowSpec _blockedSpec() {
  return const ConversationWorkflowSpec(
    goal: 'Add iCloud synchronization',
    constraints: ['Existing entities have stable UUIDs'],
    provenance: [
      ConversationContractItemProvenance(
        itemId: _assumptionItemId,
        kind: ConversationContractItemKind.constraint,
        sourceIds: ['approved-plan:deadbeef'],
        assumption: true,
        material: true,
        clarificationQuestion: _clarification,
      ),
    ],
  );
}

/// The exact state PR 2 must produce when the user confirms the assumption.
///
/// Hand-built here so the contract is legible and asserted before any
/// production code exists to satisfy it. All three steps from §7:
/// append a source, link it, then flip the flag.
ConversationWorkflowSpec _expectedConfirmationResult(
  ConversationWorkflowSpec blocked,
) {
  const sourceId = 'user-confirmed:$_assumptionItemId';
  return blocked.copyWith(
    sources: [
      ...blocked.sources,
      const ConversationContractSourceReference(
        id: sourceId,
        kind: ConversationContractSourceKind.userConfirmedAssumption,
        locator: 'message:confirmation',
      ),
    ],
    provenance: blocked.provenance
        .map(
          (item) => item.itemId == _assumptionItemId
              ? item.copyWith(
                  sourceIds: [...item.sourceIds, sourceId],
                  confirmed: true,
                )
              : item,
        )
        .toList(growable: false),
  );
}

/// Production `lib/` files, excluding generated output.
Iterable<File> _productionSources() {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    fail('Expected to run from the repository root; "lib/" was not found.');
  }
  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.endsWith('.g.dart'))
      .where((file) => !file.path.endsWith('.freezed.dart'));
}

/// Whether any production file writes
/// [ConversationContractSourceKind.userConfirmedAssumption].
///
/// The enum's own declaration does not count.
bool _productionWritesConfirmationSource() {
  const declarationPath =
      'lib/features/chat/domain/entities/conversation_workflow.dart';
  return _productionSources()
      .where((file) => file.path != declarationPath)
      .any(
        (file) => file.readAsStringSync().contains('userConfirmedAssumption'),
      );
}

/// Whether anything actually *calls* the confirmation transformation.
///
/// Presence is not reachability. The first version of this canary asserted
/// only that some production file mentions `userConfirmedAssumption`, and it
/// went green the moment the domain transformation existed — with no caller
/// anywhere. That would have moved the value from "declared and never written"
/// to "written and never called", which is the same orphan one layer up, and
/// is precisely the failure this whole track exists to stop repeating.
///
/// A caller is the weakest honest proxy for reachability that a source scan
/// can express. It does not prove a user can reach it; PR 2's surface work and
/// its own widget coverage do that.
bool _productionCallsConfirmation() {
  const definitionPath =
      'lib/features/chat/domain/services/'
      'conversation_contract_provenance_service.dart';
  return _productionSources()
      .where((file) => file.path != definitionPath)
      .any(
        (file) => file.readAsStringSync().contains('confirmMaterialAssumption'),
      );
}

/// Whether the tool loop can refuse a mutation without offering a way to
/// answer.
///
/// While ANA0 ran in shadow this asked the opposite question — that the feed
/// site went through the arming policy rather than reading the spec's blocking
/// list, because arming with no confirm surface refuses every mutation
/// permanently. The surface exists now, so the successor invariant is that the
/// refusal and the question are not separable: the loop must evaluate through
/// [MaterialAssumptionConfirmationGate], which asks and re-evaluates, and never
/// call the guard directly, which can only say no.
bool _feedSiteRefusesWithoutAsking() {
  const feedSitePath =
      'lib/features/chat/presentation/providers/'
      'chat_notifier_tool_loop_batch.dart';
  final source = File(feedSitePath).readAsStringSync();
  return !source.contains('MaterialAssumptionConfirmationGate(') ||
      source.contains('MaterialContractAssumptionGuard().evaluate(');
}

void main() {
  group('already works — do not regress', () {
    test('an unconfirmed material assumption blocks a workspace mutation', () {
      final blocked = _blockedSpec();
      expect(blocked.blockingAssumptions, hasLength(1));

      final result = _guard.evaluate(
        _mutationCall,
        workspaceMode: WorkspaceMode.coding,
        blockingAssumptions: blocked.blockingAssumptions,
      );

      expect(result, isNotNull);
      expect(result!.isSuccess, isFalse);
      expect(
        result.result,
        contains(MaterialContractAssumptionGuard.blockedCode),
      );
      expect(result.result, contains(_clarification));
    });

    test('inspection stays available while the contract is blocked', () {
      final blocked = _blockedSpec();

      expect(
        _guard.evaluate(
          _inspectionCall,
          workspaceMode: WorkspaceMode.coding,
          blockingAssumptions: blocked.blockingAssumptions,
        ),
        isNull,
        reason:
            'Investigating the assumption is the way out of the block, so it '
            'must not itself be blocked.',
      );
    });

    test('a confirmed assumption stops blocking', () {
      final confirmed = _expectedConfirmationResult(_blockedSpec());

      expect(
        confirmed.blockingAssumptions,
        isEmpty,
        reason: 'blocksExecution == assumption && material && !confirmed',
      );
      expect(
        _guard.evaluate(
          _mutationCall,
          workspaceMode: WorkspaceMode.coding,
          blockingAssumptions: confirmed.blockingAssumptions,
        ),
        isNull,
      );
    });

    test('confirmation is recorded as a source, not only as a flag', () {
      final confirmed = _expectedConfirmationResult(_blockedSpec());

      final confirmationSources = confirmed.sources.where(
        (source) =>
            source.kind ==
            ConversationContractSourceKind.userConfirmedAssumption,
      );
      expect(confirmationSources, hasLength(1));

      final item = confirmed.provenance.singleWhere(
        (entry) => entry.itemId == _assumptionItemId,
      );
      expect(
        item.sourceIds,
        contains(confirmationSources.single.id),
        reason:
            'The confirmation must be reachable from the item, so the '
            'provenance graph can later answer why this was treated as known.',
      );
    });
  });

  group('armed, now that the way out exists', () {
    test('a spec that blocks is handed exactly what blocks it', () {
      final blocked = _blockedSpec();
      expect(
        blocked.blockingAssumptions,
        hasLength(1),
        reason: 'The item itself must keep blocking semantics.',
      );

      expect(
        MaterialContractAssumptionArming.armed(blocked),
        blocked.blockingAssumptions,
        reason:
            'PR 4b-2 armed the guard once a user could answer. This policy '
            'stays the one place that decides, so a future restriction of '
            'scope has somewhere to live.',
      );
    });

    test('the feed site cannot refuse without asking', () {
      expect(
        _feedSiteRefusesWithoutAsking(),
        isFalse,
        reason:
            'chat_notifier_tool_loop_batch.dart must evaluate through '
            'MaterialAssumptionConfirmationGate, which raises the '
            'confirmation and re-evaluates. Calling the guard directly there '
            'restores the state ANA0 spent two PRs avoiding: a refusal whose '
            'only exit is a question the model may never ask.',
      );
    });
  });

  group('the gap', () {
    test('a production path writes the userConfirmedAssumption source', () {
      expect(
        _productionWritesConfirmationSource(),
        isTrue,
        reason:
            'Until some production path records a confirmation, '
            'blockingAssumptions can never empty and '
            'MaterialContractAssumptionGuard blocks every mutation in the '
            'conversation permanently. The three steps are asserted above: '
            'append the source, link it into sourceIds, set confirmed = true. '
            'See docs/ANABASIS_ORCHESTRATOR_ARCHITECTURE.md §7.',
      );
    });

    test('something calls the confirmation transformation', () {
      expect(
        _productionCallsConfirmation(),
        isTrue,
        reason:
            'ConversationContractProvenanceService.confirmMaterialAssumption '
            'exists but nothing calls it, so no user can actually confirm '
            'anything and the guard still cannot be unblocked in a real '
            'conversation. This assertion exists because the first version '
            'of this canary passed without it.',
      );
    });
  });
}
