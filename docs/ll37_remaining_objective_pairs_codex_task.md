# LL37 Remaining Objective-Distinct Pairs

## Task

- Goal: Make the final three objective-distinct mechanically-green Routine
  pairs reproducibly collectible and combine them with the accepted LL13 and
  Routine baseline pairs for the ten-case LL37 decision probe.
- User-visible behavior: None. This is a consent-gated local evaluation
  workflow.
- Non-goals: Wiring the production idle panel, weakening the five-objective
  gate, or recording personal evaluation cases without explicit consent.

## Scenario Matrix

| Scenario | Objective | Independent acceptance criterion | Weak mechanical check |
|----------|-----------|----------------------------------|-----------------------|
| `feature_flag` | Enable a feature in `settings.json` | Exact file content is `{"featureEnabled":true}` | JSON object contains a boolean `featureEnabled` |
| `retry_limit` | Set the retry policy in `policy.json` | Exact file content is `{"retryLimit":3}` | JSON object contains an integer `retryLimit` |
| `display_format` | Select compact output in `display.json` | Exact file content is `{"format":"compact"}` | JSON object contains a string `format` |

Each initial file deliberately satisfies its weak mechanical check while
violating the independent objective criterion. The correct arm must call
`write_file`; the controlled broken arm has all mutation tools disabled.

## Implementation

- Parameterize the production-Routine canary by a closed scenario identifier.
- Run and export each scenario into a separate atomic evidence directory.
- Require four explicitly supplied accepted baseline cases, combine them with
  the six new cases, and reject anything other than five pairs, five objective
  fingerprints, two or more surfaces, zero invalid/unverifiable outputs, at
  most 10% false refutes, and at least 80% broken recall.
- Keep live execution behind
  `CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1`.

## Acceptance Criteria

- Deterministic tests cover the scenario registry, unknown identifiers,
  objective distinctness, runner consent, and ten-case aggregation contract.
- Each exported pair uses schema v2 and records the same successful mechanical
  command for both arms.
- The runner never updates roadmap evidence automatically; accepted live
  results are reviewed before documentation changes.

## Verification

```bash
fvm flutter test \
  tool/canaries/ll37_routine_live_canary_test.dart \
  test/tool/run_ll37_routine_live_canary_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: The production Routine canary now supports the closed
  `feature_flag`, `retry_limit`, and `display_format` scenarios in addition to
  the accepted baseline. The remaining-pairs runner records and exports those
  three pairs, combines them with four explicitly supplied accepted baseline
  cases, and succeeds only when all ten cases pass the production Go gate and
  fidelity thresholds.
- Tests run: The focused LL37 set passed 25 tests with the consent-gated live
  test skipped. Both runner scripts passed `bash -n`; an environment-complete
  no-consent invocation stopped with exit 64. `tool/codex_verify.sh` passed all
  repository analysis, generated-file checks, Flutter/package tests, and 10
  notification relay tests.
- Live follow-up, 2026-08-13: After explicit user consent, all three new pairs
  were recorded on `qwen3.6-35b-a3b-vision`. The initial combined probe was
  `no_go_unreliable_output` because one broken case omitted the observed file
  value and was conservatively unverifiable. The initial report was preserved.
  After the weak type-only check reported the observed value without gating on
  it, the replacement pair produced a final `go`: ten matching verdicts at
  confidence 1.0, five distinct objectives, two surfaces, 0% false refutes,
  100% broken recall, and zero invalid/unverifiable outputs. The artifact is
  under
  `build/integration_test_reports/ll37_remaining_pairs_live_canary_1786582668/`.
- Risks or follow-ups: The fidelity prerequisite is satisfied. Panel wiring is
  now allowed, but must remain LL18-idle-only, bounded, non-mutating, and free
  of any inline interactive stage.
