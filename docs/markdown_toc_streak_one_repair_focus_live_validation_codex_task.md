# Markdown TOC Streak-One Repair Focus Live Validation

## Task

- Goal: Confirm that first-diagnostic repair focus improves convergence on a
  structurally different MVP without reducing completion reliability.
- User-visible behavior: A local model can assemble the Markdown TOC MVP from
  the exact short Japanese prompt and recover from verifier diagnostics without
  an unchanged verifier replay.
- Non-goals: Changing the Markdown TOC fixture, verifier, prompt, model, token
  budget, or tool-loop policy.

## Context

- Affected components: Coding Goal Auto-Continue, command-diagnostic repair
  focus, the Markdown TOC exact-short live canary, and canary reporting.
- Related docs:
  `docs/command_diagnostic_streak_one_repair_focus_codex_task.md` and
  `docs/coding_mvp_fixtures/markdown_toc_generator.md`.
- Reference command:
  `tool/run_coding_markdown_toc_exact_short_live_canary.sh`.
- Controlled prompt: The exact short Japanese prompt produced by
  `_exactShortMvpPrompt` for `markdown_toc_generator.md`.
- Model: `qwen3.6-27b-vision` at
  `http://192.168.100.241:1234/v1`.

## Baseline

- The latest three pre-change runs passed in 317.5, 535.1, and 118.6 seconds.
- The baseline pass rate is 3/3 and the average duration is 323.7 seconds.
- One baseline run required three Goal Auto-Continue requests; the other two
  completed without continuation.
- These reports predate command-diagnostic repair-focus observability, so they
  do not provide a reliable unchanged-replay count.

## Validation Protocol

- Run three canaries sequentially from the same clean commit.
- Require the independent acceptance verifier and terminal-success evidence in
  every run.
- Record repair-focus activation streaks, unchanged verifier replays before
  focus, maximum identical diagnostic streak, continuation count, and duration.
- Treat any failed acceptance criterion, post-success mutation, or blocked goal
  after verifier success as a regression requiring investigation.

## Acceptance Criteria

- All three runs pass the independent Markdown TOC verifier.
- Every authoritative diagnostic activates repair focus at streak 1.
- No run repeats an unchanged verifier before repair focus.
- No verified run is blocked or mutates files after verifier success.
- Results are compared with the 3/3, 323.7-second baseline.

## Verification

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
tool/run_coding_markdown_toc_exact_short_live_canary.sh
```

Run the command three times sequentially.

## Handoff Notes

- Summary: Three pre-guard runs passed in 231.6, 397.2, and 254.0 seconds.
  The 294.3-second average is 29.4 seconds (9.1%) faster than the 323.7-second
  baseline, while retaining a 3/3 pass rate.
- Tests run: All three clean-build exact-short Markdown TOC canaries passed the
  independent verifier and emitted terminal-success evidence.
- Risks: Model variance can dominate duration, so convergence signals and pass
  rate are primary; elapsed time is a secondary comparison.
- Live comparison: Runs 1 and 2 kept the maximum identical diagnostic streak at
  1. Run 3 activated repair focus at streak 1 but then performed three further
  read-only verifier replays, reaching streak 4 before a later mutation and
  successful verification. This exposed the need for the path-backed verifier
  replay guard documented in
  `docs/path_backed_verifier_replay_guard_codex_task.md`. Three post-guard runs
  also passed, in 177.7, 533.5, and 268.6 seconds. Their maximum identical
  diagnostic streaks were 0, 1, and 1. The slow run requested one unchanged
  verifier after repair focus; the guard blocked it, Goal Auto-Continue carried
  the diagnostic forward, and the next request performed the required edit.
