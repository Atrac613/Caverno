# Codex Output Efficiency Investigation (2026-09-04)

## Technical summary

The existing Flutter test-output summarization is effective and should remain
the baseline. In a live focused run, it reduced the default model-visible test
command output from 844,725 bytes of detailed console output to a 137-byte
wrapper response, a 99.9838% reduction, while preserving the complete
machine-readable report and returning a correct `PASS 334 tests` verdict.

The bottleneck has moved. Across 10 recent Caverno-scoped Codex sessions,
repository search, process polling, and source reads accounted for 76.67% of
9,290,144 recorded output characters. Flutter test output accounted for only
0.47%. The resulting DX2-DX4 work now provides summary-first repository
discovery, log-first agent modes for selected long-running commands, and
progressive source/Git inspection guidance.

This investigation measures recorded output characters as a proxy for context
pressure. It does not establish exact billed-token savings.

## The shipped test-output change works

[PR #188](https://github.com/Atrac613/Caverno/pull/188) introduced the current
test-output path through two commits:

- `6be640ba4` added `tool/flutter_test_quiet.sh`, the JSON-log summarizer, and
  regression tests.
- `38f7b8d4e` made the quiet wrapper the default Flutter-test path in
  `tool/codex_verify.sh`, with `--raw-tests` as the escape hatch.
- Merge commit `ce7612562` is an ancestor of the current repository state.

The implementation preserves two local artifacts for diagnosis:

- `build/test_reports/flutter_test.json` contains the full JSON reporter log.
- `build/test_reports/flutter_test_stdout.txt` contains the complete captured
  console output.

The default response is one passing verdict, or bounded failure details with
the relevant test name, error, filtered stack, and test-local captured output.
Runs that end without a reporter result are classified as incomplete rather
than reported as an unexplained empty failure.

### Live verification

The 2026-09-04 focused run used
`test/features/chat/presentation/providers/chat_notifier_test.dart`.

| Measure | Result |
|---|---:|
| Passing tests | 334 |
| Detailed console output | 844,725 bytes / 10,524 lines |
| Full JSON report | 1,775,586 bytes |
| Passing summary body | 27 bytes |
| Complete wrapper response | 137 bytes |
| Model-visible output-size reduction | 99.9838% |
| Detailed-output to wrapper-response size ratio | 6,166x |

The five focused Python regression tests for
`tool/summarize_flutter_test_json.py` also passed.

```bash
tool/flutter_test_quiet.sh \
  test/features/chat/presentation/providers/chat_notifier_test.dart
python3 test/python/summarize_flutter_test_json_test.py
```

An adoption audit of four post-merge sessions found 24 Flutter-test commands:
19 invoked the quiet wrapper directly and five used `tool/codex_verify.sh`.
None selected the raw reporter. This confirms that the reduction is on the
normal agent path rather than only available as an unused utility.

The original commit message recorded a 3.4 MB green full-suite transcript and
one 12,867-token green run. Those historical numbers explain the change, but
this investigation did not reconstruct their billing record and does not use
them as a current token-savings estimate.

### Resolved verbose-output mismatch

`tool/flutter_test_quiet.sh --verbose` now selects and streams the expanded
reporter through `tee` while retaining `flutter_test_stdout.txt`. The default
path remains quiet. Repository-side regression tests cover both modes and
preserve the underlying Flutter exit status.

## Recent output is now dominated by discovery and polling

### Population and metric

The current-output census covers Caverno-scoped Codex sessions from 2026-08-30
through 2026-09-04. The active investigation session was excluded. It joins
recorded command invocations to their output by call identifier and measures
the characters stored in each model-visible command-result payload.

The ordered classifier assigns each multi-command invocation to the first
matching family. `process polling` identifies `write_stdin` polling behavior;
it does not identify the underlying process type.

| Output family | Outputs | Characters | Share | Average characters | Outputs at least 39k |
|---|---:|---:|---:|---:|---:|
| Repository search | 250 | 3,243,965 | 34.92% | 12,976 | 18 |
| Process polling | 473 | 2,044,135 | 22.00% | 4,322 | 21 |
| Source-file reads | 175 | 1,834,833 | 19.75% | 10,485 | 3 |
| Other commands | 206 | 795,317 | 8.56% | 3,861 | 3 |
| Git inspection | 186 | 726,540 | 7.82% | 3,906 | 2 |
| Build and release | 61 | 416,010 | 4.48% | 6,820 | 4 |
| Analysis and code generation | 38 | 110,996 | 1.19% | 2,921 | 0 |
| Mutations | 208 | 74,860 | 0.81% | 360 | 0 |
| Flutter tests | 72 | 43,488 | 0.47% | 604 | 0 |
| **Total** | **1,669** | **9,290,144** | **100.00%** | **5,566** | **51** |

Repository search is the largest single family. Search, polling, and source
reads together account for 76.67% of recorded output. Fifty-one results reached
at least 39,000 characters, so the totals are lower bounds where the agent
harness truncated output.

A separate four-session 2026-08-24 through 2026-08-27 sample contained
1,013,865 Flutter-test characters, or 9.18% of its 11,039,031 total. The recent
10-session sample contains 43,488, or 0.47%. The task mix and session counts
differ, so this is supporting evidence of a shifted bottleneck, not a causal
before-and-after estimate.

No chart is included because the ranked table carries both exact totals and the
classification caveats in less space than a chart plus an audit table.

## Output caps show where an implementation could matter

The following simulation clips each result independently at a proposed display
limit. It is a prioritization aid, not a savings forecast: some clipped output
would have to be reopened during diagnosis.

| Candidate family | Display cap per result | Recorded characters | Potentially clipped | Potential reduction |
|---|---:|---:|---:|---:|
| Repository search | 4,000 | 3,243,965 | 2,451,949 | 75.6% |
| Process polling | 1,000 | 2,044,135 | 1,858,831 | 90.9% |
| Source-file reads | 8,000 | 1,834,833 | 905,161 | 49.3% |
| Git inspection | 8,000 | 726,540 | 296,296 | 40.8% |
| Build and release | 4,000 | 416,010 | 292,504 | 70.3% |
| Analysis and code generation | 4,000 | 110,996 | 39,422 | 35.5% |
| Flutter tests | 2,000 | 43,488 | 16,584 | 38.1% |

Applying only the search and polling caps would have clipped 4,310,780
characters, 46.4% of the recent total. The production design must preserve an
explicit path to the full result and measure how often agents need it.

## Delivered implementation

### DX2: summary-first repository discovery

`tool/codex_rg.sh` is now the narrow wrapper for discovery searches. It does not
replace targeted raw `rg` used to confirm exact code or review
security-sensitive matches.

The default response contains:

- the `rg` exit status, match count, and matching-file count;
- a bounded, deterministic first-hit set;
- an explicit truncation marker;
- the path to a complete result under `build/codex_reports/`;
- a `--raw` escape hatch.

Nineteen repository-side tests cover `rg` match, no-match, and error exit
semantics; invalid patterns; Unicode paths and binary text; zero matches;
maximum-hit and line-length boundaries; complete artifact retention; the raw
escape path; selected-script integration; and the focused verification
contract.

Summary mode validates the captured stream and returns a wrapper error with an
instruction to use `--raw` instead of reporting zero matches when file-list,
count, quiet, help, version, or another non-match mode does not produce match
JSON. Complete search artifacts and diagnostic sidecars use owner-only
permissions.

A representative repository search found 3,241 matching lines across 1,035
files. The bounded response was 1,886 bytes versus 367,396 bytes of raw output,
a 99.49% reduction. Its complete JSON artifact was 1,341,927 bytes. Future
session audits should measure raw follow-up frequency before changing the
default display limits; this is an operational monitoring metric, not remaining
implementation scope.

### DX3: log-first selected long-running commands

The same full-log plus bounded-summary pattern is now available through
`--quiet-output` on these repository-owned entrypoints:

- `tool/release_ios_macos.sh`;
- `tool/publish_macos_sparkle_release.sh`;
- `tool/run_turn_steering_live_canary.sh`;
- `tool/run_pro_reasoning_live_canary.sh`.

The shared internal helper emits stage heartbeats, a final status, and a bounded
diagnostic tail on command failure. Each owning script retains its complete log,
exact command status, and release-specific marker interpretation. Raw streaming
remains the default for human-operated commands, while repository agent guidance
selects `--quiet-output`. The helper is intentionally sourced rather than
exposed as a generic arbitrary-command CLI.

Quiet execution installs scoped SIGINT and SIGTERM handlers, terminates the
running command, stops the heartbeat helper, reaps both processes, and restores
the caller's prior traps and umask. It preserves conventional exit statuses 130
and 143. Complete command logs use owner-only permissions.

Integration tests cover quiet success and failure, exact exit status,
heartbeats, raw streaming, release/appcast log retention, and live-canary log
and snapshot preservation. Eight existing Dart script-contract tests also pass.

### DX4: progressive source and Git inspection

Source reads and diffs are correctness evidence, so no automatic lossy wrapper
was added. `AGENTS.md` and `CLAUDE.md` now require this inspection sequence:

1. Locate files and symbols with a bounded discovery search.
2. Read only the relevant 200-300-line regions.
3. Begin Git review with stats and changed paths.
4. Inspect each material diff directly before concluding.

Promote this guidance to additional tooling only if future sessions show
repeated over-reading without a compensating diagnosis benefit.

### Lower-priority work

`tool/codex_verify.sh` still streams code generation, analysis, package tests,
and notification-relay commands through its general step runner. Their recent
combined share is small enough that they should reuse DX3's mechanism later,
not lead the next slice.

The in-app LL34 summary-first tool-result envelope is a separate product path.
It has a measured 62.8% deterministic prompt-token reduction for its validated
model profile, while the global default remains off. DX work must not silently
change that per-model product policy.

## Verification

The completed implementation passed:

- shell syntax checks for all changed shell entrypoints;
- Python bytecode compilation for the new helper and tests;
- 19 repository-side DX tests and five existing Flutter-report summarizer tests;
- eight focused Dart script-contract tests;
- two focused `tool/codex_verify.sh` invocations that collectively covered code
  generation, generated-file diff checks, project and workspace-package
  analysis, and the eight focused tests; the post-fix rerun completed
  successfully.

The standard verification run also exposed that focused analysis still invoked
the notification relay check even though `--all-suites` owns that expansion.
`tool/codex_verify.sh` now applies its existing focused-run guard to that check,
and the successful rerun confirms that the focused path remains focused.

## Limitations and decision guardrails

- Characters are a stable local proxy, not exact tokenizer output or billed
  Codex usage.
- Session selection is workload-dependent and is not a randomized comparison.
- Ordered heuristic classification can assign a multi-command invocation to a
  different family than a human reviewer would.
- Truncated command results make the high-volume totals lower bounds.
- A display-cap simulation assumes clipped content is unnecessary; real savings
  depend on full-result reopen frequency and diagnosis quality.
- Search and polling are eligible because they have high volume and natural
  summary contracts. Source and Git evidence require stricter preservation.
- The selected release and live-canary integration tests use fixture commands;
  they do not perform signing, uploads, or external LLM data export.
- Complete evidence remains in ignored `build/` paths until normal build cleanup
  or deliberate operator removal. Automatic deletion is intentionally absent
  because these artifacts can be required for release and failure diagnosis.

The promotion gate for every new quiet path is therefore two-dimensional:
reduce default output while preserving exit status, full evidence, and failure
diagnosis. Character reduction alone is insufficient.
