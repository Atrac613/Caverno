# ChatNotifier Tool Catalogue Residency Review: Codex Task

## Task

- Goal: Explain why `ChatToolHandlerCatalog` is not wired into the production
  `ChatNotifier` path and publish a complete, reproducible tool-definition to
  handler-binding residency inventory.
- User-visible behavior: None. This is a read-only architecture investigation.
- Non-goals: Do not change tool dispatch, catalogue wiring, approval behavior,
  session logging, or product behavior.

## Context

- Affected files or components: `ChatNotifier`, `ChatToolDispatcher`,
  `ChatToolHandlerCatalog`, the production tool-handler registry, the static
  tool manifest, and the private residency measurement output.
- Related docs: `docs/chat_notifier_inventory_codex_task.md` and
  `docs/chat_notifier_architecture_renewal_plan.md`.
- Reference implementation or pattern: Existing owner-aware catalogue use in
  the subagent child-tool execution adapter.
- Known quirks, compatibility rules, or release gates: Dynamic MCP schemas,
  endpoints, session identifiers, and corpus paths are private. Report only
  opaque dynamic-definition identifiers and public aggregate provenance.

## Implementation Notes

- Preferred approach: Join the checked-in static manifest to the pinned private
  measurement, audit every production binding route, and use Git history to
  distinguish recorded facts from architectural inference.
- Constraints: Include every static definition and every dynamic snapshot
  definition, including zero invocations. Link them to named, intercepted, or
  generic fallback binding rows. Do not wire the catalogue in production.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `ChatToolHandlerCatalog`, `ChatToolHandlerRegistry`,
  `SubagentCatalogChildToolExecutionAdapter`, `executeFallbackTool`, and
  `WS6-19`.
- Files or modules inspected: Production composition, dispatcher policies,
  catalogue implementation, subagent adapter, decomposition records, and
  relevant Git history.
- Follow-up tasks found: Record separately in the findings document; do not
  implement them in this investigation.

## Acceptance Criteria

- Required behavior: Publish
  `docs/chat_notifier_tool_catalog_residency_inventory.md` with two linked
  tables: one row per measured definition and one row per named/intercepted
  binding plus one explicit generic fallback row.
- Required evidence: Record the source and analyser revisions, corpus manifest
  digest, file count, logged range, represented build revisions and dirty
  states, exact inspection commands, exclusions, and unresolved items.
- Binding analysis: For each binding, report notifier state reads,
  approval/owner dependencies, whether it can be registered, and any turn-state
  access the catalogue cannot currently provide.
- Historical conclusion: Explain the unwired production state using read-only
  Git evidence, labeling any inference explicitly.
- Edge cases: Preserve absent static definitions and zero-observation dynamic
  definitions instead of silently dropping them.
- Failure paths: Stop if manifest counts, snapshot counts, or binding joins do
  not reconcile.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --require-clean-source \
  --check-tool-manifest tool/chat_notifier_tool_catalog_inventory.json
git diff --check
```

## Handoff Notes

- Summary: Published the complete static/dynamic definition inventory, linked
  it to six production binding groups, and traced the unwired catalogue to the
  unmet WS6-19 registry-last gate.
- Tests run: 44 focused analyser tests, deterministic tool-manifest validation,
  report-to-private-output count reconciliation, `git diff --check`, and the
  standard verifier. The verifier passed generation, analysis, and package
  tests, then reproduced the unrelated stale stalled-diagnostic canary fixture
  failure after 6,482 passing Flutter tests.
- Coverage or low-coverage notes: Documentation-only slice; focused analyser
  tests cover the measurement tooling rather than this Markdown finding.
- Risks or follow-ups: Production catalogue migration remains a separate task
  behind the existing gate or an explicitly reviewed replacement contract.
