# LL37 Mechanically-Green Evidence Contract

## Task

- Goal: Restrict the LL37 production fidelity denominator to paired evidence
  whose correct and known-broken arms both passed the same mechanical
  verification command.
- User-visible behavior: None. Local case and report artifacts expose whether
  mechanical verification passed and whether the case is eligible.
- Non-goals: Collecting new live evidence without explicit consent, changing
  production Routine or LL13 execution policy, or wiring the LL37 idle panel.

## Context

- Affected files or components: the LL37 case schema and loader, result/report
  eligibility, LL13 history exporter, controlled live canary, fixtures, focused
  tests, and LL37 roadmap evidence.
- Related docs: `docs/ll37_objective_diversity_gate_codex_task.md` and LL37 in
  `docs/local_llm_agent_roadmap.md`.
- Reference implementation or pattern: case schema v1 compatibility and the
  existing consent-gated LL13 evidence exporter.
- Known quirks, compatibility rules, or release gates: historical Routine and
  LL13 pairs either synthesize a failed manifest result or explicitly require
  `verifiedGreen: false` for the broken arm. They validate the harness but do
  not represent LL37's green-command/objective-wrong target population.

## Implementation Notes

- Preferred approach: Add an explicit `mechanicalVerificationPassed` field to
  case schema v2. Continue loading schema v1 as mechanically unqualified and
  exclude it from the production denominator. Require both LL13 task arms to
  be completed and `verifiedGreen: true` before exporting schema v2.
- Constraints: Keep expected objective verdict separate from mechanical
  verification. Never derive `verificationResult` from the expected objective
  label. Preserve consent, redaction, hash, size, and path checks.
- Generated files needed: None.
- Migration or data compatibility concerns: Existing schema-v1 cases remain
  readable and scoreable but become ineligible. Existing artifacts are not
  rewritten.

## Similar-Pattern Search

- Search terms: `verifiedGreen`, `verificationResult`, `isEligible`,
  `sourceSurface.isEligible`, and `recordedVerifiedGreen`.
- Files or modules inspected: LL37 evidence/result/report parts, Routine and
  LL13 exporters, worktree-agent evidence capture, controlled live canary, and
  runner validation.
- Follow-up tasks found: after this deterministic contract lands, a new
  consented live pair can validate the v2 path and begin a fresh eligible
  denominator. The historical v1 inventory remains harness-only.

## Acceptance Criteria

- Required behavior: Only unattended schema-v2 cases with
  `mechanicalVerificationPassed: true` count as eligible. An LL13 pair exports
  only when both tasks are completed and verified green.
- Edge cases: Schema v1 remains loadable but ineligible; mixed mechanical
  status within a pair is rejected; expected `refuted` remains independent of
  the passed command.
- Failure paths: A non-green task, mismatched pair status, malformed v2 field,
  or fabricated expected-label-derived verification result cannot enter the
  eligible denominator.
- Accessibility, localization, or platform expectations: Not applicable. CLI
  output and artifacts remain English-only.

## Verification

```bash
tool/codex_verify.sh \
  --test test/tool/ll37_verifier_fidelity_probe_test.dart \
  --test test/tool/ll37_worktree_agent_history_export_test.dart \
  --test test/tool/run_ll37_worktree_agent_live_canary_test.dart
```

## Handoff Notes

- Summary: Case schema v2 records mechanical verification independently from
  the expected objective verdict. Schema v1 remains readable but ineligible,
  report schema v3 exposes the new status and eligibility semantics, and the
  LL13 exporter now requires and records two green task arms.
- Tests run: The repository verification entrypoint passes root/package
  analysis, generated-file checks, package tests, 19 focused
  probe/exporter/runner tests, the skipped live-canary compile, and notification
  relay checks. A deterministic CLI export plus fixture-response probe produced
  two schema-v2 mechanically-green eligible cases and the expected
  `no_go_insufficient_eligible_sample` gate.
- Coverage or low-coverage notes: The disabled live canary remains
  consent-gated; deterministic fixtures cover the evidence contract.
- Live follow-up, 2026-08-12: After explicit user authorization, the controlled
  v2 canary ran on `qwen3.6-35b-a3b-vision`. Both LL13 tasks completed with
  `verifiedGreen: true`; the correct arm recorded one changed file and the
  write-disabled broken arm recorded none. The verifier matched both labels at
  confidence 1.0 with zero invalid or unverifiable outputs. The report remains
  `no_go_insufficient_eligible_sample` with one eligible pair, one objective,
  and one source surface. The local artifact is under
  `build/integration_test_reports/ll37_worktree_agent_live_canary_1786546687/`.
- Risks or follow-ups: Four more objective-distinct v2 pairs and an eligible
  second unattended surface are still required before panel wiring.
