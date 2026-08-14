# Live LLM Canary Agent Runbook

Use this runbook when Codex, Claude, or a developer needs to run a Caverno live
LLM canary against an OpenAI-compatible endpoint.

## Choose the Connection Path

Use the managed loopback wrapper only when all of these are true:

- the canary runs under `flutter_tester` on macOS;
- the endpoint is an HTTP LAN address rather than localhost; and
- macOS Local Network Privacy may block the test process.

Run the canary command directly for localhost endpoints, Apple Foundation
Models, and host-app tests that already have network access. The first relay
version intentionally rejects HTTPS endpoints. Do not disable TLS verification
or replace the wrapper with an undocumented fixed-port relay.

## Required Preflight

Before spending model time:

1. Confirm the task authorizes live model calls and any external data transfer.
2. Confirm the intended endpoint is reachable from the shell.
3. Inspect the endpoint's model catalog and select an exact loaded model ID.
4. Check that the chosen canary matches the changed production path.
5. Confirm any data-export acknowledgement required by that canary.
6. Keep the run bounded until the connection and evidence path are proven.

For a local router that exposes status in the OpenAI model catalog, this
read-only check prints the loaded model IDs:

```bash
curl -fsS "${CAVERNO_LLM_BASE_URL%/}/models" \
  -H "Authorization: Bearer ${CAVERNO_LLM_API_KEY}" \
  | jq -r '.data[] | select(.status.value == "loaded") | .id'
```

Use the provider's authenticated model-catalog equivalent when it does not
expose router status in this shape.

Never print or commit an API key. Session logs and canary artifacts may contain
prompts, tool arguments, tool results, and generated code context.

## Smallest Useful Live Check

The streaming probe is the recommended first check for the managed relay. It
uses Caverno's production streaming datasource, requires the selected probe to
run, and gates on its full 50 points:

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=qwen3.6-35b-a3b-vision \
CAVERNO_BENCHMARK_CANARY_NAME=official_loopback_streaming_live_canary \
CAVERNO_BENCHMARK_CANARY_PROBE_IDS=streaming_response \
CAVERNO_BENCHMARK_CANARY_REQUIRED_PROBE_IDS=streaming_response \
CAVERNO_BENCHMARK_CANARY_MIN_POINTS=50 \
tool/with_live_llm_loopback.sh -- tool/run_live_llm_benchmark_canary.sh
```

Replace the endpoint and model with the values confirmed during preflight. Do
not copy a historical model ID without checking current model state.

## Wrap an Existing Canary

The wrapper accepts any existing canary runner after `--`:

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=replace-with-loaded-model-id \
tool/with_live_llm_loopback.sh -- tool/run_chat_live_llm_canary.sh
```

Use the narrowest runner that covers the change:

| Validation target | Runner |
|---|---|
| Endpoint and production streaming | `tool/run_live_llm_benchmark_canary.sh` |
| Chat orchestration | `tool/run_chat_live_llm_canary.sh` |
| Plan Mode scenarios | `tool/run_plan_mode_live_test.sh` |
| Routine execution | `tool/run_routine_live_llm_canary.sh` |

Use `docs/live_llm_canary_coverage.md` to select broader coding, tool-result,
vision, or release gates. Do not substitute a generic benchmark for the
production surface changed by the task.

## Evidence to Inspect

The runner prints its artifact directory. Inspect at least:

- `canary_summary.json`: `result`, `mainReadiness.status`, `baseUrl`,
  `effectiveBaseUrl`, `relayMode`, and the exact model;
- `benchmark_run.json`, when present: the requested probe status, attempted
  points, checks, token usage, and streaming measurements; and
- `flutter_test.jsonl`: exact failure text when the summary is not ready.

A valid managed-relay report keeps the LAN endpoint in `baseUrl`, records a
dynamic `127.0.0.1` URL in `effectiveBaseUrl`, and sets `relayMode` to
`loopbackTcp`. The wrapper preserves the canary exit status and removes its
relay process on normal exit and signals.

`likelyBuffered: true` is not a relay failure. It means delivery timing cannot
support a model decode-rate claim, even when the probe content passed.

## Failure Triage

- `relay exited before becoming ready`: inspect the printed relay error; common
  causes are an unsupported URL or unavailable Dart runtime.
- `timed out waiting for the relay`: check local process limits and retry once;
  do not switch to a fixed port.
- connection failures inside every probe: confirm the wrapper printed both the
  origin and effective URLs, then recheck endpoint reachability and model state.
- required probe skipped: verify the probe ID and provider capability before
  trusting the run.
- HTTPS rejected: run directly when permitted or design a certificate-correct
  HTTPS transport separately.

## Handoff Format

Report the exact model and endpoint, requested probe or runner, result and
readiness, artifact directory, origin/effective route metadata, important
physical measurements, cleanup result, and any intentionally untested surface.
Separate measured evidence from inference.
