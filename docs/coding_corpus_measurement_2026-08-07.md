# Re-Measuring The Closed Decisions On Coding Data (2026-08-07)

Question this answers: **the edit-anchor thread was closed with "do not
implement", and LL34 was sized, on a corpus that turned out to be mostly chat
(`docs/canary_evidence_outside_the_corpus_2026-08-06.md`). Do those decisions
survive on the coding corpus?**

The anchor decision survives and gets stronger. LL34's sizing does not.

Every figure below was produced today with the same tools over both corpora, so
the comparison is apples-to-apples rather than against the July write-ups (the
chat corpus has drifted since; its anchor-failure count is 50 today, not 57).

| | chat (`~/.caverno`) | coding (`build/integration_test_reports`) |
|---|---:|---:|
| Files scanned | 1,743 | 481 |
| Sessions with tool traffic | 111 | 169 |
| Tool results | 1,421 | **3,773** |
| Distinct tools invoked | 35 | **10** |

## 1. The anchor decision survives — do not build hashline anchoring

`docs/edit_anchor_recovery_measurement_2026-07-21.md` declined a broad anchor
protocol change on three numbers. All three replicate on 2.5x the failures, in
the population where `edit_file` actually lives:

| | chat | coding | July decision needed |
|---|---:|---:|---|
| `edit_file` anchor failure rate | 50/133 = **37.6%** | 128/370 = **34.6%** | — |
| Next-edit recovery | 21/30 = **70.0%** | 46/60 = **76.7%** | high → don't build |
| Streaks stopping after one failure | 33/41 = **80.5%** | 97/111 = **87.4%** | high → don't build |
| Whitespace / indentation mismatch | 0 | 1 (0.8%) | ~zero → a normalizer moves nothing |

The coding numbers are *better*, not worse: recovery is 7 points higher and
streaks stop sooner. Whatever makes a weak model reconstruct an anchor from
memory, it also lets it correct the anchor on the next attempt more reliably
when it is actually doing coding work.

**The 37% is real and stable.** It reproduces at 34.6% on an independent,
2.8x-larger sample of `edit_file` calls. It was never a corpus artifact — which
also means the July doc's other conclusion stands: a 37% failure rate is worth
fixing *on its own terms*, just not with hashline anchors, because the failures
do not repeat.

One thing did move. The model gives up on `edit_file` and rewrites the whole
file more often in coding runs — `switched_to_write` is **29 of 128 (22.7%)**
against 8 of 50 (16.0%). Abandonment is also up (29.7% vs 24.0%). Neither is a
correctness failure, but a full-file rewrite is the expensive recovery, and this
is where the anchor defect's real cost shows up rather than in repeat failures.

**Conclusion: the anchor thread stays closed, now on both populations.** Reopen
it only if `switched_to_write` keeps climbing, which is a cheaper thing to watch
than a protocol change is to build.

## 2. LL34's sizing needs a coding-side re-read

`docs/ll34_tool_outcome_census_2026-07-21.md` sized the milestone from the chat
corpus: 41 of 106 tools ever invoked, 7 tools covering 41.3%, 8 covering 67.6%.
Coding runs are a different distribution entirely.

| tool | coding share | chat share |
|---|---:|---:|
| `read_file` | **39.5%** | 25.1% |
| `local_execute_command` | 18.7% | 22.0% |
| `write_file` | 11.3% | 9.3% |
| `edit_file` | 9.8% | 9.4% |
| `list_directory` | **9.6%** | 10.3% |
| `dart_analyze_feedback` | **7.9%** | 4.3% |
| `delete_file` | 1.2% | — |
| `dart_test_verification_evidence` | 1.2% | 1.2% |
| `update_goal` | 0.8% | — |

Three consequences, in order of how much they change the plan:

**a. The envelope set is worth more than the census claimed.** LL34's scoped
tools (command execution + filesystem mutations + `read_file` hash + test
runners) cover **81.7% of coding tool traffic**, against the 67.6% measured on
chat. The milestone is a better investment than its own sizing said.

**b. `read_file`'s hash is the right next field, more so than argued.** At
**39.5%** it is not merely the most-invoked tool, it is 2.1x the next one. The
census made this case at 26.3%.

**c. `dart_analyze_feedback` is not second-tier.** LL34 files it under "a
second-tier pass over `process_*` and `dart_analyze_feedback`". On coding runs
it is the **6th-largest tool at 7.9%**, ahead of every remaining scoped tool
except the big four, and it is a pure verification signal — exactly the kind of
fact the track wants typed. Together with `list_directory` (9.6%, no natural
outcome, correctly left text-only) it is most of the 18.3% the envelope does not
cover.

## 3. Commands fail 3x more often in coding runs

From the same census's payload facts, `local_execute_command` exit codes:

| | zero | non-zero | non-zero rate |
|---|---:|---:|---:|
| chat | 215 | 55 | **20.4%** |
| coding | 213 | 314 | **59.6%** |

Nearly six in ten commands fail during a coding run. This is the number behind
two other items: it is what makes LL34's `exitCode` field load-bearing rather
than cosmetic, and it is the mechanism under `tool_failure_abort` at 14.2%
(LL29's withdrawn gate). It also reframes the summary-first rendering idea in
LL34's scope — the deterministic one-liner would be describing a failure most of
the time, which is exactly when a weak model most needs it short.

The dominant coding error is unchanged from the anchor section:
`old_text was not found` at 128, more than 3x the next error.

## What was changed

`analyze_tool_results.iter_log_paths` — one shared discovery helper globbing
`**/*.jsonl`, used by `analyze_tool_results`, `analyze_edit_anchors`,
`analyze_edit_anchor_recovery`, and (inline) `analyze_deferred_verification`.
They had four copies of the same one/two-level glob, so pointing
`CAVERNO_SESSION_LOG_DIR` at the canary tree found the 198 `flutter_test.jsonl`
reporter files and **zero session logs**. Verified the widening changes nothing
on the chat corpus: identical 1,743 files found before and after.

## Verification

```bash
CAVERNO_SESSION_LOG_DIR="$(pwd)/build/integration_test_reports" python3 tool/analyze_edit_anchor_recovery.py
```

```bash
CAVERNO_SESSION_LOG_DIR="$(pwd)/build/integration_test_reports" python3 tool/analyze_tool_results.py
```
