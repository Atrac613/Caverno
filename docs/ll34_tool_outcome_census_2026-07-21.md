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

A content hash on read results is worth more than the pass/fail fields, because
it makes the project's **measured dominant failure mode** mechanically
detectable. The LL31 triage found redundant file re-reads in roughly 53% of
sessions — the largest real failure signal Caverno has. `ToolLoopContextDigest`
currently detects this by comparing whole result payloads for byte-identity and
flagging repeats as `unchanged`; a hash field makes that comparison a field
lookup instead of a heuristic over rendered text, and makes "this file has not
changed since you read it at iteration 4" a fact the harness can state.

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

1. **Keep the milestone, sharpen the order.** Land the envelope on
   `local_execute_command` (exit code) and `read_file` (content hash) first —
   two tools, 43% of traffic, and the second one feeds the known #1 failure.
2. **`read_file`'s hash reframes LL34's relationship to LL30.** LL34 stops being
   pure hygiene and becomes a direct contributor to the dominant measured
   problem, which is the strongest available argument for building it before
   the speculative half of the track.
3. **Do not chase the tail.** 33 of the 41 invoked tools stay text-only. The
   non-goal already recorded in the milestone — never invent an outcome field a
   tool does not genuinely know — is confirmed by the distribution rather than
   just asserted.

## Caveat

These logs are one developer's usage on one machine, weighted toward coding
sessions. The shape (top-heavy, coding tools dominant) is unlikely to invert,
but the exact percentages should not be quoted as a general property of the
product.
