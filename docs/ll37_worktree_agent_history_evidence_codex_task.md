# LL37 Worktree-Agent History Evidence

## Task

- Goal: Convert an explicitly selected LL13 worktree-agent correct/broken task
  pair into the neutral LL19/LL37 fidelity evidence format.
- User-visible behavior: None. This is a local, read-only evidence export and
  live-canary workflow.
- Non-goals: Wiring the LL37 production verifier panel, changing LL13 task
  execution, or treating every completed LL13 task as benchmark evidence.

## Context

- Affected files or components: LL13 persisted task JSON, the LL37 fidelity
  case schema, a consent-gated exporter, and its focused tests.
- Related docs: LL13, LL19, and LL37 in
  `docs/local_llm_agent_roadmap.md`.
- Reference implementation or pattern: `tool/ll37_routine_history_export.dart`
  and the bounded LL13 changed-file evidence capture.
- Known quirks, compatibility rules, or release gates: The persisted LL13
  store was empty when this slice started. Export must therefore accept an
  explicit JSON snapshot and must not read or mutate SharedPreferences.

## Implementation Notes

- Preferred approach: Require an explicit selection file carrying
  personal-eval consent, validate a distinct completed green/non-green pair,
  verify captured file hashes and sizes, and stage the complete output before
  an atomic directory rename.
- Constraints: Never export absolute worktree paths, API credentials, or hidden
  reasoning. Preserve only bounded changed-file evidence already captured by
  LL13 and redact sensitive text before writing verifier inputs.
- Generated files needed: None.
- Migration or data compatibility concerns: None. The exporter consumes the
  existing additive LL13 task JSON schema without changing it.

## Similar-Pattern Search

- Search terms: `ll37_routine_history_export`, `changedFiles`,
  `personalEvalManifestPath`, `explicitUserConsent`, `worktree_agent`.
- Files or modules inspected: LL37 probe and Routine exporter, LL13 task
  entity/repository/executor, session-log redaction, and live-canary wrappers.
- Follow-up tasks found: Run a consented isolated LL13 pair against the approved
  LAN model, export it, and score it with the existing LL37 probe.

## Acceptance Criteria

- Required behavior: Export exactly one `not_refuted` and one `refuted` case
  with `sourceSurface: worktree_agent`, matching manifests, shared objective
  and criteria, and recorded verification evidence.
- Edge cases: Reject duplicate task ids, non-terminal tasks, inverted
  verification labels, truncated evidence, unsafe paths, and inconsistent
  content hashes or byte sizes.
- Failure paths: Refuse to replace an existing output directory and remove a
  partially staged directory after any export error.
- Accessibility, localization, or platform expectations: Not applicable. All
  schemas, diagnostics, and docs are English-only.

## Verification

```bash
tool/codex_verify.sh --test test/tool/ll37_worktree_agent_history_export_test.dart --test test/tool/ll37_verifier_fidelity_probe_test.dart
```

## Handoff Notes

- Summary: Added a consent-gated LL13 history exporter plus an isolated live
  canary that runs the production worktree-agent delegate twice against one
  objective. Candidate A uses the normal scoped file tools; candidate B is a
  declared known-broken control with write tools disabled. The exporter
  validates labels, evidence integrity, and matched objectives before writing
  redacted LL19/LL37 manifests and cases.
- Tests run: The focused exporter, runner, existing LL37 probe, and disabled
  live-canary tests passed (17 passed and one skipped in the combined run).
  The saved-report validator also passed against the live artifact.
- Coverage or low-coverage notes: Tests cover consent, matched labels,
  completion state, path safety, evidence truncation, hash/size integrity,
  atomic output, redaction, CLI parsing, and runner gates. The live run on
  `qwen3.6-35b-a3b-vision` recorded one verified changed file for candidate A,
  no changed files and a failing verifier for candidate B, and LL37 verdicts
  matching 2/2 at confidence 1.0 with zero invalid or unverifiable outputs.
- Risks or follow-ups: The broken arm is deliberately recorded as
  `controlled_live_canary`, not organic task history. Together with the prior
  Routine pair the evidence inventory is two correct and two broken cases over
  two surfaces, still below the five-plus-five production gate. Add three
  objective-distinct pairs before any panel wiring.
