# ChatNotifier TurnRuntime Phase 1.5 Decision Contract: Codex Task

## Task

- Goal: Reconcile the Phase 1.5 decision contract before the selected
  `TurnRuntime` production prototype begins.
- User-visible behavior: None. This task changes architecture decision records
  only.
- Non-goals: Creating `TurnRuntime`, editing production Dart, implementing the
  prototype comparison mode, wiring `ChatToolHandlerCatalog`, completing I2, or
  rerunning the live canary.

## Context

- Affected files or components:
  - `docs/chat_notifier_architecture_renewal_plan.md`
  - `docs/chat_notifier_turn_runtime_preprototype_decision.md`
  - `docs/chat_notifier_turn_runtime_phase_1_5_decision_codex_task.md`
- Related docs:
  - `docs/chat_tool_handler_catalog_unwired_findings.md`
  - `docs/chat_notifier_renewal_candidate_ranking.md`
  - `docs/chat_notifier_turn_runtime_prototype_verification_codex_task.md`
- Reference implementation or pattern:
  - `tool/chat_notifier_turn_runtime_prototype_verification.json`
  - `tool/measure_chat_notifier_turn_runtime_prototype.py`
- Known quirks, compatibility rules, or release gates:
  - The original live-baseline No-Go was lifted after three of four seeded runs
    passed and the remaining flake received a bounded attribution rule.
  - The architecture plan still recorded the lifted No-Go and treated positive
    production line delta as an automatic rejection.
  - The catalogue investigation proved that current bindings capture
    `ChatNotifier`; WS6-19 therefore remains blocked without port extraction.
  - The last clean selector chose
    `chat_notifier_goal_auto_continue.dart` with 13 explicit identity
    entrypoints, zero turn-reachable ambient reads, and 804 production lines.

## Implementation Notes

- Preferred approach:
  1. Record a conditional Go for exactly one mechanically selected production
     prototype.
  2. Remove catalogue wiring from the Phase 1.5 experiment while retaining its
     WS6-19 prerequisites and stop conditions for later re-entry.
  3. Separate structural falsification gates from cost-reporting metrics.
  4. Retain the seeded live baseline and its known-flake attribution rule.
  5. Require a fresh clean selector and static gate binding before production
     editing.
- Constraints:
  - Keep identity-parameter removal, ambient-read non-increase,
    no-`ChatNotifier` capture, scope ownership, and behavior preservation as
    hard gates.
  - Report line delta, ports, callbacks, touched files, and public surface; do
    not use line delta alone to reject the diagnosis.
  - Keep the full I2 catalogue matrix out of the isolated prototype entry
    contract, while requiring a selected-part port matrix.
  - Preserve historical failed-run evidence rather than rewriting it as if the
    original No-Go never existed.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `Phase 1.5`, `No-Go`, `production line delta`, `WS6-19`,
  `ChatNotifier`, `I2`, `attribution rule`, `prototype`.
- Files or modules inspected:
  - `docs/chat_notifier_architecture_renewal_plan.md`
  - `docs/chat_notifier_turn_runtime_preprototype_decision.md`
  - `docs/chat_tool_handler_catalog_unwired_findings.md`
  - `docs/chat_notifier_decomposition_workstream_6_codex_tasks.md`
  - `docs/chat_notifier_renewal_candidate_ranking.md`
- Follow-up tasks found:
  - Build the selected-part port matrix from current source.
  - Re-run clean selector and static gate validation from the decision commit.
  - Add prototype comparison mode only when the isolated production prototype
    is ready to measure.

## Acceptance Criteria

- Required behavior:
  - Both decision documents state the same conditional-Go status.
  - Catalogue wiring is not a Phase 1.5 implementation experiment and remains
    blocked until prototype ports plus I2 satisfy WS6-19.
  - Positive line delta triggers cost review but is not a structural failure.
  - Structural gates and the known live-flake attribution rule remain explicit.
  - The selected-part port matrix and fresh clean selection are prerequisites
    to production editing.
- Edge cases:
  - Historical No-Go evidence remains clearly identified as historical.
  - A correctly blocked live run is not described as full goal completion.
  - Abandoning the prototype does not implicitly unblock catalogue wiring.
- Failure paths: Any remaining contradictory Go/No-Go or line-delta language
  blocks the prototype.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
rg -n "No-Go|Conditional Go|production line delta|ChatToolHandlerCatalog|WS6-19|I2|structural gate" \
  docs/chat_notifier_architecture_renewal_plan.md \
  docs/chat_notifier_turn_runtime_preprototype_decision.md \
  docs/chat_notifier_turn_runtime_phase_1_5_decision_codex_task.md
git diff --check
```

## Handoff Notes

- Summary: Reconciled Phase 1.5 around one conditional-Go prototype, deferred
  catalogue wiring until prototype ports plus I2 satisfy WS6-19, and separated
  structural gates from line-count cost reporting.
- Tests run:
  - Decision-language search across all three affected documents: passed.
  - `git diff --check`: passed.
- Coverage or low-coverage notes: Documentation-only decision contract; no
  production coverage changes.
- Risks or follow-ups: The selected-part port matrix remains the next bounded
  task before production editing.
