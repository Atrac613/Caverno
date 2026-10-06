# Caverno v1.3.35

> Release date: 2026-09-19

## Summary

Chat turn-lifecycle hardening (cut-off detection, truncation recovery, tool-result history), diagnostics tool-depth ladder and probe grading fixes, and consolidated test suites.

## Changes

### Features

- **Cut-off reply detection** — Distinguish a cut-off reply from a finished one so the UI can offer resume.
- **Carried read-only results** — Carry recent read-only tool results into the follow-up turn instead of discarding them.
- **Tool-refusal scoring** — Score what the model does when a tool refuses a call.
- **Tool-depth ladder v2** — Harden the tool-depth rungs and add a tool-chain depth ladder above the conformance floor.
- **Ladder rung classification** — Tell a failed ladder rung from one that never fit.

### Fixes

- **Turn resume after cut-off** — Resume a turn that was cut off before it acted on anything.
- **In-loop truncation recovery** — Let an in-loop truncation reach the recovery path that exists for it.
- **Tool-result history role** — Send carried tool results as history, not as a fresh batch.
- **Inline reused tool results** — Inline a reused tool result the request does not carry.
- **Qwen3.8 thinking suppression** — Apply thinking suppression to every Qwen3.8 build.
- **Read-only command re-run** — Let a read-only command re-run instead of ending the turn.
- **Session-log tool defects** — Repair four tool defects found in three session logs.
- **Roadmap-slice defects** — Repair three defects found scoping the next roadmap slices.
- **Remote-coding reconnection** — Keep automatic reconnection alive after the first ladder.
- **search_files path honesty** — Stop search_files lying about a path it can read.
- **Reworded call double-execution** — Stop a reworded call running twice off one approval.
- **Diagnostics probe grading** — Fix token-cap scoring, multi-round grading, vision-probe grading, staircase mid-loop answers, unrun-ladder reporting, /v1/models generation waste, saved-run model labelling, and structured-output arm parity.
- **Firebase resolutions** — Restore the Firebase resolutions the merge dropped.

### Testing

- **Suite consolidation** — Fold 53 tool-script suites, 59 chat suites, and 31 domain-service suites into single files.
- **FileMutationPathFence coverage** — Add behaviour tests for FileMutationPathFence.
- **Notification fixture clock** — Keep mobile notification fixtures on the wall clock.
- **Pin refresh** — Refresh two pins the code had already moved past.

### Documentation

- **CLAUDE.md split** — Split CLAUDE.md into focused reference documents.
- **Agent guidance** — Streamline agent guidance.
- **Diagnostics budget note** — Record that a bigger budget did not fix two probes.

### Dependencies

- serious_python 4.6.0 → 4.7.0
- mobile_scanner 7.4.0 → 7.4.2
- dartssh2 3.3.1 → 4.1.0
- wifi_scan 0.4.1+2 → 0.5.0
- firebase-admin 14.4.0 (services/notification_relay)
- actions/setup-java 6.0.0 → 6.0.1

## Version

- `1.3.35+48`

## Notes

This release focuses on chat turn-lifecycle robustness (cut-off detection, truncation recovery, tool-result history semantics) and diagnostics probe accuracy. Test suite consolidation reduces CI overhead. Six Dependabot updates (five dependency bumps and one CI action bump) are included.
