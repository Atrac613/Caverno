# LL37 Idle Panel Slice 1

## Task

- Goal: Add the smallest production LL37 objective-verification path behind
  the existing LL18 idle scheduler without adding any interactive latency or
  mutating unattended work.
- User-visible behavior: The LL18 morning report may include one bounded
  objective-verification result when an injected unattended source supplies a
  candidate. The default source is empty, so existing maintenance behavior is
  unchanged until a later source-adapter slice lands.
- Non-goals: Multiple verifier votes, majority aggregation, retries,
  continuation nudges, a persistent verdict store, or source adapters for
  Routine/LL7/LL13 history.

## Architecture

- Add a pure domain panel service under `features/maintenance`.
- Accept only unattended candidates whose outcome is not already settled by
  LL34 evidence.
- Bound one run to one candidate, one verifier request, a closed prompt-size
  limit, and a fixed output-token allowance.
- Send no tool definitions and expose no mutation callback.
- Parse a fixed JSON verdict schema and return token estimates, findings,
  blocking classification, and a run-local report.
- Add `objective_verify` only to `maintenanceStagesProvider`; no chat or
  attended completion provider may reference it.

## Acceptance Criteria

- Attended and LL34-settled candidates are skipped without calling the model.
- Cancellation is honored before the request and after the response.
- Oversized prompts are skipped instead of truncated into ambiguous evidence.
- Invalid or out-of-range responses become `unverifiable`, never exceptions or
  implicit refutations.
- One invocation cannot evaluate more than one candidate or issue more than one
  model request.
- The maintenance stage stores the run-local report in shared context and
  records a compact result in the existing morning report.
- Tests prove the service is referenced by LL18 maintenance wiring and not by
  interactive chat wiring.

## Verification

```bash
fvm flutter test \
  test/features/maintenance/domain/services/ll37_objective_verification_panel_test.dart \
  test/features/maintenance/presentation/providers/maintenance_stages_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a pure one-candidate, one-request objective verifier and wired
  an `objective_verify` stage immediately after LL18's baseline eval. The
  request supplies no tools, enforces prompt/output bounds, maps unreliable
  responses to `unverifiable`, honors cancellation, and keeps its complete
  report only in the maintenance run context. Production remains doubly
  fail-closed: verifier fidelity eligibility defaults to false and the
  unattended candidate source defaults to empty.
- Tests run: 21 focused domain and maintenance-stage tests passed. They cover
  attended and LL34-settled exclusions, prompt limits, cancellation before and
  after the only request, invalid output, concrete refutation findings, the
  fail-closed profile gate, one-of-many candidate bounding, run-local reporting,
  and absence from interactive chat code. `tool/codex_verify.sh` passed all
  repository analysis, generated-file checks, Flutter/package tests, and 10
  notification relay tests.
- Risks or follow-ups: The next slice must bind fidelity eligibility to the
  measured model identity and adapt exactly one read-only unattended result
  source. Add a user-reviewable verdict store before increasing the vote or run
  cap, retrying work, or connecting continuation nudges.
