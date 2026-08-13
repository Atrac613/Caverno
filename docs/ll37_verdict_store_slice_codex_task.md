# LL37 Reviewable Verdict Store Slice

## Task

- Goal: Persist one reviewable LL37 verdict projection per evaluated unattended
  candidate and use that history to suppress duplicate votes across app
  restarts.
- User-visible behavior: Advanced idle-maintenance diagnostics show recent LL37
  verdicts with their objective, criteria, blocking classification, findings,
  measured verifier identity, timestamp, and token estimate.
- Non-goals: Multiple votes, majority aggregation, automatic retries,
  continuation nudges, candidate mutation, verdict deletion, or interactive
  verification.

## Context

- Affected components: LL37 panel reports, maintenance persistence/providers,
  the `objective_verify` stage, and the idle-maintenance debug page.
- Related docs: `docs/local_llm_agent_roadmap.md`,
  `docs/ll37_idle_panel_slice2_codex_task.md`.
- Reference pattern: LL13's SharedPreferences repository and the existing LL18
  debug page/provider composition.
- Release gate: The panel remains idle-only and fail-closed to the exact
  measured provider, endpoint, model, and accepted fidelity report.

## Implementation Notes

- Persist schema-v1 records as a bounded newest-first JSON list with a maximum
  of 50 records.
- Store one immutable record per candidate in this slice. Loading skips unknown
  schema versions and malformed entries while retaining other valid records.
- Persist only a review projection: candidate/source identity, objective,
  criteria, changed-file paths, implementation summaries, verdict, blocking,
  confidence, findings, request/token counts, verifier profile/report identity,
  detail/error, and UTC timestamp.
- Do not persist changed-file contents, raw verifier prompts, raw model
  responses, credentials, or worktree paths.
- Keep the complete panel report run-local. Only evaluated reports are stored;
  skipped and cancelled reports are not.
- Continue using the session attempt ledger for concurrent/in-session
  suppression, and additionally exclude candidate IDs already in the persisted
  store.
- No generated files are required.

## Similar-Pattern Search

- Search terms: `SharedPreferences`, `loadAll`, `history`, `review`,
  `maintenanceLl37ObjectiveVerificationReportKey`.
- Inspected modules: LL13 repository/registry, Routine history, Personal Eval
  repositories, maintenance debug state, and LL37 source/profile composition.
- Follow-up found: A future multi-vote slice must introduce vote identity and
  convergence policy rather than weakening this slice's one-record-per-
  candidate contract.

## Acceptance Criteria

- A valid evaluated report survives repository and provider-container reloads.
- A malformed list entry or unknown schema does not hide valid neighboring
  records; a malformed root fails closed to an empty history.
- Duplicate candidate records collapse deterministically to the newest valid
  record, and retention never exceeds 50.
- A persisted candidate is excluded before another verifier request after an
  app restart.
- Persistence failure fails the maintenance stage instead of reporting an
  unrecorded successful vote.
- Cancelled and skipped reports are not persisted.
- The review UI renders empty and populated states without exposing changed-file
  contents or raw prompts/responses.
- Interactive chat code remains unable to import the LL37 panel.

## Verification

```bash
fvm flutter test \
  test/features/maintenance/data/ll37_objective_verdict_repository_test.dart \
  test/features/maintenance/presentation/providers/ll37_objective_verdict_history_notifier_test.dart \
  test/features/maintenance/presentation/providers/maintenance_stages_test.dart \
  test/features/maintenance/presentation/pages/idle_maintenance_debug_page_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Implemented schema-v1 verdict projections, bounded persistence,
  provider-backed history state, cross-restart candidate suppression, fail-closed
  maintenance-stage recording, and the Advanced idle-maintenance review UI.
- Tests run: 380 maintenance, file-ratchet, and translation tests passed;
  `fvm flutter analyze` passed with no issues; `tool/codex_verify.sh` passed
  7,322 Flutter tests and 10 notification-relay tests.
- Risks: SharedPreferences remains suitable only because records omit full file
  contents and retention is strictly bounded.
- Follow-up: Define immutable vote identity, a per-candidate vote cap, and
  deterministic aggregation and stall rules before issuing multiple votes.
  Multiple verifier routes, retries, and continuation remain later slices.
