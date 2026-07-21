# LL34 Tool-Outcome Census (2026-07-21)

Question this answers: **how much of Caverno's real tool traffic can carry a
structured outcome envelope, and how many tools have to be touched to get it?**

LL34 was scoped from reading code (four consumers re-parsing the same result
string). Before writing its acceptance criteria, the payoff needed a number —
if only a handful of rarely-used tools had a natural outcome, the milestone
would be mostly ceremony.

## Method

Two counts, because the obvious one is misleading.

**Registered tools** come from `BuiltInToolRegistry`
(`lib/features/settings/domain/entities/built_in_tool_info.dart`): **106**.

**Invoked tools** come from the local session logs
(`~/.caverno/session_logs/{chat,coding,routines}`, 992 files), counted by the
`[Tool: <name>]` marker that `ToolResultPromptBuilder.formatToolResults` emits
for every rendered tool result. Counting `"name":"<tool>"` instead does **not**
work: every request ships the full tool catalog (the intentional LL6
prefix-stable payload), so each tool floors at ~2594 matches whether or not it
was ever called. That baseline is catalog, not traffic.

Result: **41 of 106 registered tools are ever invoked**, across **2153** tool
result renders.

## Traffic distribution

| Tool | Renders | Share | Sessions |
|------|--------:|------:|---------:|
| `read_file` | 566 | 26.3% | 75 |
| `local_execute_command` | 363 | 16.9% | 72 |
| `list_directory` | 201 | 9.3% | 53 |
| `git_execute_command` | 200 | 9.3% | 29 |
| `edit_file` | 169 | 7.8% | 33 |
| `write_file` | 130 | 6.0% | 45 |
| `process_wait` | 70 | 3.3% | 20 |
| `process_start` | 60 | 2.8% | 22 |
| `dart_analyze_feedback` | 59 | 2.7% | 22 |
| `find_files` | 48 | 2.2% | 14 |
| `search_web` | 47 | 2.2% | 7 |
| `web_search` | 38 | 1.8% | 1 |
| `whois_lookup` | 31 | 1.4% | 27 |
| `run_tests` | 25 | 1.2% | 10 |

The tail past `run_tests` is 27 tools sharing under 6% combined.

## Coverage of the proposed envelope

As originally scoped (exit code, file mutations, test counts):

| Outcome field | Tools | Renders | Share |
|---------------|------:|--------:|------:|
| Exit code (`local_execute_command`, `git_execute_command`, `run_python_script`, `run_tests`, `ssh_execute_command`) | 4 invoked | 589 | 27.4% |
| File mutation (`write_file`, `edit_file`, `rollback_last_file_change`, `delete_file`, `save_skill`) | 3 invoked | 300 | 13.9% |
| Test counts (`run_tests`) | 1 | 25 | 1.2% |
| **Union** | **7** | **889** | **41.3%** |

**Verdict: the payoff is concentrated, not diffuse.** Seven tools cover 41% of
all tool traffic. The implementation surface is small precisely because tool
usage is so top-heavy — the long tail of 99 network/BLE/computer-use tools that
have no natural outcome also carries almost no traffic, so leaving them
text-only costs nothing.

## The census changed the design: `read_file` belongs in the envelope

`read_file` is the single most-invoked tool at 26.3%, and it was **not** in the
original envelope scope because "reading a file" has no pass/fail outcome. That
framing was wrong. A read has a highly valuable outcome: **the content hash**
(plus byte and line counts). Today `read_file` returns `content` and
`truncated` and nothing else (`filesystem_tools.dart:242`).

A content hash on read results makes "this file has not changed since you read
it at iteration 4" a fact the harness can state, and it extends comparison
across reads with different parameters (offset 1-100 then 1-200 produce
different payloads from an unchanged file).

> **Superseded (same day).** The correction below replaced the read hash with
> the mutation `changed` fact as "the signal behind the dominant failure". That
> is also wrong: counting the logs shows anchor mismatch (`old_text was not
> found`) in 19 of 23 edit-bearing re-read sessions versus no-op mutations in 1.
> See `docs/reread_loop_mechanism_2026-07-21.md`. The reasoning below is kept
> because the intermediate claim was acted on.

