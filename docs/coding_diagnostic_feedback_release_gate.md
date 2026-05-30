# Coding Diagnostic Feedback Release Gate

This gate promotes the Dart analyzer feedback loop from a focused Live LLM
canary to release evidence for Coding Mode changes that affect prompts,
tool-loop execution, diagnostic feedback, model compatibility, or local file
side effects.

## Required Evidence

The gate requires a `coding_diagnostic_feedback_live_canary` summary that proves:

- the live canary result is `passed`;
- the run completed with no failed, skipped, or malformed Flutter JSON tests;
- the root package and nested package Dart repair scenarios passed in at least
  three repeats;
- `dart_analyze_feedback` was observed with non-zero feedback and diagnostic
  counts;
- analyzer feedback telemetry reported non-zero command latency and command
  attempt counts, including fallback, timeout, and start-error counters;
- analyzer feedback included both `lib/main.dart` and
  `packages/nested_app/lib/main.dart`;
- Live LLM recovery signals were all zero, including transport disconnects,
  content-tool recovery, assistant-authored tool blocks, and memory fallback.

## Run

Run the full release gate when release-candidate work touches Coding Mode model
behavior, tool execution, diagnostic feedback, or Dart editing quality:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_coding_diagnostic_feedback_release_gate.sh
```

The wrapper defaults to
`CAVERNO_CODING_DIAGNOSTIC_FEEDBACK_LIVE_REPEAT_COUNT=3`, runs the Live LLM
canary, then checks the generated `canary_summary.json` with:

```bash
dart run tool/coding_diagnostic_feedback_release_gate.dart \
  --summary build/integration_test_reports/<run>/live/<canary>/canary_summary.json \
  --min-repeat-count 3 \
  --out-json build/integration_test_reports/<run>/release_gate.json \
  --out-md build/integration_test_reports/<run>/release_gate.md
```

The checker exits non-zero until every gate is ready. The JSON and Markdown
reports list `blockedGateIds` and next actions for missing or weak evidence.

The feedback payload reports diagnostics introduced after the pre-edit analyzer
baseline when one is available. Existing diagnostics that were present before
the file mutation are counted separately and are not sent back as repair work.

## Reference Reports

`tool/live_llm_canary_reference_report.dart` treats
`coding_diagnostic_feedback` evidence as release-gated evidence. If the
diagnostic feedback summary is present but does not satisfy this gate, the
reference report marks that entry as failed and records the blocked gate IDs as
risk signals.

Keep `tool/codex_verify.sh` separate from this release gate. The gate sends
prompts, tool results, and temporary code-edit data to the configured Live LLM
endpoint and therefore belongs in explicit model or release-candidate evidence,
not everyday local verification.
