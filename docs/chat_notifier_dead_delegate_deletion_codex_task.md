# ChatNotifier Dead Delegate Deletion Task

## Task

- Goal: Remove the two proposal-parsing delegates classified as dead by the
  matching-build guard measurement.
- User-visible behavior: None; proposal parsing continues through the domain
  service call sites that replaced these delegates.
- Non-goals: Do not instrument or reclassify the remaining unresolved guards,
  and do not change proposal parsing behavior.

## Context

- Affected files or components: The proposal-parsing extension, guard and
  decomposition inventories, the turn-scope baseline, analyzer tests, and the
  ChatNotifier renewal documents.
- Related docs: `docs/chat_notifier_guard_reachability_inventory.md` and
  `docs/chat_notifier_renewal_candidate_ranking.md`.
- Reference implementation or pattern: Preserve historical measurement facts
  while removing deleted symbols from current-source inventories.
- Known quirks, compatibility rules, or release gates: The full verification
  suite has a known stale fixture in
  `run_coding_stalled_diagnostic_repair_live_canary_test.dart`.

## Implementation Notes

- Preferred approach: Delete the two orphan delegates, remove their current
  inventory rows, regenerate the turn-scope baseline, and use a synthetic
  unreachable guard in analyzer tests that exercise dead-state derivation.
- Constraints: Keep the matching-build evidence as historical documentation;
  do not disclose private corpus paths or session identifiers.
- Generated files needed: Regenerate
  `tool/chat_notifier_turn_scope_baseline.json` with the audit tool.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `_tryRepairAndDecodeMap`, `_repairJsonCandidate`,
  `currentStaticState`, and `actionState`.
- Files or modules inspected: ChatNotifier proposal parsing, guard inventory,
  telemetry selection, decomposition inventory, analyzer tests, and renewal
  documentation.
- Follow-up tasks found: Re-rank the persisted workflow-origin audit after this
  deletion slice lands.

## Acceptance Criteria

- Required behavior: The two delegates have no production declarations or
  references, and proposal parsing tests remain green.
- Edge cases: The analyzer still derives `dead` for a closed synthetic guard
  and rejects matching-build telemetry that contradicts that proof.
- Failure paths: Current inventory validation and baseline comparison pass.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Removed both dead delegates and synchronized the guard, telemetry,
  decomposition, turn-scope, test, and renewal artifacts.
- Tests run: All 47 focused Python analyzer tests, current guard and telemetry
  manifest validation, turn-scope baseline comparison, and all 4 focused
  proposal parsing tests pass. The standard verifier passes generation,
  project and package analysis, package tests, and 6,481 of 6,482 Flutter
  tests; only the known stale
  `run_coding_stalled_diagnostic_repair_live_canary_test.dart` fixture fails.
- Coverage or low-coverage notes: Focused analyzer tests cover dead-state
  derivation and contradiction rejection.
- Risks or follow-ups: The remaining 63 candidates stay unresolved until a
  later evidence slice closes their static or runtime edges.
