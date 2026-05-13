# Plan Mode Supportability - 2026-05-13

PM17 defines the support surface for user issue reports and reviewer
investigations.

## Product Support Snapshot

The General settings page now includes a Plan Mode support snapshot action. It
copies redacted JSON with:

- configured base URL and derived `/models` endpoint
- selected model identity
- non-secret API key status
- demo mode, assistant mode, and MCP enablement
- endpoint preflight failure classification
- canonical deterministic, live, and canary report paths
- troubleshooting document references

The snapshot intentionally excludes API key values and other secrets.

## Failure Classification

Use these product-side classifications before reading raw logs:

| Classification | Meaning | First action |
|----------------|---------|--------------|
| `ready` | `/models` responded and the selected model is available. | Attach the snapshot and latest Plan Mode report if workflow behavior still fails. |
| `modelNotAvailable` | `/models` responded, but the selected model is not listed. | Select a fetched model or update the model name. |
| `endpointPreflightFailed` | `/models` could not be fetched. | Check base URL, API key, server availability, and OpenAI-compatible `/models` support. |
| `preflightPending` | The model-list request is still loading. | Refresh or wait before classifying the failure. |

## Report Paths

When filing or reviewing a Plan Mode issue, attach the support snapshot and the
latest applicable artifact:

- deterministic smoke:
  `build/integration_test_reports/plan_mode_suite_macos_report.json`
- live smoke:
  `build/integration_test_reports/plan_mode_live_suite_macos_report.json`
- Ping CLI canary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/canary_summary.json`

## Troubleshooting Map

- Endpoint, model, or `/models` failures:
  `docs/plan_mode_model_endpoint_compatibility.md`
- Release decision and blocker classification:
  `docs/plan_mode_release_readiness_checklist.md`
- Full release candidate rerun flow:
  `docs/plan_mode_release_candidate_gate.md`
- Scenario classification and promotion rules:
  `docs/plan_mode_scenario_coverage.md`

## Verification

- `fvm flutter test test/features/settings/presentation/pages/general_settings_page_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

## Decision

PM17 is complete. Plan Mode issue reports can now include a redacted product
snapshot, model identity, failure classification, and canonical report paths
without exposing API keys.
