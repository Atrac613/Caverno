# Edit-Anchor Recovery Measurement (2026-07-21)

Question this answers: **after `edit_file` reports `old_text was not found`,
does the next edit of that file recover, and does returning
`current_content` change the result?**

## Method

`tool/analyze_edit_anchor_recovery.py` walks the 999 local session logs in
message order and reuses the record and tool-section parsing from
`tool/analyze_tool_results.py`. Within each session it:

1. de-duplicates replayed messages by stable message id;
2. JSON-parses result payloads instead of matching payload prose;
3. tracks each failed anchor by normalized file path;
4. finds the next `edit_file` or `write_file` action on that file;
5. records same-file `read_file` calls before that action; and
6. counts consecutive anchor-failure streak lengths.

The path key uses the final parent plus basename, matching the existing
re-read triage normalization. This joins relative and absolute spellings of
the same file. Same-named files in the same final directory can collide, but
none appeared in the traced failures.

The parser corrected **13,783 message slots to 2,011 distinct messages
(6.9x replay)**. All 57 known anchor failures were retained. The
`old_text-in-current_content` canary remained zero, and the current-content
split reproduced the independent classifier exactly: 34 with content and 23
without it.

## Result

| Next same-file action | All failures | With `current_content` | Without `current_content` |
|---|---:|---:|---:|
| Next edit succeeded | **24** | 14 | 10 |
| Next edit failed | **12** | 8 | 4 |
| Switched to `write_file` | **5** | 5 | 0 |
| No later mutation of that file | **16** | 7 | 9 |
| **Total** | **57** | **34** | **23** |

Among the 36 failures followed by another edit, **24 recovered and 12 failed:
a 66.7% next-edit recovery rate**.

The content split does not show a benefit from inlining the small file:

| Failure payload | Recovered | Failed again | Recovery rate |
|---|---:|---:|---:|
| With `current_content` | 14 | 8 | **63.6%** |
| Without `current_content` | 10 | 4 | **71.4%** |

This is a small observational sample, so the eight-point difference is not a
claim that withholding content helps. It does rule out a large visible benefit
from the current inline-content mechanism in these logs.

## Direct re-read link

The sequential pass replaces the previous session-level co-occurrence claim
with a direct count:

| Failure payload | Failures followed by another edit | Same-file read before it | Recovered after that read |
|---|---:|---:|---:|
| With `current_content` | 22 | **3** | 2 |
| Without `current_content` | 14 | **14** | 10 |
| **Total** | **36** | **17 (47.2%)** | **12** |

Every large-file failure that reached another edit performed the instructed
same-file re-read first: **14 of 14**. The harness-to-re-read link is therefore
counted evidence, not just co-occurrence.

That re-read does not establish a causal recovery benefit. Next edits recovered
after 12 of 17 reads (70.6%) and after 12 of 19 no-read paths (63.2%). The
sample is too small for that difference to be meaningful, and the no-read group
is dominated by small files that already supplied their content.

The abandoned group also matters: 11 of 16 failures performed a same-file read
but never attempted another same-file mutation. A re-read can therefore be a
cost without producing a measured recovery attempt.

## Failure streaks

| Consecutive anchor failures | Runs | Failures represented |
|---:|---:|---:|
| 1 | 38 | 38 |
| 2 | 6 | 12 |
| 3 | 1 | 3 |
| 4 | 1 | 4 |

There were 46 streaks. **38 (82.6%) stopped after one anchor failure**; eight
continued, and the longest contained four failures. Repeated misses are real
but are not the dominant shape.

## Instrument-quality findings

The analyzer reports every format problem instead of silently dropping it.
The corpus contained one rendered `edit_file` section without a `Result:`
marker and therefore one unparseable edit payload; it was not one of the 57
anchor failures. It also found 184 non-JSON `read_file` payloads, which are
legacy/raw content results and do not prevent read tracking because the path is
parsed from `Arguments:`. Ten pathless `write_file` renders and two missing
write argument lines were left unassociated rather than guessed. Every anchor
failure still lands in an explicit outcome, so the 57-failure total is
conserved.

The synthetic regression test covers replay, multiple paths, small/large-file
splits, a same-file read, a repeated failure, recovery, `write_file` fallback,
abandonment, streak lengths, and a missing `Arguments:` line.

## Preflight inspection

The cheaper-bypass hypothesis does not hold in the current code:

- `ChatNotifier._handleEditFile` calls `FilesystemTools.preflightEditFile`
  before approval or execution.
- `FilesystemTools.editFile` calls the same `_editPreconditionResult` again
  before writing.
- The built-in filesystem handler reaches `FilesystemTools.editFile`, so its
  direct path also runs the shared precondition.

The three previously classified “already applied” failures are therefore
classification facts about the attempted anchor/new text, not evidence that
the preflight path was skipped.

## Decision

Do **not** implement a broad anchor protocol change from this measurement.
When the model makes another edit attempt, two thirds recover immediately;
83% of failure streaks stop at one; and returning the whole small file does not
produce a visible recovery advantage. The evidence does not meet the handoff's
threshold of failures “largely repeating, especially with
`current_content` already supplied,” so hashline-style anchoring is not yet
worth adding to the runtime surface.

This does not make the original 37% anchor-failure rate acceptable. It narrows
the opportunity: the remaining structural population is 12 failed next edits,
including eight after `current_content`, rather than all 57 failures.

## Proposed next task

Close this edit-anchor recovery thread without an app fix and return to
**LL30's compaction structural pre-pass**, scoped first to the 23 read-heavy
sessions that contain no edit at all. That population cannot benefit from edit
anchoring and is the cleanest remaining target for reducing redundant reads.

If anchor work is reconsidered later, first add a post-build cohort comparison
using the session log's build provenance and require the repeated-failure
population to grow beyond this 12-attempt baseline before costing hashline
anchoring. Do not start that implementation from the present sample.

## Verification

```bash
python3 test/python/analyze_edit_anchor_recovery_test.py
python3 tool/analyze_edit_anchor_recovery.py
python3 tool/analyze_edit_anchors.py
python3 tool/analyze_tool_results.py --tool edit_file
```

No Dart or generated files changed, so the Flutter verification suite is not
required for this measurement-only task.
