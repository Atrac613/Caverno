# SEC4.4 Write Containment Remainder

SA-08 file-mutation containment is split across these slices. Do not combine
them in one PR.

| Slice | Status | Scope |
|-------|--------|-------|
| SEC4.4b | done | `write_file`, `edit_file`, `delete_file` through `ProjectMutationPathFence` |
| SEC4.4c | done | Routine external MCP deny-by-default (SA-09) |
| SEC4.4d | done | `git_execute_command` working-directory fence |
| SEC4.4e | next | Git pathspecs and `--git-dir` / `--work-tree` / `-C` escapes |
| SEC4.4f | later | Local-command write containment (canonical cwd fence + internal write argv) |

SEC4.4e is the next slice. Its task will be
`docs/sec4_4e_git_pathspec_containment_task.md`.
