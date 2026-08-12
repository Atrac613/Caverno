# LL37 Objective-Diversity Gate

## Task

- Goal: Make the LL37 fidelity Go gate require five structurally valid,
  objective-distinct correct/broken pairs before any further evidence
  collection or production panel wiring.
- User-visible behavior: None. The local JSON and Markdown fidelity reports
  expose eligible pair and objective counts.
- Non-goals: Running the verifier against a live model, collecting new
  consented evidence, changing the verifier prompt, or wiring the production
  idle panel.

## Context

- Affected files or components: the LL37 pair validator, report schema and Go
  gate, focused probe tests, and the LL37 roadmap evidence section.
- Related docs: `docs/ll37_verifier_fidelity_probe_codex_task.md` and LL37 in
  `docs/local_llm_agent_roadmap.md`.
- Reference implementation or pattern: the existing conservative case-count,
  source-surface, false-refute, and broken-recall gates.
- Known quirks, compatibility rules, or release gates: the roadmap requires
  objective-distinct pairs, but report schema v1 counts only cases and source
  surfaces. Existing local reports remain historical artifacts.

## Implementation Notes

- Preferred approach: Validate that both arms of each pair share one source
  surface and one canonical objective/acceptance contract. Count eligible pair
  IDs and canonical objective fingerprints, then require five of each.
- Constraints: Normalize case, whitespace, and acceptance-criterion order for
  fingerprinting. Do not expose the fingerprint or objective text in summary
  metadata. Keep synthetic pairs excluded from the production denominator.
- Generated files needed: None.
- Migration or data compatibility concerns: Bump only the report schema because
  the case schema is unchanged. Existing report files are not rewritten.

## Similar-Pattern Search

- Search terms: `validateLl37VerifierFidelityPairs`, `minimumCorrectCases`,
  `eligibleSourceSurfaces`, `pairId`, and `objective`.
- Files or modules inspected: the LL37 probe, evidence loader, report builder,
  Routine exporter, worktree-agent exporter, focused tests, and roadmap.
- Follow-up tasks found: the next consented evidence pair must be mechanically
  green in both arms while the known-broken arm violates an independent
  acceptance criterion. The current worktree-agent broken control is useful
  harness evidence but has `verifiedGreen: false` and does not establish that
  harder objective-verification population.

## Acceptance Criteria

- Required behavior: A Go report requires five correct cases, five broken
  cases, five complete eligible pairs, five distinct eligible objective
  fingerprints, and at least two eligible unattended source surfaces.
- Edge cases: Reject pair arms with different objectives, acceptance criteria,
  or source surfaces. Treat case, whitespace, and criterion-order-only changes
  as the same objective fingerprint.
- Failure paths: Repeated objectives remain
  `no_go_insufficient_eligible_sample`; malformed pairs throw before any model
  completion is requested.
- Accessibility, localization, or platform expectations: Not applicable. CLI
  output and artifacts remain English-only.

## Verification

```bash
tool/codex_verify.sh --test test/tool/ll37_verifier_fidelity_probe_test.dart
```

## Handoff Notes

- Summary: Report schema v2 validates pair objective/criteria/surface identity,
  reports eligible pair and objective counts, and requires five canonical
  objectives for Go.
- Tests run: The repository verification entrypoint passes the focused probe's
  11 cases, including normalized pair identity, structural rejection paths,
  repeated-objective No-Go, and five-objective Go coverage. Root and package
  analysis, package tests, generated-file checks, and notification-relay checks
  also pass.
- Coverage or low-coverage notes: No live model call is required for this
  deterministic eligibility contract.
- Risks or follow-ups: The mechanically-green known-broken evidence contract is
  now defined by case schema v2. A new live pair still requires explicit
  recording consent, and a second eligible unattended surface remains required.
