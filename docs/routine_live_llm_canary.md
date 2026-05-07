# Routine Live LLM Canary

This document captures the purpose, scope, and triage workflow for the Routine
live LLM canary.

## Purpose

The Routine live LLM canary is an explicit diagnostic run for the routine tool
loop. It is not a unit test and it is not part of the normal `flutter test`
surface. Use it as an early warning check when changing routine execution,
tool-call parsing, workspace file tools, Google Chat notification handling, or
prompt guidance for local models.

The current canary validates the LAN watcher routine path:

- read the previous `lan_devices.json` from a routine workspace
- run `lan_scan`
- write the updated IP list back to `lan_devices.json`
- post only newly discovered IPs through `routine_google_chat_post`

## Runner

Run the canary through the helper script:

```bash
CAVERNO_LLM_BASE_URL=http://<llm-host>:1234/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=gemma-4-26B-A4B-it-Q4_K_M.gguf \
tool/run_routine_live_llm_canary.sh
```

Required environment variables:

| Variable | Required | Notes |
|----------|----------|-------|
| `CAVERNO_LLM_BASE_URL` | Yes | OpenAI-compatible base URL for the live model |
| `CAVERNO_LLM_API_KEY` | Yes | API key or placeholder token accepted by the server |
| `CAVERNO_LLM_MODEL` | Yes | Model ID used for the canary |

Optional environment variables:

| Variable | Notes |
|----------|-------|
| `CAVERNO_ROUTINE_LIVE_CANARY_REPORTER` | Flutter test reporter, defaults to `compact` |
| `CAVERNO_ROUTINE_LIVE_CANARY_MAX_TOKENS` | Overrides routine max tokens for this run |
| `CAVERNO_ROUTINE_LIVE_CANARY_TEMPERATURE` | Overrides routine temperature for this run |

The older `CAVERNO_ROUTINE_LIVE_REPORTER`,
`CAVERNO_ROUTINE_LIVE_MAX_TOKENS`, and
`CAVERNO_ROUTINE_LIVE_TEMPERATURE` aliases are still accepted for compatibility,
but new runs should prefer the `CAVERNO_ROUTINE_LIVE_CANARY_*` names.

The script sets `CAVERNO_ROUTINE_LIVE_CANARY=1` before invoking:

```bash
flutter test tool/canaries/routine_live_llm_canary_test.dart -r compact
```

## Test Shape

The canary uses a live OpenAI-compatible LLM, but isolates side effects:

- the workspace is a temporary directory
- `lan_devices.json` is seeded with previous IPs
- `lan_scan` is a fake MCP tool returning deterministic current IPs
- Google Chat delivery is captured in memory and never posts to a real webhook

The canary expects the model to call these tools successfully:

- `read_file`
- `lan_scan`
- `write_file`
- `routine_google_chat_post`

It also verifies that the saved file contains the current IPs and that the
captured Google Chat message contains only the new IP.

## Why This Is a Canary

This run depends on live model behavior, so it can fail because of prompt
sensitivity, model truncation, parser drift, or tool-loop orchestration changes.
That makes it valuable as a regression signal, but too variable to treat as a
small deterministic unit test.

Keep it outside `test/` so normal test discovery does not run it accidentally.
Run it intentionally after changes that affect routine execution behavior.

## Captured Failure Example

This canary caught a real tool-loop budget issue in the LAN watcher routine.
The live model gathered evidence with `lan_scan` and `read_file`, then called
`write_file` during the final action check. The model requested
`routine_google_chat_post` after the file write, but the runner had already
spent the shared tool-loop iteration budget and stopped before executing the
Google Chat tool.

The fix was to keep separate budgets for evidence collection and final action
tools. Evidence collection still has a bounded loop, while final side-effect
tools such as `write_file` and `routine_google_chat_post` get their own small
bounded loop before the final answer.

This failure is important because the assistant transcript can show that the
model intended to post to Google Chat, while the persisted run record proves
whether the tool actually executed. Treat the persisted tool call list as the
source of truth.

## Failure Triage

Start from the diagnostic output in the failed expectation. It includes:

- routine status and error
- assistant preview and output
- recorded routine tool names
- executed fake MCP tool names
- captured Google Chat messages
- final `lan_devices.json` content when available

Common failure classes:

- Missing `routine_google_chat_post`: the model updated the file but did not
  complete the requested notification flow.
- Missing `write_file`: the model inspected data but failed to persist the
  workspace state.
- Malformed `write_file` arguments: parser compatibility or prompt guidance
  regressed.
- Think-only or length-finished response: the live model likely hit the token
  limit before completing the tool loop.
- Live endpoint connection error: the LLM server or environment variables are
  misconfigured, not necessarily an app regression.

Patch the smallest layer that explains the observed failure before rerunning the
canary. For example, prefer prompt/tool-loop fixes for skipped required tools
and parser fixes for malformed embedded tool-call text.
