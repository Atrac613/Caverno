# Plan Mode Settings and Compatibility UX - 2026-05-13

PM16 productizes the most common endpoint and model compatibility checks from
the Plan Mode release gate into the settings UI.

## User Problem

Before PM16, a failed model-list request only said that the list could not be
fetched. Users still had to infer whether the configured base URL, API key, or
model name was the next thing to inspect. That was enough for logs and release
scripts, but weak for product use.

## Product Behavior

The General settings page now treats the OpenAI-compatible `/models` request as
an endpoint preflight signal:

- When `/models` succeeds and the selected model is present, the settings UI
  shows that endpoint preflight passed.
- When `/models` succeeds but the selected model is missing, the settings UI
  distinguishes a model selection problem from an endpoint outage.
- When `/models` fails, the settings UI shows the configured `/models`
  endpoint, selected model, non-secret API key status, and next repair action.
- Refreshing the model list invalidates the provider instead of only rebuilding
  the page.

The API key display never reveals the secret value. It only reports whether the
app is using the local placeholder or a configured key.

## Verification

- `fvm flutter test test/features/settings/presentation/pages/general_settings_page_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

## Decision

PM16 is complete. Endpoint and model failures are now distinguishable from Plan
Mode workflow failures in the product settings surface, and the release
compatibility documentation points users to the same `/models` preflight
boundary.
