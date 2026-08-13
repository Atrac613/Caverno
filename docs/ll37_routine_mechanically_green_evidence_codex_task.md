# LL37 Routine Mechanically-Green Evidence

## Task

- Goal: Make controlled Routine history pairs eligible for the LL37
  mechanically-green fidelity denominator without deriving verification state
  from the expected objective verdict.
- User-visible behavior: None. The consent-gated exporter and live-canary
  workflow produce local schema-v2 LL37 evidence.
- Non-goals: Collecting live evidence without explicit consent, changing
  production Routine scheduling behavior, or wiring the LL37 idle panel.

## Context

- Affected files or components: the Routine history exporter, its fixtures and
  focused tests, a controlled Routine live canary, its runner, and LL37 roadmap
  evidence after a consented run.
- Related docs: `docs/ll37_mechanically_green_evidence_contract_codex_task.md`
  and LL37 in `docs/local_llm_agent_roadmap.md`.
- Reference implementation or pattern: the schema-v2 LL13 exporter and
  `tool/run_ll37_worktree_agent_live_canary.sh`.
- Known quirks, compatibility rules, or release gates: Routine run records do
  not persist a verification command. A controlled capture must therefore
  attach the actual command, exit code, and bounded output to each exported run
  snapshot. Historical schema-v1 Routine evidence remains readable but
  ineligible.

## Implementation Notes

- Preferred approach: Require both selected completed scheduled runs to carry
  `mechanicalVerification` objects with the same non-empty command and exit
  code zero. Emit case schema v2 with
  `mechanicalVerificationPassed: true`, and write `verificationResult: passed`
  to both manifests. Keep objective labels independent.
- Constraints: Preserve explicit consent, atomic output staging, hidden
  reasoning removal, network identifier redaction, workspace path containment,
  and the correct/broken objective-tool coverage distinction.
- Generated files needed: None.
- Migration or data compatibility concerns: The exporter consumes a controlled
  augmented snapshot rather than changing the persisted `RoutineRunRecord`
  entity. Existing application data and schema-v1 artifacts are unchanged.

## Similar-Pattern Search

- Search terms: `mechanicalVerificationPassed`, `verifiedGreen`,
  `verificationResult`, `ll37_routine_history_export`, and
  `run_ll37_worktree_agent_live_canary`.
- Files or modules inspected: LL37 case loading and pair validation, LL13 and
  Routine exporters, `RoutineExecutionService`, Routine tool execution, and
  both existing Routine and LL13 live canaries.
- Follow-up tasks found: after this deterministic slice lands, run one
  explicitly consented controlled Routine pair and combine it with the existing
  LL13 pair. Three additional objective-distinct pairs still remain before Go.

## Acceptance Criteria

- Required behavior: Export exactly one `not_refuted` and one `refuted`
  Routine case at schema v2 only when both arms passed the same recorded
  mechanical verification command.
- Edge cases: Reject missing, non-zero, malformed, or mismatched mechanical
  verification; unsafe or duplicate changed-file paths; attended or failed
  runs; and a broken arm that covers every required objective tool.
- Failure paths: Never infer mechanical success from `expectedVerdict`, never
  expose an absolute Routine workspace path, and never replace an existing
  evidence directory.
- Accessibility, localization, or platform expectations: Not applicable. CLI,
  schema, and documentation text remain English-only.

## Verification

```bash
tool/codex_verify.sh \
  --test test/tool/ll37_routine_history_export_test.dart \
  --test test/tool/ll37_verifier_fidelity_probe_test.dart \
  --test test/tool/run_ll37_routine_live_canary_test.dart
```

## Handoff Notes

- Summary: The Routine exporter now requires both selected arms to carry the
  same successful mechanical verification command, emits schema-v2 cases with
  mechanically-green manifests, normalizes contained changed-file paths, and
  redacts the Routine workspace. A consent-gated live canary exercises the
  production scheduled Routine service with a correct write-capable arm and a
  broken write-disabled arm that both pass the same deliberately weak JSON
  verification command.
- Tests run: After the live-run harness fixes, `tool/codex_verify.sh` passed
  7,286 Flutter tests and 10 relay tests. The focused LL37 set passed 23 tests
  with the consent-gated live test skipped, and
  `bash -n tool/run_ll37_routine_live_canary.sh` passed.
- Coverage or low-coverage notes: The live test remains skipped unless its
  explicit recording-consent environment variable is set.
- Live follow-up, 2026-08-13: After explicit user authorization, the controlled
  Routine pair ran on `qwen3.6-35b-a3b-vision`. The correct arm wrote the exact
  requested state while the write-disabled broken arm left the original state;
  both passed the shared syntax-only verification command. The verifier matched
  both labels at confidence 1.0 with zero invalid or unverifiable outputs. A
  combined probe with the existing LL13 pair matched all four eligible cases
  across two objectives and two surfaces. The local report is under
  `build/integration_test_reports/ll37_routine_live_canary_1786579225/`.
- Risks or follow-ups: The gate remains
  `no_go_insufficient_eligible_sample`. Three more objective-distinct schema-v2
  pairs are required before the combined ten-case decision run and any panel
  wiring.
