# Edit-Anchor Recovery Measurement (LL34 follow-up)

Branch this continues: `docs/grounded-verification-track` (15 commits ahead of
`main`, working tree clean, full suite green at 3931 tests).

## Task

- **Goal:** Measure whether an `edit_file` call that failed with
  `old_text was not found` succeeds on its *next* attempt against the same
  file, and report the distribution. This is a measurement task; it decides
  whether a fix is needed at all and, if so, which shape.
- **User-visible behavior:** None. This adds analysis tooling and a findings
  document. No app code changes.
- **Non-goals:**
  - Do **not** implement a fix for anchor failures in this task. The whole
    point is that four fixes were proposed today from plausible reasoning and
    all four were mis-aimed; this measurement exists to stop the fifth.
  - Do not change `FilesystemTools.editFile`, its error payload, or the hint
    text.
  - Do not touch the `ToolOutcome` / `CommandPayloadFacts` work already landed.

## Context

### What prompted this

`edit_file` fails with `old_text was not found` in **57 of 155 calls (37%)**
across 999 local session logs, in 33 sessions. Classifying those 57 by *why*
the anchor missed (`tool/analyze_edit_anchors.py`) gives:

| Bucket | Count | Share |
|--------|------:|------:|
| No `current_content` (file >4 KB) | 23 | 40.4% |
| Absent entirely | 19 | 33.3% |
| First line matches, block drifted | 12 | 21.1% |
| Already applied (`new_text` is in the file) | 3 | 5.3% |
| Whitespace differs | 0 | 0% |
| Indentation differs | 0 | 0% |

Of the 34 classifiable failures, **91% are the model writing `old_text` from
memory instead of copying it verbatim.** Whitespace and indentation — the
intuitive explanation — account for none.

The open question this task answers: when a failure returns `current_content`
(files ≤4 KB), does the model's next attempt succeed? If it does, the loop is
self-correcting and a fix is low value. If it does not, the failure is
structural and the hashline direction below becomes worth costing.

### Affected files or components

- `tool/analyze_tool_results.py` — the record-parsing instrument. Reuse its
  `iter_records`, `log_dir`, `TOOL_SECTION`, `RESULT_MARKER`,
  `split_tool_sections`. **Import it; do not re-implement log parsing.**
- `tool/analyze_edit_anchors.py` — the per-failure classifier. The new work is
  its sequential sibling; follow its structure and docstring style.
- `tool/triage_session_logs.py` — existing triage; the re-read distribution
  baseline lives here.
- Read-only reference: `lib/features/chat/data/datasources/filesystem_tools.dart`
  (`editFile`, `preflightEditFile`, `_editPreconditionResult`,
  `_oldTextNotFoundError` around line 783).

### Related docs

- `docs/reread_loop_mechanism_2026-07-21.md` — **read this first.** It records
  the measurement, the corrections, and the instrument failures. The
  "Instrument failure" section is not optional background; it is the list of
  traps you will otherwise walk into.
- `docs/ll34_tool_outcome_census_2026-07-21.md` — tool traffic distribution and
  its verification.
- `docs/grok_build_comparison_2026_07_21.md` — where the hashline idea comes
  from, and the local-first constraints on adopting anything from that source.
- `docs/local_llm_agent_roadmap.md` — LL34 in the Grounded Verification Track.

### Known quirks — session log analysis

These cost most of a session to discover. Every one produced a wrong published
number before it was found.

1. **Never grep the concatenated log text.** Each record carries the whole
   conversation, so messages replay: 13783 message slots collapse to 2011
   distinct, **6.9x**, and unevenly (early turns replay more). De-duplicate by
   `message['id']` per session file, as `analyze_tool_results.py` does.
2. **Never substring-match payload prose.** Tool payloads embed file content:
   the not-found error inlines `current_content`, so matching `not found`
   counted 64 lines of a TODO app printing "item not found" as tool errors.
   Parse the payload as JSON and read the field.
3. **A count derived from grep was off by 17x** (982 reported, 57 real). If a
   number looks large, suspect the method before believing the number.
4. **A classifier that puts ~100% in one bucket is broken until proven
   otherwise.** This happened twice today: once from an unescaped-pattern
   mismatch, once because slicing off the `\nResult:\n` marker also removed the
   newline the `Arguments:` regex required. Both produced tidy, meaningless
   output. Add a canary bucket that must stay empty (e.g. "verbatim present",
   which is impossible for a failed anchor) and assert it.
5. `[Tool: <name>]` markers *are* reliable — verified against the instrument
   within 0.1 points — because the marker resists contamination and tool-result
   messages happen to be barely replayed. Nothing else about grep is reliable.

## Implementation Notes

- **Preferred approach:** a new `tool/analyze_edit_anchor_recovery.py` that
  walks each session's distinct messages **in order**, tracks `edit_file`
  attempts per `path`, and for each failure records what happened on the next
  attempt against that same path:

  | Outcome | Meaning |
  |---------|---------|
  | `recovered_next` | Next attempt on that path succeeded |
  | `failed_again` | Next attempt on that path failed too |
  | `abandoned` | No further attempt on that path in the session |
  | `switched_to_write` | Next mutation on that path was `write_file` |

  Report counts, the distribution of consecutive-failure run lengths (how deep
  do the streaks go), and split by whether `current_content` was returned
  (≤4 KB) or not (>4 KB) — that split is the whole point, since it separates
  "was handed the file and still missed" from "was told to re-read".

