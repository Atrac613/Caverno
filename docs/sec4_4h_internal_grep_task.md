# SEC4.4h Internal grep

Status: completed 2026-09-24.

## Task

- Goal: stop spending a fresh SEC4.4g host-write approval on plain `grep`
  reads, without narrowing SEC4.4g itself.
- User-visible behavior: supported `grep` invocations run through Caverno's
  bounded internal executor, with no approval prompt, like `cat` and `rg`.
  Everything else keeps the gated shell path.
- Non-goals: widening SEC4.4g, allowlisting any command that reaches `sh -c`,
  or supporting every GNU/BSD grep flag.

## Context

- Evidence: the approval audit held 255 `opaque_host_write` prompts across 17
  days between 2026-08-26 and 2026-09-23, 49% of all audited decisions. 52
  were `grep`, and the most common command was
  `grep -E '^version:' pubspec.yaml`. SEC4.1 removed `grep` from the read-only
  shortcut because it then ran through the real shell.
- A 2026-09-11 attempt to exempt a direct argv tier from SEC4.4g was reverted
  the same day: it validated the executable and passed later flags through.
  This slice does not repeat that shape. No external `grep` process is ever
  spawned on the approval-free path.
- Related docs: `docs/sec4_1_approval_free_execution_boundary_task.md`,
  `docs/sec4_4a_project_read_containment_task.md`,
  `docs/sec4_4g_opaque_local_command_authority_task.md`.

## Implementation Notes

- `LocalShellGrep` (`lib/features/chat/data/datasources/local_shell_grep.dart`)
  is a pure Dart implementation. Its `parse` is the only authority for
  support. The same parse result supplies the paths `projectReadDenial` fences
  and drives execution, so the fenced paths are exactly the paths that are
  read.
- Unsupported invocations return null from `parse`. `isReadOnly` is then false
  and the command takes the existing gated shell path, so nothing that worked
  with approval before becomes an error. SEC4.1's invariant still holds:
  `isReadOnly(command)` implies `executed_internally: true`.
- Deliberately left on the shell path:
  - `-R`, because it follows symlinks out of the root.
  - stdin input and `-f`.
  - `-P`.
  - Dart-only escapes such as `\d`, back-references, `\<` and `\>`,
    equivalence classes, and `(?`.
  - Stacked quantifiers, which Dart reads as lazy.
  - Brace globs.
  - Nested repetition such as `(a+)+` and `(a|aa)*`. Dart's `RegExp`
    backtracks, and an internal command runs on the app isolate with no
    process to kill. grep's DFA is immune, so the shell handles these.
- `grep -r` skips symlinks met during recursion, as GNU grep does. Command-line
  operands are resolved and fenced by `ProjectReadPathFence`.
- `_hasUnquotedShellExpansion` keeps `grep` off the internal path whenever the
  shell would build different argv than `_splitArgs`. That covers globbing,
  tilde and brace expansion, backslash removal, and the empty quoted word
  `''`, which `_splitArgs` drops.
- `_hasUnsafeShellSyntax` now reads operators inside quotes as literal text.
  Inside single quotes `sh` interprets nothing. Inside double quotes only `$`,
  the backtick and the backslash keep a meaning, and those still refuse. An
  escaped operator outside quotes, a newline, and an unterminated quote still
  refuse. A misread here cannot run anything, because an accepted command is
  executed by Caverno, never by `sh`. The worst case is an internal answer
  that differs from the shell's.

## Similar-Pattern Search

- Search terms: `LocalShellTools.isReadOnly`, `_canExecuteInternally`,
  `_hasUnsafeShellSyntax`, `projectReadDenial`, `_internalReadPaths`,
  `executed_internally`.
- Consumers inspected:
  - `local_command_tool_handler.dart`
  - `built_in_local_command_read_preflight.dart`
  - `built_in_local_command_mutation_preflight.dart`
  - `planning_tool_policy.dart`
  - `tool_call_execution_policy.dart`
- All of them consume the shared classifier, so Plan Mode now also permits
  supported `grep`. Background execution and `process_start` still reach the
  shell and SEC4.4g.
- Adjacent defect not fixed here: `_splitArgs` also drops `''` and ignores
  globs for `cat`, `ls`, `head` and the other internal commands. Their
  behavior is unchanged in this slice.

## Acceptance Criteria

- Supported `grep` forms report `executed_internally: true` and need no
  approval.
- Output and exit status match `/usr/bin/grep` on the unit-test fixture.
- Every unsupported form listed above reports `isReadOnly == false`.
- `grep` operands outside the project, including recursive roots, are denied
  by the read fence.
- Symlinks inside a recursively searched tree are not followed.

## Verification

```bash
tool/flutter_test_quiet.sh \
  test/features/chat/data/datasources/local_shell_grep_test.dart \
  test/features/chat/data/datasources/local_shell_tools_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- A one-off differential harness compared 57 internal invocations against
  `/usr/bin/grep` (BSD grep 2.6.0, GNU compatible). stdout and exit status
  matched on every one. The unit tests pin the recorded outputs.
- Replaying the 255 audited `opaque_host_write` commands through the new
  classifier frees 29 of them (11%). Every other `grep` prompt chains `git`,
  pipes to `head`, or uses a construct listed above, and correctly stays
  gated.
- Risks: output parity is measured against BSD grep only, and GNU-specific
  output details may differ. Word characters for `-w`, `\w` and `\b` are ASCII
  here, but locale-aware in GNU grep.
