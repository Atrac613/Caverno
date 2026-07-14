# Japanese Structured Execution-Deferral Recovery

## Task

- Goal: Recover an active coding implementation turn when a model returns a
  Japanese execution plan instead of issuing the required first tool call.
- User-visible behavior: A short Japanese coding request proceeds into one
  bounded, tool-aware recovery rather than stopping after headings such as
  `Execution Plan` expressed in Japanese.
- Non-goals: Recovering ordinary planning sessions, executing commands parsed
  from prose, broadening recovery without an active executable workflow, or
  changing tool approval behavior.

## Context

- Affected files or components: Structured coding execution-deferral
  detection, initial coding continuation recovery, session-log summaries, and
  focused notifier tests.
- Related docs: `docs/structured_execution_deferral_recovery_codex_task.md`
  and `docs/session_logs.md`.
- Reference implementation or pattern: The existing English `Next Chunk` and
  `What I need to verify` recovery path.
- Known failure: Coding session
  `1972360e-8bac-4904-8911-1ea3077b2f98` had an active `implement` workflow
  whose required action was `execute`, but returned a Japanese execution plan
  with zero tool calls. The final-answer claim guard added
  `unexecuted_command_action_notice`, then the turn exited as `text_response`.

## Implementation Notes

- Preferred approach: Extend the pure detector with bounded Japanese planning
  markers, action-line verbs, question punctuation, and blocker phrases. Keep
  the existing active-goal and executable-workflow gate in the notifier.
- Constraints: Match the supplied incident response without treating a bare
  Japanese action sentence or a blocked/question response as executable
  deferral. Do not infer or execute a command from response text.
- Generated files needed: None.
- Migration or data compatibility concerns: The session-log summary schema may
  add a backward-compatible warning flag; no persisted application data
  changes are required.

## Similar-Pattern Search

- Search terms: `StructuredCodingExecutionDeferralDetector`,
  `unexecuted_command_action_notice`, `coding_action_promise_without_tool`, and
  `turnExit.transforms`.
- Files or modules inspected: The detector, coding continuation recovery,
  final-answer claim detector, turn-exit logging, log-summary tool, and their
  focused tests.
- Follow-up tasks found: Raw memory-extraction output drafted the one-off task
  as a fact, but this log does not prove that the candidate was persisted. Keep
  memory candidate filtering outside this recovery slice.

## Acceptance Criteria

- Required behavior: The exact Japanese plan shape from the incident triggers
  one recovery and executes the model's recovered native `read_file` call.
- Edge cases: English recovery remains unchanged; a bare Japanese future
  action, a question, a blocker, or a planning session does not trigger this
  structured recovery path.
- Failure paths: If bounded recovery still returns no tool call, existing
  unexecuted-action evidence and notices remain available.
- Observability: A logged `turn_exit` containing
  `unexecuted_command_action_notice` produces an explicit session-summary
  warning even when the preceding response does not match lexical heuristics.

## Verification

```bash
tool/codex_verify.sh --coverage
```

Run the detector, notifier continuation-recovery, and session-log summary tests
as focused checks before the full suite.

## Handoff Notes

- Summary: Added bounded Japanese planning markers, coding action lines,
  question punctuation, and blocker phrases to structured execution-deferral
  detection. Active executable goals recover through the existing native tool
  path, while the same plan without an active goal remains ordinary text.
  Session summaries now use the authoritative turn transform to report an
  unexecuted coding action even when lexical detection misses the response.
- Tests run: Focused detector and session-summary tests passed 16 tests. The
  exact active-goal notifier incident regression recovered to `read_file`, and
  the paired no-goal regression preserved the response without recovery.
  `tool/codex_verify.sh --coverage` passed code generation checks, analysis,
  and the full test suite.
- Coverage or low-coverage notes: Repository line coverage is 69.87%
  (49,242/70,480). The structured execution-deferral detector has 100% line
  coverage (14/14). Re-running the original incident log now reports one
  `coding_action_promise_without_tool` warning from line 3 instead of zero
  warnings.
- Risks or follow-ups: The language patterns remain intentionally narrow and
  still require a structured marker plus a coding target and action. A future
  Live run may not naturally reproduce this stochastic response shape; the
  exact response is therefore retained as deterministic regression evidence.
  Raw memory-extraction candidate quality remains a separate follow-up because
  this session does not show whether the one-off task fact was persisted.
