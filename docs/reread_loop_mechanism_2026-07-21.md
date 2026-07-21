# Re-read Loop: What Actually Drives It (2026-07-21)

Question this answers: **the LL31 triage says redundant file re-reads are the
dominant real failure — what mechanism produces them?**

This was run to validate a causal claim before continuing to build on it. The
claim did not survive.

## Method

Over the 992 local session logs, count read-heavy sessions (≥3 `read_file`
renders) and check which mutation signals appear alongside the re-reads:
`old_text was not found` (an edit whose anchor did not match) versus
`no_change` / `already_applied` (a mutation that ran and changed nothing).

## Result

| Population | Sessions |
|------------|---------:|
| Read-heavy sessions (≥3 reads) | 46 |
| …with any `edit_file` | 23 |
| …showing `not found` (anchor mismatch) | **19** |
| …showing `no_change` / `already_applied` (no-op mutation) | **1** |

The 23 read-heavy sessions with **no edits at all** are a separate population:
pure redundant reading with no mutation involved (`ad90955c` — 44 reads, 0
edits; `b73801da` — 27 reads, 0 edits; `f6ffbf97` — 23 reads, 0 edits). Those
are context-digest territory (LL30), not mutation-feedback territory.

So the re-read population splits three ways:

1. **No mutation at all** — 23 of 46. The model re-reads without editing.
2. **Edit anchor mismatch** — 19 of 23 edit-bearing sessions. The dominant
   mutation-linked driver.
3. **No-op mutation** — 1 of 23. Rare.

## Consequence: a correction, the second on this claim

`docs/ll34_tool_outcome_census_2026-07-21.md` first claimed the `read_file`
content hash addressed the dominant failure; that was corrected to the mutation
`changed` fact. **That correction was also wrong.** The `changed` fact targets
population 3 — one session in twenty-three.

The shipped `changed` work is not wasted: a byte-identical write really was
indistinguishable from a real one, and the fact closes that ambiguity cheaply.
But its billing as "the signal behind the dominant measured failure" is not
supported by the logs, and this document supersedes that claim.

The general lesson is narrower than "measure first": all three claims came from
reading code and reasoning about plausible mechanisms. Each was plausible. The
distribution was only knowable by counting.

## Where the evidence actually points

The worst offender, session `119292cb` (11 identical reads), shows the pattern
directly: `read → edit → edit → read → read → edit → …`, 12 edits against 10
byte-identical reads, with 29 `not found` occurrences and zero no-op reports.
The model was not writing identical content — its edit anchors kept missing.

And the harness participates in the loop. `FilesystemTools._oldTextNotFoundError`
(`filesystem_tools.dart:783`) branches on file size:

- **≤4096 bytes**: inlines `current_content` so the model can copy `old_text`
  verbatim. Good — no re-read needed.
- **>4096 bytes**: the hint reads *"Re-read the file and copy old_text verbatim
  from its current content"*.

For any file over 4 KB — which is most source files — **the harness instructs
the re-read that then shows up in the triage as redundant**. The loop is not
purely a model failure; the tool asks for it, the model complies, the anchor
misses again, and the cycle repeats.

## Instrument failure: occurrence counts in this document are not trustworthy

Following up on the proposed target below produced a methodological finding
that partially undermines this document's own numbers. Recorded here rather
than quietly fixed, because the counts were already acted on.

**Contamination 1 — substring matching against inlined file content.** The
`old_text` not-found error inlines `current_content` for files ≤4096 bytes, so
the *file being edited* becomes part of the log text. In session `73fa0bf3`, 84
occurrences of `not found` break down as 20 real tool errors and **64 lines of
the app's own source** (a TODO CLI that prints `Todo item ... not found`).
Every count in this document derived from the loose string `not found` is
inflated by an unknown amount.

**Contamination 2 — errors with no corresponding tool call.** Re-running with
the exact error string `old_text was not found` gives 982 total occurrences,
but only 99 carry either hint variant, and several of the worst sessions have
**zero** `[Tool: edit_file]` renders while showing dozens of errors
(`0461c455`: 10 reads, 0 edits, 55 errors; `d65fa545`: 0 reads, 0 edits, 36).
An error cannot occur without an edit, so the text is reaching the log by some
path other than a rendered tool result — most plausibly conversation history
replayed into each record. That was not accounted for, and it means **no
per-occurrence figure here is defensible.**

What survives:

| Claim | Status |
|-------|--------|
| 46 read-heavy sessions; 23 with edits; 19 with a real not-found | Session-level presence, re-verified with the exact error string — **holds** |
| 23 of 46 read-heavy sessions involve no mutation at all | Presence-based — **holds** |
| Session `119292cb` shows read/edit alternation with failing anchors | Single traced session — **holds as n=1** |
| "29 not-found occurrences" in `119292cb` | **Withdrawn** (contamination 1) |
| 73% / 27% split between the two hint branches | **Unverified** — the hint strings are distinctive enough to avoid contamination 1, but the 99 occurrences may still be replay-inflated |

The pattern that prompted this check — a model re-issuing an edit it had already
applied successfully (visible in `73fa0bf3`, rows 7-8: the identical
`TodoList._();` → `TodoList();` edit succeeding then failing) — could not be
counted at all: the extraction matched 2 of that session's not-found edits.
A null result from a broken instrument is not a null result, so no claim is
made about its frequency.

**Before any further claim about this loop, the instrument has to be fixed:**
parse the log records and count each tool result once, in the record where it
first appears, instead of grepping the concatenated text. That belongs in
`tool/` next to `triage_session_logs.py` so the next question costs seconds
rather than a rebuild — the ad-hoc scripts behind this document were thrown
away, which is part of why it took four attempts to notice they were wrong.

## Proposed next target (not yet built, and not yet justified)

Give the large-file branch what the small-file branch already gives: enough
current content to copy from, without a full re-read. Rather than inlining a
whole large file, locate the region the failed `old_text` most nearly matches
and return that window, so the model can correct its anchor in place.

Acceptance would be measured, not argued: `tool/triage_session_logs.py` already
reports the re-read distribution, and this document's counts are the baseline
to compare against. The build provenance recorded in each session log
(`build.commit`) makes before/after separable.

Baseline at the time of writing (all logs predate the LL34 work):

- 1498 turns scanned, 97.9% exiting `text_response`
- 46 sessions with any byte-identical re-read
- worst single repeat: 11 identical reads
