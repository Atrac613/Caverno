# Plan Mode Release Package - 2026-05-13

This package is the user-facing release surface for Plan Mode. It summarizes
what ships, what users need before starting, what remains limited, and which
assets or evidence should accompany release review.

## Release Notes

Plan Mode helps coding threads move from a request to implementation through a
reviewable workflow:

- Caverno proposes a plan document with workflow stage, goal, constraints,
  acceptance criteria, open questions, and numbered tasks.
- Users can review, edit, approve, or cancel the plan before implementation
  begins.
- Approved plans stay attached to the conversation and can be expanded,
  edited, refreshed into execution tasks, or used as the source of truth for
  continued work.
- Task rows show progress, validation status, blockers, recovery actions, and
  completion state without requiring users to read integration logs.
- General settings now show endpoint preflight, selected model availability,
  non-secret API key status, and a redacted Plan Mode support snapshot.

## Requirements

- An OpenAI-compatible chat completion endpoint.
- A configured base URL, API key or placeholder token, and model name in
  General settings.
- A `/models` route for product preflight, unless the endpoint is known to be
  compatible but intentionally omits that route.
- A model that can produce parseable workflow and task proposals, follow saved
  task boundaries, and tolerate the app's tool-result handling.
- MCP or built-in tools enabled when the approved plan requires file, shell,
  git, search, or diagnostic tool use.

## Supported Setup Path

1. Open Settings > General.
2. Configure the OpenAI-compatible base URL, API key, and model.
3. Refresh the model list.
4. Confirm the settings card shows `Endpoint preflight passed`.
5. Start a coding conversation with Plan Mode enabled.
6. Review and approve the generated plan before implementation starts.

If the selected model is missing or endpoint preflight fails, fix that settings
state before classifying a Plan Mode generation failure as an app regression.

## Known Limitations

- Endpoint and model compatibility is validated through the PM5 gate and current
  release candidate evidence, not a broad provider matrix.
- Models that repeatedly produce malformed workflow or task JSON are outside
  the supported boundary until compatibility improves.
- Ping-only canary evidence does not replace a fresh live smoke pass.
- The app redacts API key values in support snapshots, so users may need to
  verify the secret separately when debugging authentication failures.
- Store screenshots are produced through the existing screenshot flow; Plan Mode
  release review should additionally capture current product states listed
  below when preparing external materials.

## Demo And Screenshot Checklist

Capture or demo these states for release review and external materials:

- General settings with endpoint preflight passed.
- General settings with the Plan Mode support snapshot action visible.
- A generated Plan Mode draft showing review, edit, approve, and cancel actions.
- An invalid draft showing the approval blocker message.
- An approved plan collapsed and expanded in the chat timeline.
- Execution task rows showing in-progress, blocked or recovery, validation, and
  completed states.

Use the existing store screenshot command in `README.md` for standard app store
images. Keep any extra Plan Mode demo captures in release review notes unless
they are promoted into the store screenshot set.

## Support And Troubleshooting

Use these documents when triaging release feedback:

- `docs/plan_mode_model_endpoint_compatibility.md`
- `docs/plan_mode_supportability_2026-05-13.md`
- `docs/plan_mode_release_readiness_checklist.md`
- `docs/plan_mode_release_candidate_gate.md`
- `docs/plan_mode_scenario_coverage.md`
- `docs/plan_mode_post_release_guardrails_2026-05-13.md`

For user reports, ask for:

- the redacted Plan Mode support snapshot from Settings > General
- the latest deterministic or live Plan Mode report path
- a short description of the visible product state
- whether the issue happened before planning, during approval, during task
  execution, during recovery, or after completion

## Verification

- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

## Decision

PM18 is complete. The Plan Mode release surface now has release notes,
requirements, limitations, demo and screenshot expectations, and support
handoff links in one package.
