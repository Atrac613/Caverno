# SEC4.4 Write Containment Remainder

SA-08 file-mutation containment is split across these slices. Do not combine
them in one PR.

| Slice | Status | Scope |
|-------|--------|-------|
| SEC4.4b | done | `write_file`, `edit_file`, `delete_file` through `ProjectMutationPathFence` |
| SEC4.4c | done | Routine external MCP deny-by-default (SA-09) |
| SEC4.4d | done | `git_execute_command` working-directory fence |
| SEC4.4e | done | Git pathspecs and `--git-dir` / `--work-tree` / `-C` escapes |
| SEC4.4f | done | Local-command write containment (canonical cwd fence + internal write argv) |

SA-08 file-mutation containment is complete. Next remaining P1 slices are
SEC4.5e (Remote Coding connection/frame/rate limits) and SEC4.3d
(HTTP body/time limits).
