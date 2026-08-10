# LL37 Verifier Fidelity Probe

## Task

- Goal: Add a read-only probe that scores a local objective verifier against
  paired correct and known-broken LL19 cases from unattended execution
  surfaces.
- User-visible behavior: None. The probe writes local JSON and Markdown
  evidence for an LL37 Go/No-Go decision.
- Non-goals: Shipping an objective verifier in production, adding verification
  to attended turns, changing LL19 persistence, or automatically enabling
  LL37.

## Context

- Affected files or components: a standalone tool, focused tool tests, and the
  LL37 evidence section of the Local LLM roadmap after a live run.
- Related docs: LL19 and LL37 in `docs/local_llm_agent_roadmap.md`.
- Reference implementation or pattern:
  `tool/ll10_dependency_grounding_live_canary.dart` for an injectable
  OpenAI-compatible client and deterministic fixture mode.
- Known quirks, compatibility rules, or release gates: session logs and case
  evidence are sensitive and remain local. A live case must carry explicit
  personal-eval consent. Synthetic cases can validate the harness but never
  count toward the production fidelity gate.

## Implementation Notes

- Preferred approach: Load paired evidence case files, join each to its LL19
  manifest, send only the objective, acceptance criteria, changed-file
  evidence, and verification evidence to the configured local endpoint, parse
  a fixed JSON verdict, and report a confusion matrix.
- Constraints: Keep the probe read-only, require a supported unattended source
  surface, keep `refuted`, `not_refuted`, and `unverifiable` distinct, and make
  invalid model output visible rather than coercing it into a verdict.
- Generated files needed: None.
- Migration or data compatibility concerns: None. The new evidence-case schema
  is tool-owned and does not alter the LL19 persisted entity.

## Similar-Pattern Search

- Search terms: `PersonalEvalCase`, `PersonalEvalReplayOrchestrator`,
  `chat/completions`, `precision`, `recall`, `heldOut`.
- Files or modules inspected: LL19 entities, live replay driver, verification
  runner, suite pipeline, LL18 measurement, and LL10 live canary.
- Follow-up tasks found: Collect real paired Routine, LL7, and LL13 cases after
  the probe itself is deterministic and reviewable.

## Acceptance Criteria

- Required behavior: Report correct-case false-refute rate, broken-case recall,
  unverifiable/invalid counts, model and endpoint provenance, and case-level
  findings.
- Edge cases: Reject duplicate case IDs, incomplete pairs, mismatched LL19 case
  IDs, missing consent, attended source surfaces, invalid schemas, and
  out-of-range confidence.
- Failure paths: Network, HTTP, timeout, and malformed response failures remain
  explicit case errors and force a No-Go result.
- Accessibility, localization, or platform expectations: Not applicable; CLI
  output and artifacts are English-only.

## Verification

```bash
tool/codex_verify.sh --test test/tool/ll37_verifier_fidelity_probe_test.dart
```

## Handoff Notes

- Summary: Added the read-only paired-case fidelity scorer, strict LL19
  manifest/consent validation, conservative eligibility gate, deterministic
  synthetic fixtures, and OpenAI-compatible transport with an explicit request
  content length for local llama.cpp-compatible routing.
- Tests run: `fvm flutter test
  test/tool/ll37_verifier_fidelity_probe_test.dart` (9 passed); `fvm dart
  analyze` over the probe and its part files (no issues). The live synthetic
  pair scored 2/2 on `qwen3.6-35b-a3b-vision`, with zero unverifiable or invalid
  outputs.
- Coverage or low-coverage notes: Live endpoint transport is exercised by the
  local canary and a local HTTP regression test; parsing and scoring use
  deterministic tests.
- Risks or follow-ups: A synthetic pair is harness validation only and is
  excluded from the eligible denominator. LL37 remains No-Go until at least
  five correct and five known-broken real cases from at least two unattended
  surfaces meet the documented thresholds.
