# LL4 Repo Map Live Measurement - 2026-06-13

## Setup

- Baseline commit: `4f489123729483751227bbb8de78513e7a43af3d`
- Repo map commit: `35fa483e`
- Model: `qwen3.6-27b-mtp-vision`
- Endpoint: `http://192.168.100.241:1234/v1`
- Canary: `tool/run_coding_goal_live_edit_canary.sh`
- Repeat count: `1`
- Metric source: Flutter JSON log print messages containing
  `[Tool] Executing tool: ...`

Exploration before first mutation counts `list_directory`, `read_file`,
`find_files`, and `search_files` calls before the first `edit_file` or
`write_file` call in each test.

## Artifacts

- Baseline summary:
  `/tmp/ll4_repo_map_measurement/baseline/coding_goal_live_edit_canary_1781325422/canary_summary.json`
- Baseline log:
  `/tmp/ll4_repo_map_measurement/baseline/coding_goal_live_edit_canary_1781325422/flutter_test.jsonl`
- Repo map summary:
  `/tmp/ll4_repo_map_measurement/current/coding_goal_live_edit_canary_1781325566/canary_summary.json`
- Repo map log:
  `/tmp/ll4_repo_map_measurement/current/coding_goal_live_edit_canary_1781325566/flutter_test.jsonl`
- Post-fix summary:
  `/tmp/ll4_repo_map_measurement/recovery3/coding_goal_live_edit_canary_1781327553/canary_summary.json`
- Post-fix log:
  `/tmp/ll4_repo_map_measurement/recovery3/coding_goal_live_edit_canary_1781327553/flutter_test.jsonl`

## Summary

| Metric | Baseline | Repo map | Delta |
| --- | ---: | ---: | ---: |
| Passed tests | 3/6 | 5/6 | +2 |
| Blocker failures | 3 | 1 | -2 |
| Canary duration | 113,094 ms | 56,739 ms | -49.8% |
| Total tool calls | 56 | 29 | -48.2% |
| Exploration calls before first mutation | 10 | 8 | -20.0% |
| Avg exploration calls before first mutation | 1.67 | 1.33 | -20.0% |
| Avg first mutation index | 3.00 | 2.67 | -11.1% |

The repo map run still failed overall because the git lifecycle case repeated a
successful `git config user.email` command and stopped before `git add`,
`git commit`, and `git revert`. The measurement is still useful for LL4 because
the code-editing cases showed fewer tool calls and improved pass rate under the
same model and endpoint.

## Post-Fix Recovery Run

After the repo map measurement, the tool loop was updated to recover from
duplicate successful command calls, avoid false incomplete-goal detection from
benign `remaining arguments` narration, and stop extra follow-up tool calls once
the active git lifecycle goal has successful `init`, file creation, `add`,
`commit`, `revert`, and clean final `status` tool results.

| Metric | Post-fix run |
| --- | ---: |
| Passed tests | 6/6 |
| Blocker failures | 0 |
| Canary duration | 78,696 ms |
| Total tool calls | 44 |
| Main readiness | ready |

The post-fix run passed every visible live coding canary. Its git lifecycle log
shows `Current git lifecycle goal already succeeded` followed by
`Ignoring follow-up tool calls after git lifecycle success`, preventing the
model from re-opening the sequence after the clean final status.

## Per-Test Tool Metrics

| Test | Baseline result | Repo map result | Baseline tools | Repo map tools | Baseline exploration before mutation | Repo map exploration before mutation | Baseline first mutation index | Repo map first mutation index |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Direct greeting edit | passed | passed | 6 | 4 | 4 | 2 | 5 | 3 |
| Red-green repair | failed | passed | 4 | 4 | 1 | 1 | 3 | 3 |
| Two-file edit | passed | passed | 7 | 5 | 2 | 2 | 3 | 3 |
| Package-like parser fixture | passed | passed | 11 | 6 | 3 | 3 | 4 | 4 |
| File lifecycle | failed | passed | 14 | 6 | 0 | 0 | 1 | 1 |
| Git lifecycle | failed | failed | 14 | 4 | 0 | 0 | 2 | 2 |

## Observations

- The direct edit case skipped the initial double `list_directory` exploration
  seen in the baseline and reached the first edit after two `read_file` calls.
- The package-like parser case kept the same first-mutation depth but cut total
  tool calls from 11 to 6 by avoiding repeated read/edit cycles.
- The file lifecycle case moved from a failed 14-tool run to a passing 6-tool
  run.
- The initial git lifecycle failure was not a repo map orientation issue; it was
  a command progression stall after successful git configuration. The post-fix
  run validates that the stalled and over-eager follow-up paths are now covered.
