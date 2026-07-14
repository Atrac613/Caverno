# Markdown TOC Adaptive Terminal-Success Live Validation

## Task

- Goal: Confirm that adaptive Dart CLI entrypoint verification and structured
  terminal-success finalization generalize from the TODO fixture to the
  structurally different Markdown TOC exact-short fixture.
- User-visible behavior: A local model can implement the Markdown TOC MVP from
  a short prompt, verify the entrypoint it actually created, and stop after
  successful verification without re-entering coding recovery.
- Non-goals: Changing the fixture, verifier, prompt, model, token budget, or
  ordinary recovery behavior when terminal-success evidence is absent.

## Context

- Affected components: The Markdown TOC exact-short Live canary, adaptive Dart
  CLI entrypoint resolution, and turn-finalization recovery.
- Related docs: `docs/adaptive_mvp_entrypoint_verification_codex_task.md`,
  `docs/terminal_success_turn_finalization_recovery_codex_task.md`, and
  `docs/coding_mvp_fixtures/markdown_toc_generator.md`.
- Reference command:
  `tool/run_coding_markdown_toc_exact_short_live_canary.sh`.
- Controlled prompt: The exact short Japanese prompt produced by
  `_exactShortMvpPrompt` for `markdown_toc_generator.md`.
- Model: `qwen3.6-27b-vision` at
  `http://192.168.100.241:1234/v1`.

## Baseline

- The latest three pre-change runs were ready in 146.2, 90.6, and 181.2
  seconds, for a 139.3-second average.
- All three reached verifier success on turn 1 and created only
  `bin/markdown_toc.dart`.
- Two of the three requested both coding-continuation and turn-finalization
  recovery after terminal success. The third requested neither.
- The baseline predates adaptive entrypoint verification and the structured
  terminal-success finalization guard on the current branch.

## Validation Protocol

- Query `/v1/models` and require the named model before running.
- Run three canaries sequentially from the same clean commit.
- Require one direct Dart file under `bin/`, independent verifier success, and
  terminal-success evidence in every run.
- Inspect session logs for entrypoint diagnostics, file mutations, recovery
  requests, blocked goals, and post-success mutation attempts.
- If a run fails, classify the failure before changing the harness; do not
  weaken the verifier or acceptance gate.

## Acceptance Criteria

- All three runs are ready and pass the independent Markdown TOC verifier.
- Each run leaves exactly one direct `bin/*.dart` entrypoint.
- Missing, unexpected, and ambiguous entrypoint diagnostics are all absent.
- Coding-continuation and turn-finalization recovery request counts are zero.
- No verified run is blocked or attempts a mutation after verifier success.

## Verification

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
tool/run_coding_markdown_toc_exact_short_live_canary.sh
```

Run the command three times sequentially, then validate the generated summaries
and coding session logs.

## Handoff Notes

- Summary: The initial sample exposed a harness defect: adaptive entrypoint
  resolution selected `bin/generate_toc.dart`, but behavioral diagnostics
  still defaulted to `bin/markdown_toc.dart`. The selected path now propagates
  into all behavioral diagnostics, preventing repair through a stale canonical
  path and the resulting duplicate-entrypoint ambiguity.
- Tests run: `tool/codex_verify.sh --coverage` passed after the fix. Focused
  fixture and resolver tests passed 21 tests with 9 environment-gated Live
  tests skipped.
- Coverage or low-coverage notes: The new harness regression covers both TODO
  and Markdown TOC alternate entrypoints. Three consecutive Live runs on
  commit `70d6bc54` were ready in 682.1, 182.2, and 202.5 seconds.
- Live evidence: Run ids `1784012653`, `1784013349`, and `1784013548` all
  reached verifier success on turn 1, recorded zero coding-continuation and
  turn-finalization recovery requests, and were not blocked after success.
  The latter two runs created and verified only `bin/generate_toc.dart`; the
  first created and verified only `bin/markdown_toc.dart`.
- Risks or follow-ups: The first passing run required one goal continuation and
  four diagnostic-repair focus activations, so model repair latency remains
  variable even though the entrypoint and terminal-success gates are stable.
