# Codex Task: Guard Against Deliverable Claims Naming Files Never Written

Caverno's ChatNotifier already neutralizes false *command/execution* claims
(unexecuted command action notices, failed-command success-claim
replacement, unverified read-only inspection notices — see
`chat_notifier_unexecuted_action_recovery.dart` and friends). There is no
equivalent for *file deliverable* claims: a final answer can list files as
"created/updated" that were never written by any tool call in the turn, and
nothing fires. Add that guard, following the existing guard architecture.

## Motivating Evidence (do not skip)

Session `~/.caverno/session_logs/coding/fc1c1bbf-95ec-4541-b302-e8d9f3d6c660.jsonl`
(2026-07-10, CMVP-1 fixture, Dart pinned, fresh `tmp/todo`):

- The turn's only file mutations were `write_file pubspec.yaml`,
  `write_file lib/models/task.dart`, and two `edit_file` calls on the same
  `task.dart`. Zero commands were executed.
- The final answer declared the MVP implemented and listed four
  deliverables, including **`lib/storage.dart` (新規作成)** and
  **`lib/main.dart` (新規作成)** — neither file was ever written; neither
  exists on disk. The runnable program does not exist.
- The only transform that fired was `unexecuted_command_action_notice`
  (about the untested state). The fabricated file list itself passed through
  untouched, so on screen the user saw a mostly-credible deliverable
  summary for a deliverable that is 50% fictional.

This is a coding-mode failure class the existing guards were built for —
claims not backed by tool results — just on the file axis instead of the
command axis.

## Task

- Goal: when a coding-mode assistant answer claims specific file paths were
  created/written/updated in this turn, and a claimed path has no successful
  `write_file` / `edit_file` / `rollback_last_file_change` result in the
  turn, append a guard notice naming the unbacked path(s) (same
  notice-appending mechanism as the existing unexecuted-command guards) and
  record a transform in `turn_exit.transforms[]`.
- Strengthening signal (cheap, do it): if the claimed path also does not
  exist on disk at finalization time, say so explicitly in the notice
  ("listed as created but does not exist"). A path that exists but was not
  written this turn gets the softer "not modified in this turn" phrasing —
  it may be a pre-existing file the model is legitimately describing, so
  the notice must not overclaim either.
- Non-goals:
  - Do not block or rewrite the model's answer beyond the established
    notice-appending pattern; guards annotate, they do not censor.
  - No LLM secondary call; this is a deterministic cross-check of claimed
    paths vs the turn's tool results (the agreed escalation path for
    smarter completion verdicts is a separate track).
  - Do not fire on general prose mentioning files (reading, planning,
    describing existing code) — only on deliverable-style claims (see
    Context for the trigger shape).
  - General-workspace (non-coding) turns are out of scope.

## Context

- Guard family and mechanics to mirror:
  `chat_notifier_unexecuted_action_recovery.dart`
  (`_buildUnexecutedCommandActionToolResult`,
  `_appendUnexecutedCommandActionNoticeIfNeeded`) and the finalization path
  in `chat_notifier_response_finalization.dart`. Transforms are recorded to
  the session log's `turn_exit` entry — follow the same registration so
  `tool/triage_session_logs.py` picks the new transform up.
- Turn-scoped tool results are available at finalization
  (`_latestCompletedToolResults` / the executed tool-result list in the tool
  loop); successful writes carry the resolved absolute `path` in their
  result payload (see `write_file`/`edit_file` result JSON:
  `{"path": ..., "replacements": ...}` etc.).
- Claim extraction: keep it deterministic and conservative. Trigger shape:
  the answer names a path-like token (contains `/` or a known source
  extension) in the same sentence/list item as a creation/update claim
  (Japanese and English: 作成 / 新規作成 / 更新 / 追加しました / created /
  added / updated / wrote). A useful precedent for path extraction already
  exists in `file_reference_extractor.dart` — reuse it rather than writing a
  new regex zoo.
- Path normalization: claimed paths may be relative (`lib/main.dart`) while
  results carry absolute paths — normalize against the selected coding
  project root (the same resolution `_resolveProjectScopedArguments` uses).
- False-positive discipline: the guard fires only when BOTH (a) the claim
  verb is creation/update-class and (b) the path has no successful mutation
  result this turn. When in doubt (ambiguous verb, path outside the project
  root), stay silent. A guard that over-fires gets neutered later — see the
  PR #103 lesson on the read-only inspection guard.

## Similar-Pattern Search

Grep the existing guard tests (`test/features/chat/**` for
`unexecuted_command_action_notice` / success-claim replacement) and mirror
their structure: deterministic predicate unit tests + a `sendMessage`-level
repro asserting on `state.messages.last.content`.

## Acceptance Criteria

1. Repro test of the motivating session shape: turn writes `a.dart`, final
   answer claims `a.dart` and `b.dart` were created → notice appended naming
   only `b.dart`, transform recorded; with `b.dart` absent on disk the
   notice uses the "does not exist" phrasing.
2. No-fire cases: answer describes reading/plans ("`b.dart` を確認します"),
   answer names a pre-existing file without a creation verb, answer claims a
   file that WAS successfully written this turn, non-coding workspace turn.
3. Pre-existing-file case: `b.dart` exists on disk but was not modified this
   turn, answer says "`b.dart` を更新しました" → softer "not modified in
   this turn" notice.
4. The new transform name appears in `turn_exit.transforms[]` and is counted
   by `tool/triage_session_logs.py` without changes to that script (it
   aggregates transforms generically — verify, don't assume).
5. `flutter analyze` and `flutter test` pass.

## Verification

Run the new tests plus the existing guard suites. Manual dogfood per
`docs/coding_mvp_fixtures/README.md`: re-run the CMVP-1 Dart-pinned
controlled run and confirm a fabricated deliverable list gets annotated on
screen.

## Handoff Notes

Log the guard's firing rate in the PR after the dogfood run — if it fires on
legitimate answers, tighten the claim-verb list before merging rather than
shipping an over-eager guard. English only in code/comments/commit messages
(repo rule).
