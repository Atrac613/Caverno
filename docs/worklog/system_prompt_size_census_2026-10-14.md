# System Prompt Size Census (2026-10-14)

LL46's third producer kind is system-prompt sections. Before deciding how to
inventory them, this measures what the system prompt is made of in real
sessions: every `turn opening request` in the grounded session-log corpus,
personal-eval replays excluded.

## Size

| Workspace | Turns | Median chars | p90 | Max |
|---|---|---|---|---|
| chat | 26 | 11,114 | 11,873 | 11,885 |
| coding | 485 | 23,781 | 41,560 | 49,866 |

A coding turn's system prompt is about 6k tokens at the median and 10k at
p90, before any history or tool catalog. On a 32k-token window that is a
fifth to a third of the budget.

## What it is made of (coding, 488 prompts)

| Part | Median chars | p90 |
|---|---|---|
| `<repo_map>` | 297 | 8,500 |
| `<agents_md>` | 0 | 6,608 |
| Everything else | 23,298 | 25,363 |

The 15 `SystemPromptConstants` blocks present in every coding prompt total
about 4,500 characters (`exactPreservationInstruction` 646,
`researchHonestyInstruction` 482, `toolInterpretationInstruction` 392, ...).
The remaining ~18,800 characters at the median are guidance written inline
in `SystemPromptBuilder.build` (1,106 lines, around 150 conditional
`buffer.writeln` calls in the coding branch). None of it has a section id,
so neither the session log nor an inventory can say which rule costs what,
or which ones are always on.

The repo map and AGENTS.md are what make the p90 large; the inline guidance
is what makes the median large.

## Implication for LL46

A system-prompt inventory needs the builder's sections to be named first:
each conditional block becomes a `(section id, condition, text)` entry, the
builder concatenates them in the existing order, and an inventory test fails
on an unnamed section. That is a behaviour-preserving large-file refactor
(`docs/large_file_refactor_plan.md`): the rendered prompt must stay
byte-identical, which a golden test over a matrix of modes can pin before
any block moves. Once sections are named, the session log can record which
section ids a request carried, and their sizes, so trimming decisions rest on
measured cost rather than on reading the builder.

## Follow-up the same day

The builder now writes 44 named sections, byte-identical under 24 golden
scenarios, and session-log schema v7 records each request's sections and
sizes. A full-catalog coding render puts `computer_use_tools` (3,446),
`project_read_tools` (2,438) and `core_principles` (1,529) on top; in the
first real chat session recorded (`dcbf9bb9`) the largest section was
`session_memory` (3,254 of 10,192). Trimming decisions can now read these
sizes from the session log instead of from the builder.
