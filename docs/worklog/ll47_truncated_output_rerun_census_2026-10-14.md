# LL47 Truncated Tool-Output Re-run Census (2026-10-14)

LL47 proposed spilling the complete output of a truncated tool result to a
private file and naming its path, and asked first how often truncation is
followed by a re-run of the same command with a narrower filter, the cost the
spill would remove.

## Measurement

Grounded session logs, personal-eval replays excluded; each tool result
counted once by id.

| Measure | Value |
|---|---|
| Command results with `stdout_truncated` or `stderr_truncated` | 194 |
| by tool | `git_execute_command` 157, `process_wait` 29, `local_execute_command` 5, `process_status` 2, `process_tail` 1 |
| Followed within three results by the same command plus a narrowing filter (`--stat`, `\| tail`, `\| head`, `\| grep`, ...) | 14 (7%), in 10 sessions |

Most narrowing re-runs are `git diff` -> `git diff --stat` or
`git diff -- <file> | tail -N`. `17e971376` already tells the model how to
read git output past the character cap.

## The existing spill

`ToolResultArtifactStore` already spills any tool result over 50,000
characters to the app-support directory and tells the model "Use read_file on
that path". `ProjectReadPathFence` only authorizes reads under the active
project root, so in coding mode that instruction cannot be followed. It fired
twice in the corpus; neither time did the model try to read the file.

## Conclusion

LL47 as scoped does not pay: 14 narrower re-runs across the corpus, most of
them on git output that already carries reading guidance. Not implemented.

The existing spill's guidance is a small, separate defect: it names a path
the read fence refuses. Either the guidance should stop pointing at
`read_file` (say the full result was saved for the user and give the
truncated content only), or the read fence should admit the artifact
directory read-only, which is a SEC1 perimeter decision.
