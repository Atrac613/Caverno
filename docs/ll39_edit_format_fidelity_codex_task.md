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
- Keep the fixed benchmark maximum at 1,000 and bump the suite version.

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
- Completed: focused analysis and tests. Live model evidence remains a separate
  consented follow-up because this slice changes implementation and contracts.
