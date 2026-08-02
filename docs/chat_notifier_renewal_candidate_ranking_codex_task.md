# ChatNotifier Renewal Candidate Ranking Task

## Task

- Goal: Combine the Phase 1 guard, tool-residency, and concept-overlap
  inventories into one evidence-backed renewal candidate ranking.
- User-visible behavior: None. This slice selects the safest next engineering
  work without changing runtime behavior.
- Non-goals: Delete code, migrate tool registration, change persisted models,
  or redesign the chat turn loop.

## Context

- Affected files or components:
  - `docs/chat_notifier_renewal_candidate_ranking.md`
  - `docs/chat_notifier_inventory_codex_task.md`
- Related docs:
  - `docs/chat_notifier_guard_reachability_inventory.md`
  - `docs/chat_notifier_tool_catalog_residency_inventory.md`
  - `docs/chat_notifier_concept_overlap_inventory.md`
- Reference implementation or pattern:
  `docs/chat_notifier_inventory_codex_task.md` defines the Phase 1 ranking
  contract.
- Known quirks, compatibility rules, or release gates: Missing runtime
  observations are not evidence that a path is dead. Tool-catalogue migration
  remains gated by the registry-last prerequisites recorded in its inventory.

## Implementation Notes

- Preferred approach: Rank by evidence confidence first and estimated current
  size within each confidence band. Keep deletion, migration, and investigation
  candidates in separate sections.
- Constraints: Do not multiply confidence by line count. Record evidence,
  dependencies, the next bounded action, and a stop condition for each ranked
  candidate. Prefer proven deletion over extraction when both solve the same
  ownership problem.
- Generated files needed: None.
- Migration or data compatibility concerns: Persisted workflow origins must be
  measured before retiring workflow as an authored source.

## Similar-Pattern Search

- Search terms: `action state`, `unreachable`, `registry-last`, `authoritative`,
  `source of truth`, `persisted origin`, and `unresolved`.
- Files or modules inspected: The three Phase 1 inventories, their checked-in
  manifests, and the directly referenced production declarations.
- Follow-up tasks found: Record them in the ranking with an explicit evidence
  action instead of expanding this documentation-only slice.

## Acceptance Criteria

- Required behavior: The report separates ready deletion candidates from
  blocked migrations and evidence-gathering investigations, ranks confidence
  before size, and identifies one concrete next implementation slice.
- Edge cases: Zero observations in a small or mismatched corpus must not produce
  a deletion recommendation.
- Failure paths: Conflicting evidence remains unresolved and receives a bounded
  next measurement rather than a speculative action state.
- Accessibility, localization, or platform expectations: Not applicable.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-guard-manifest tool/chat_notifier_guard_inventory.json
python3 tool/analyze_chat_notifier_tool_catalog.py \
  --source-revision HEAD \
  --check-manifest tool/chat_notifier_tool_catalog_inventory.json
git diff --check
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending.
- Tests run: Pending.
- Coverage or low-coverage notes: This slice changes documentation only.
- Risks or follow-ups: Pending ranking output.
