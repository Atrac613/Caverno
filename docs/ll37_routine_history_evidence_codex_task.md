# LL37 Routine History Evidence Export

## Task

- Goal: Export a consented pair of recorded scheduled Routine runs into the
  LL19 manifest and LL37 verifier-fidelity case formats.
- User-visible behavior: None. The command writes local-only evidence files for
  an offline LL37 fidelity measurement.
- Non-goals: Changing Routine execution, treating explicit failed runs as
  objective-verifier candidates, enabling the LL37 idle panel, or committing
  private run evidence.

## Context

- Affected files or components: a standalone Routine-history exporter, focused
  tool tests, and the LL37 fidelity probe's evidence validation.
- Related docs: LL19 and LL37 in `docs/local_llm_agent_roadmap.md` and
  `docs/ll37_verifier_fidelity_probe_codex_task.md`.
- Reference implementation or pattern: `tool/personal_eval_case_manifest.dart`
  for consent and local-only manifest fields; the existing LL37 probe for the
  paired evidence schema.
- Known quirks, compatibility rules, or release gates: both selected runs must
  be scheduled and recorded as completed because LL37 audits unattended
  completion claims. The known-broken run must omit at least one caller-declared
  objective tool that the correct run contains. Raw evidence stays outside the
  repository.

## Implementation Notes

- Preferred approach: Read an exported SharedPreferences Routine JSON array and
  a small selection file, validate the pair mechanically, and write neutral
  candidate IDs so expected labels never enter the verifier prompt.
- Constraints: Require explicit personal-eval consent, keep source records
  read-only, strip hidden thinking from final output, anonymize network
  identifiers consistently across the complete verifier payload, and preserve
  enough tool evidence for an independent objective judgment.
- Generated files needed: Local LL19 manifests and LL37 case JSON files under a
  caller-selected output directory.
- Migration or data compatibility concerns: Known-broken cases may legitimately
  contain no changed files; correct cases still require at least one captured
  file mutation.

## Similar-Pattern Search

- Search terms: `flutter.routines`, `PersonalEvalCaseManifest`,
  `explicitUserConsent`, `RoutineRunRecord`, `toolCalls`, `scheduled`.
- Files or modules inspected: Routine repository/entity/history persistence,
  Personal Eval manifest tooling, stored Routine metadata, and LL37 case
  validation.
- Follow-up tasks found: Repeat the same evidence discipline on LL13 or
  retry-until-green so the two-surface gate can be evaluated.

## Acceptance Criteria

- Required behavior: Export exactly one neutral-ID pair, keep both source runs
  scheduled/completed, prove required tools are present in the correct run and
  missing from the broken run, emit consented local-only manifests, and remove
  raw IP and MAC addresses from the exported cases.
- Edge cases: Reject duplicate or missing run IDs, non-scheduled runs,
  non-completed runs, empty criteria, missing consent, a correct run without a
  captured file mutation, and a broken run that contains every required tool.
- Failure paths: Invalid JSON or malformed stored tool arguments fail before
  writing a partial output directory.
- Accessibility, localization, or platform expectations: Not applicable; CLI
  output and artifacts are English-only.

## Verification

```bash
tool/codex_verify.sh --test test/tool/ll37_routine_history_export_test.dart --test test/tool/ll37_verifier_fidelity_probe_test.dart
```

## Handoff Notes

- Summary: Added a consent-gated Routine-history exporter that validates one
  scheduled completed correct/broken pair, writes neutral LL19/LL37 evidence,
  strips hidden reasoning, and replaces network identifiers with stable
  `device-XXX` tokens while fully redacting MAC addresses. One real Routine
  pair was exported to a local temporary directory; no private evidence was
  committed or sent to a model.
- Tests run: `fvm dart analyze` over the exporter and LL37 probe sources (no
  issues); `fvm flutter test test/tool/ll37_routine_history_export_test.dart
  test/tool/ll37_verifier_fidelity_probe_test.dart` (16 passed). A local
  fixture-response run loaded both real exported cases and matched the expected
  labels, but does not count as model-fidelity evidence.
- Coverage or low-coverage notes: Stored Routine parsing and pair validation use
  deterministic fixtures. The real exported payload contains zero raw IPv4 or
  MAC matches after anonymization.
- Risks or follow-ups: Live scoring of the anonymized real Routine payload needs
  explicit approval because its objective and abstracted tool evidence still
  derive from private run history. Even after that run, one Routine pair cannot
  satisfy the two-surface or minimum-case gate.