- **Also worth capturing while you are in there:** whether a `read_file` on the
  same path occurs between the failure and the next attempt. That is the direct
  link between anchor failure and the re-read statistic, which is currently
  established only by session-level co-occurrence (19 of 23) and one traced
  session — **not** by counted evidence. If you can produce that number, say so
  explicitly, because it upgrades or kills the causal claim.

- **Constraints:**
  - Pure `python3` stdlib, no dependencies, consistent with the existing tools.
  - Honor `CAVERNO_SESSION_LOG_DIR` / `CAVERNO_HOME`.
  - Keep it read-only; never write into `~/.caverno`.
  - Docstring must state what the tool corrects for (replay, contamination),
    following `analyze_tool_results.py`.

- **Generated files needed:** none. No Freezed/JSON codegen in this task.
- **Migration or data compatibility concerns:** none.

## Similar-Pattern Search

- **Search terms:** `old_text`, `not found`, `already_applied`,
  `preflightEditFile`, `_editPreconditionResult`, `edit_mismatch`.
- **Files or modules to inspect:** `filesystem_tools.dart` has a
  `preflightEditFile` path and an `already_applied` precondition result that
  the classification barely saw (3 of 57). Check whether preflight is actually
  reached in the failing flows, or whether it is bypassed — if preflight would
  have caught these and is not running, that is a different and cheaper finding
  than anything in this document.
- **Follow-up tasks found:** record any in the handoff notes rather than
  expanding this task.

## Acceptance Criteria

- **Required behavior:** `tool/analyze_edit_anchor_recovery.py` runs against
  the local logs and prints the recovery distribution, streak lengths, and the
  ≤4 KB / >4 KB split, with the replay factor it corrected for shown the way
  `analyze_tool_results.py` shows it.
- **Edge cases:**
  - Sessions with a single edit attempt (no "next attempt") must land in
    `abandoned`, not be silently dropped.
  - Multiple files edited in one session must be tracked per path, not
    globally.
  - Unparseable payloads and missing `Arguments:` lines must be counted in an
    explicit bucket, never silently skipped — a silent skip is what hid the
    first broken run.
- **Failure paths:** if the classifiable population is under ~20 attempts, say
  so and treat the result as indicative rather than conclusive. 57 failures is
  already a small n; the recovery subset will be smaller.
- **Accessibility, localization, or platform expectations:** none; this is a
  developer tool with English-only output.

## Verification

```bash
python3 tool/analyze_edit_anchor_recovery.py
python3 tool/analyze_edit_anchors.py          # must still reproduce 57 / 4 buckets
python3 tool/analyze_tool_results.py --tool edit_file
```

No Dart changes, so `tool/codex_verify.sh` is not required for the tool itself.
Run it if you touch anything under `lib/`.

## The decision this feeds

Do not skip this section; it is why the measurement is worth doing.

- **If failures largely recover on the next attempt** — the loop is
  self-correcting, the 37% is noisy but not structural, and the right outcome
  is to record that and close the thread. No fix.
- **If failures largely repeat, especially with `current_content` already
  supplied** — the model cannot reproduce a verbatim multi-line anchor even
  when handed the file, and supplying more content will not help. That is the
  case where **hashline-style anchoring** becomes worth costing: address a
  region by line number plus a content hash, with bounded re-location when the
  line has shifted, instead of quoting the block back. See
  `docs/grok_build_comparison_2026_07_21.md`; Grok Build ships this as
  `grok_build_hashline` with three candidate schemes and its own benchmark
  harness. Adopt the design, not the code — that source is Apache-2.0 and
  in-tree copying would need NOTICE handling.
- **Either way, propose the next task rather than starting it.** Today's
  pattern was that every plausible mechanism turned out to be the wrong one,
  and the only claims that survived were the counted ones.

## Handoff Notes

- **Summary:** LL34's exit-status and mutation facts have shipped
  (`ToolOutcome` in `packages/caverno_tool_contracts`, `McpToolResult.outcome`,
  producers for `git_execute_command`, `git_finish_worktree_session`,
  `local_execute_command`, and the filesystem mutation funnel; consumers in
  `ToolFailureClassifier` and the `write_file` operation note). This task does
  not extend that work — it measures whether the next piece is justified.
- **Tests run before handoff:** `flutter analyze` clean; `flutter test` 3931
  passing; ratchet budgets lowered for four files that were extracted to make
  room (`mcp_tool_result_normalizer` 126→106,
  `built_in_local_command_tool_handler` 581→341, `filesystem_tools` 1282→1243,
  `built_in_filesystem_tool_handler` 622→343).
- **Coverage notes:** the new tools under `tool/` are analysis scripts and are
  not covered by the Dart suite, consistent with `triage_session_logs.py`.
- **Risks or follow-ups:**
  - `read_file`'s content hash is still unbuilt. It is coverage and
    cross-parameter comparison, **not** the causal fix — that claim was
    corrected twice and the correction is recorded.
  - `edit_file` does not yet report its own `changed` fact; the funnel lifts
    one but the payload does not supply it.
  - Second-tier outcome fields: `process_*` (6.7% of traffic) and
    `dart_analyze_feedback` (2.7%).
  - Unmerged branches touch two files this work is adjacent to:
    `feature/chat-notifier-refactor-slices` holds +194 lines of
    `local_shell_tools.dart`, `feature/discovery-zero-match-hints` holds +82 of
    `tool_result_prompt_builder.dart`. Neither conflicts with this task.