### Correction (same day): the read hash is not the signal the dominant failure needs

This document first claimed the read hash makes the measured dominant failure —
redundant re-reads in ~53% of sessions — "mechanically detectable". That
overstated it. `ToolLoopContextDigest` keys results by (tool, arguments) and
compares the payload bodies for identity
(`tool_loop_context_digest.dart:67-72`), so **identical re-reads are already
detected today**. The recorded case behind that statistic — 11 identical
full-file reads in session 119292cb — is exactly the shape the existing
comparison catches.

What is *not* detected is the cause of that loop: the no-op edit. The model
edits, believes the file changed, re-reads, sees the same content, and edits
again. `FilesystemTools.writeFile` reports `bytes_written` and `created`
(`filesystem_tools.dart:632-634`) and **never whether the content actually
changed** — writing byte-identical content is indistinguishable from a real
mutation. `editFile` has an `already_applied` flag, but that is a precondition
check (the old text was missing because the new text is already there), not a
post-write comparison.

So the ranking of the remaining envelope fields is:

| Field | Reaches the dominant failure? |
|-------|-------------------------------|
| Mutation `changed` / content hash on `write_file` / `edit_file` (13.9%) | **Yes — this is the undetected cause** |
| Read content hash on `read_file` (26.3%) | Partly: better robustness and cross-parameter comparison, but the symptom is already caught |

The mutation fact should therefore land before the read hash, even though the
read hash covers more traffic. Coverage is what this census measured; causal
value is a separate question, and conflating them is what produced the original
claim.

Revised coverage with a read outcome (path, hash, bytes, lines) added:

| Envelope scope | Tools | Share of traffic |
|----------------|------:|-----------------:|
| Original (exit / mutation / tests) | 7 | 41.3% |
| **+ read outcome (`read_file`)** | **8** | **67.6%** |
| + directory outcome (`list_directory`) | 9 | 76.9% |

Second tier worth considering once the first lands: `process_start` /
`process_wait` / `process_status` (6.7% combined, exit status and running
state) and `dart_analyze_feedback` (2.7%, error/warning counts — already
structured upstream by the LSP bridge).

## Consequences for LL34

1. **Keep the milestone, sharpen the order.** Land exit status first
   (`local_execute_command`, `git_execute_command` — 26.2% of traffic, and the
   boundary to lift from already exists), then the mutation `changed` fact,
   then the read hash.
2. **The mutation fact is what reframes LL34's relationship to LL30** (see the
   correction above). A `changed` fact on writes is the one undetected signal
   behind the dominant measured problem, which is the strongest available
   argument for building this milestone before the speculative half of the
   track. The read hash is coverage and robustness, not the causal fix.
3. **Do not chase the tail.** 33 of the 41 invoked tools stay text-only. The
   non-goal already recorded in the milestone — never invent an outcome field a
   tool does not genuinely know — is confirmed by the distribution rather than
   just asserted.

## Caveat

**Method risk (added 2026-07-21, after a related count proved contaminated).**
The traffic figures above come from counting `[Tool: <name>]` markers in the
concatenated log text. A later investigation
(`docs/reread_loop_mechanism_2026-07-21.md`) found two failure modes in that
technique: substring matches against file content inlined into tool payloads,
and text appearing in sessions that contain no corresponding tool render, most
plausibly through replayed conversation history. The `[Tool: ]` marker is
distinctive enough to be immune to the first, and the observed rate (~2.2
renders per session) is too low to suggest heavy replay inflation, so these
figures are probably sound.

**Resolved the same day: they are.** `tool/analyze_tool_results.py` now counts
the same population by de-duplicating messages on their stable id and parsing
payloads, and it reproduces these figures within 0.1 points (`read_file` 26.4%
vs 26.3%, `local_execute_command` 17.0% vs 16.9%). The technique survived
because the `[Tool: ]` marker resists payload contamination and tool-result
messages are barely replayed, even though the surrounding conversation is
(6.9x overall). The error counts in the companion document were not so lucky.

These logs are one developer's usage on one machine, weighted toward coding
sessions. The shape (top-heavy, coding tools dominant) is unlikely to invert,
but the exact percentages should not be quoted as a general property of the
product.
