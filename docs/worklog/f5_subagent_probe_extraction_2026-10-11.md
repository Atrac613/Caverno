# F5 Subagent Recognition Probe Extraction

## Task

- Goal: complete one behavior-preserving diagnostic boundary extraction.
- User-visible behavior: preserve the delegation request, recognition outcomes,
  report evidence, progress publication and error handling.
- Non-goals: actual delegation, tool-search execution, provider policy changes,
  LL45 implementation, releases and RC1 signed-device verification.

## Context And Selection

The source baseline is local main `208203c26`. Goal-update fidelity was already
committed as `9aa3e3b3a`; its owning roadmap still requested review/commit.
The diagnostic service contains 2,397 lines. The subagent recognition probe is
bounded and only inspects a returned call, unlike tool search, which executes
`tool_search`. It follows the existing completion-port probe pattern.

## Tasks And Acceptance

1. Reconcile the completed goal-update slice with Git and refresh F5's summary.
2. Move subagent prompt and scoring to `LiveLlmSubagentProbe`; retain catalog
   availability, tool selection, request settings, thinking observation, error
   handling, elapsed time and publication in the service.
3. Verify missing/wrong calls, incomplete arguments, first-spawn selection,
   embedded calls, evidence bounds and propagated errors. Preserve strict string
   casts, including malformed-type errors, rather than changing validation.
4. Verify service requests and pending/running/final publication, unavailable
   catalogs and transport failure. Lower the service ratchet and budget the
   extracted module.
5. Inspect the diff, record verification, update both roadmap indexes and commit
   only task files. Preserve the pre-existing `macos/Podfile.lock` change.

## Similar-Pattern Search

Inspected the existing goal-update fidelity and thinking-control probes, and
remaining initial-harness, tool-search and remote-MCP methods. Shared scoring,
preview and usage helpers remain reused. No execution port is introduced.

## Verification

Completed the five tasks above. Final verification:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_subagent_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_goal_update_fidelity_probe_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 594 focused tests passed across six suites, with clean root/package analysis,
  125 internal-package tests and notification relay source checks.
- Extracted module: 14/14 executable lines covered (100%). Service: 623/722
  (86.29%) in this focused run. This is not full-suite coverage.
- First boundary check rejected the new domain-to-data import. The final port
  carries domain calls/content/diagnostic usage and the boundary check passes;
  no reviewed-edge allowance was added. A new-test braces lint was also fixed.
- Normalized scoring matches the original after explicit reply-port and
  constant substitutions. Service contracts cover exact prompt, model,
  temperature, token cap, tool catalog, publication, thinking observation,
  unavailable tools, embedded calls and request failure.
- Service: 2,397 -> 2,355 lines. Module: 69 lines; both size budgets verified.
- Diff whitespace and local roadmap/boundary-plan links checked. Completed
  goal-update task document removed; its historical evidence remains in Git.
- No generated entities changed, so build_runner was unnecessary. No live
  model, signed-device, release, push or full Flutter-suite run was performed.

## Risks And Follow-Up

This is an extraction, not a new capability or a release sign-off. F5 remains
`current`. RC1 signed-device evidence remains on hold. The next bounded F5
candidate is initial-harness selection scoring; tool-search execution should
remain a separate boundary. LL45 remains the next defect-driven alternative.
