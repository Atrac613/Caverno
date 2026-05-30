# Coding Verification Feedback Release Gate

This gate promotes the Dart test feedback loop from focused Live LLM canary
evidence to release evidence for Coding Mode changes that affect prompts,
tool-loop execution, verification feedback, model compatibility, or local file
side effects.

## Required Evidence

The gate requires a `coding_verification_feedback_live_canary` summary that
proves:

- the live canary result is `passed`;
- the run completed with no failed, skipped, or malformed Flutter JSON tests;
- the root package and nested package Dart repair scenarios passed in at least
  three repeats;
- `dart_test_feedback` was observed with non-zero feedback and failing-test
  counts;
- verification feedback came from `completionClaim` triggers with failed
  validation status;
- test feedback telemetry reported non-zero command latency and command attempt
  counts, including fallback, timeout, and start-error counters;
- test feedback included both `lib/canary_value.dart` and
  `packages/nested_app/lib/canary_value.dart`;
- Live LLM recovery signals were all zero, including transport disconnects,
  content-tool recovery, assistant-authored tool blocks, and memory fallback.

## Run

Run the full release gate when release-candidate work touches Coding Mode model
behavior, tool execution, verification feedback, or Dart editing quality:

```bash
CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1 \
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_coding_verification_feedback_release_gate.sh
```

Set `CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1` only after confirming the configured
endpoint may receive prompts, temporary code-edit context, and tool results from
the isolated live canary fixture.

The wrapper defaults to
`CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_REPEAT_COUNT=3`, runs the Live LLM
canary, then checks the generated `canary_summary.json` with:

```bash
dart run tool/coding_verification_feedback_release_gate.dart \
  --summary build/integration_test_reports/<run>/live/<canary>/canary_summary.json \
  --min-repeat-count 3 \
  --out-json build/integration_test_reports/<run>/release_gate.json \
  --out-md build/integration_test_reports/<run>/release_gate.md
```

The checker exits non-zero until every gate is ready. The JSON and Markdown
reports list `blockedGateIds` and next actions for missing or weak evidence.

## Latest Evidence

- 2026-05-30: `qwen3.6-27b-mtp-vision` at
  `http://192.168.100.241:1234/v1` passed the release gate with `6/6` live
  canary tests, three complete root/nested repeats, non-zero
  `dart_test_feedback`, and zero Live LLM recovery signals.
- Report root:
  `build/integration_test_reports/coding_verification_feedback_release_gate_1780151765/`
- Gate summary:
  `build/integration_test_reports/coding_verification_feedback_release_gate_1780151765/release_gate.md`

## Reference Reports

`tool/live_llm_canary_reference_report.dart` treats
`coding_verification_feedback` evidence as release-gated evidence. If the
verification feedback summary is present but does not satisfy this gate, the
reference report marks that entry as failed and records the blocked gate IDs as
risk signals.

Keep `tool/codex_verify.sh` separate from this release gate. The gate sends
prompts, tool results, and temporary code-edit data to the configured Live LLM
endpoint and executes generated project tests, so it belongs in explicit model
or release-candidate evidence, not everyday local verification.
