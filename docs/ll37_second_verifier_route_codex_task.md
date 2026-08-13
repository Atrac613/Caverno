# LL37 Second Verifier Route Slice

## Task

- Goal: Measure one distinct local verifier route against the unchanged
  consented LL37 ten-case corpus and admit it to production only if it passes
  every existing schema-v3 fidelity threshold.
- Candidate route: OpenAI-compatible
  `http://192.168.100.241:1234/v1`, model `qwen3.6-27b-vision`.
- User-visible behavior on Go: New unattended candidates receive at most one
  vote from each accepted route across idle windows. Two agreeing route votes
  converge; disagreement terminates as `unverifiable` for review.
- Non-goals: Parallel fan-out, a third route, automatic retries, candidate
  mutation, anti-ratchet continuation, strategist passes, or interactive
  verification.

## Evidence Gate

- Reuse exactly the five consented objective-distinct pairs that established
  the first route: one worktree-agent pair and four Routine pairs.
- Each of the ten manifests records explicit user consent for
  `personal_eval_case_recording`. Do not regenerate or relabel cases.
- Run the unchanged schema-v3 probe at temperature zero with no tools.
- Go requires all existing thresholds without exceptions: at least five
  correct and five broken cases, five pairs, five distinct objectives, two
  unattended surfaces, false-refute rate at most 10%, broken recall at least
  80%, and zero invalid or unverifiable outputs.
- Persist the generated JSON and Markdown report under `docs/evidence/` and use
  the committed JSON SHA-256 as the production profile identity.
- The endpoint initially has `qwen3.6-35b-a3b-vision` loaded and the candidate
  unloaded. Let the router autoload the requested candidate, then explicitly
  restore the 35B model after the probe whether the gate is Go or No-Go.

## Production Design On Go

- Append the passing route to the accepted fidelity registry; never replace or
  weaken the first route's evidence.
- Define the route roster in append-only registry order. Slot one remains the
  original 35B route so schema-v1 history keeps its meaning; slot two uses the
  new 27B route.
- Aggregate across the route roster, not within separate per-route cohorts.
  Each accepted route receives at most one vote. With two routes, agreement
  converges and disagreement caps as `unverifiable`; no route gets a tie-break
  repeat.
- Keep the global hard cap at three for a future third independently measured
  route. The current effective cap is the number of accepted routes, two.
- The active provider and normalized endpoint must match the roster. The stage
  may select the roster's measured model per slot, but must recheck endpoint
  eligibility immediately before each request.
- Preserve one request per idle window, persisted vote IDs, cancellation,
  token accounting, privacy filtering, and persistence-failure behavior.

## No-Go Behavior

- Commit the measurement report and decision, but do not alter the accepted
  registry or production route selection.
- Keep the existing exact 35B route and serialized bounded observations
  fail-closed. Record the failed metric and choose a different future candidate
  only in a separate task.

## Acceptance Criteria

- The report is reproducible from the recorded case paths and its SHA-256 is
  recorded in both the registry and roadmap on Go.
- A route is impossible to register when its report misses any threshold.
- On Go, slot assignment is stable across restarts and gives each route at most
  one vote before terminal aggregation.
- Existing schema-v1 slot-one records remain associated with the original 35B
  route; malformed or mismatched route slots are ignored and cannot persist.
- Two matching cross-route classifications converge; a two-route disagreement
  terminates as `unverifiable` without a third same-route request.
- Interactive chat code remains unable to import the panel or route policy.

## Verification

```bash
fvm flutter test \
  test/features/maintenance/domain/services/ll37_verifier_fidelity_profile_test.dart \
  test/features/maintenance/domain/services/ll37_objective_vote_policy_test.dart \
  test/features/maintenance/presentation/providers/maintenance_stages_test.dart \
  test/features/maintenance/presentation/pages/idle_maintenance_debug_page_test.dart
fvm flutter analyze
tool/codex_verify.sh
```

## Handoff Notes

- Measurement: Completed after explicit authorization. The unchanged ten-case
  corpus produced five correct and five broken matches, zero false refutes,
  100% broken recall, zero invalid or unverifiable outputs, five objectives,
  and two source surfaces. The JSON report SHA-256 is
  `ddca603486332ddb0502c634c224cad06611be976650d31ad12c2bdeee587d16`.
- Decision: Go. The candidate passed every unchanged schema-v3 threshold.
- Implementation: Complete. The 27B route follows the original 35B route in
  the append-only roster. The scheduler persists at most one vote per route,
  agreement converges, disagreement caps without a same-route tie-break, and
  endpoint drift or mismatched persisted slots fail closed.
- Runtime cleanup: The candidate was unloaded and
  `qwen3.6-35b-a3b-vision` was restored to `loaded` after measurement.
- Tests run: The live probe passed with all ten cases eligible and all expected
  verdicts matched. The 52-test focused persistence, panel, policy, scheduler,
  and UI suite passed, and `fvm flutter analyze` reported no issues.
  `tool/codex_verify.sh` then passed all analyzers, package tests, 7,339 Flutter
  tests, and 10 notification-relay tests with no generated-file drift.
