# LL39 Edit-Format Fidelity Probe

## Task

- Goal: measure which file-edit representation a selected model can reproduce
  exactly and persist the strongest reliable format in its capability profile.
- User-visible behavior: Live LLM Diagnostics reports whole-file,
  search-and-replace, and unified-diff fidelity and updates
  `editFormatPreference` from live evidence.
- Non-goals: applying edits, touching a real workspace, changing edit tools, or
  adding embeddings, effective-context, or structured-output probes.

## Context

- Affected components: `LiveLlmDiagnosticService`, benchmark scoring,
  `ModelCapabilityProfileBuilder`, diagnostic translations, and focused tests.
- Related docs: `docs/local_llm_agent_roadmap.md` LL39.
- Reference pattern: the exact-preservation probe uses deterministic inputs,
  exact machine grading, partial credit, and production-shaped task wording.

## Implementation Notes

- Ask for the same bounded Dart edit in three independently graded formats.
- Never execute or apply model output.
- Prefer unified diff, then search-and-replace, then whole-file output among
  formats that pass exact grading.
- Store the selected enum name in probe metadata; do not parse display text.
- Keep the fixed benchmark maximum at 1,000 and bump the suite version whenever
  the scored prompt contract changes.

## Acceptance Criteria

- Every `ModelEditFormatPreference` value is reachable from live probe evidence.
- Partial format support is distinguishable from complete failure.
- Bounded model-capability re-probes include this probe.
- Existing tool, vision, streaming, and sampler behavior remains unchanged.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/entities/live_llm_diagnostic_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart
```

## Progress

- Completed: deterministic three-format probe and partial-fidelity grading.
- Completed: `ModelEditFormatPreference` profile mapping via probe metadata.
- Completed: `cavernobench` v5 scoring with the fixed 1,000-point maximum.
- Completed: focused analysis and tests.
- Live v8 evidence on 2026-08-14 showed `qwen3.6-35b-a3b-vision` reproduced the
  whole-file and search/replace contracts but emitted `@@ -1,3 +1,3 @@` for a
  four-line unified-diff hunk. Exact grading correctly rejected that malformed
  header. Failed formats now report their first differing line so future runs
  expose the cause without manually extracting `modelContent`.
- The standard verifier passed project and package analysis, 54 focused Flutter
  tests, package tests, and notification-relay checks.
- A 3-by-3 live A/B then isolated the v8 prompt wording: the original scored
  `[37, 37, 37]`, while an applicable-diff contract with explicit hunk-count
  consistency scored `[55, 55, 55]` against the unchanged exact expected
  output. The corrected production-shaped prompt ships as `cavernobench-v9`.
- Full v9 reruns confirmed 55/55 edit-format fidelity on both
  `qwen3.6-27b-vision` and `qwen3.6-35b-a3b-vision`.
