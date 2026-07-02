# Coding Goal Composer Release Checklist

Use this checklist before shipping the coding goal composer toggle. The feature
uses the configured OpenAI-compatible endpoint to infer a thread goal, so the
manual checks should run against the same model and base URL intended for the
release candidate.

## Local Verification

- Run `tool/codex_verify.sh`.
- Run the focused goal flow tests when iterating on this feature:
  - `fvm flutter test test/features/chat/presentation/widgets/message_input_test.dart test/features/chat/presentation/pages/chat_page_goal_flow_test.dart`
- Confirm generated files are unchanged after verification.

## Live LLM Smoke

Enable coding mode in a thread with a selected coding project, then verify:

- Optional automation: run
  `CAVERNO_LLM_BASE_URL=... CAVERNO_LLM_API_KEY=... CAVERNO_LLM_MODEL=... tool/run_coding_goal_composer_live_smoke.sh`.
- Empty composer, switch enabled: the composer shows pending goal setup and the
  goal flow starts only after the next non-empty send.
- Draft present, switch enabled: the app drafts and saves a goal without sending
  the message.
- Pending setup plus send: the app drafts a goal, saves it, then sends the
  original message once.
- Ambiguous request: the app opens the clarification dialog, accepts a concise
  answer, and applies the clarified goal.
- Repeated ambiguity: the app asks at most two clarification questions, then
  falls back to the clarification snackbar.
- Suggestion failure or offline endpoint: the message draft is preserved and no
  duplicate message is sent.
- Rapid switch/send taps during suggestion: no duplicate suggestion requests,
  no duplicate goal saves, and no duplicate messages.

## Release Candidate Evidence

### 2026-05-31

- Endpoint: `http://192.168.100.241:1234/v1`
- Model: `qwen3.6-27b-mtp-vision`
- Live LLM Smoke: passed with `tool/run_coding_goal_composer_live_smoke.sh`.
  The automated run covered deferred empty-composer setup, draft suggestion,
  pending setup plus send, clarification recovery, repeated ambiguity fallback,
  offline preservation, and rapid interaction duplicate guards.
- Full verification: passed with `tool/codex_verify.sh`.

## UI Checks

- Narrow desktop width around 360 px does not show a RenderFlex overflow.
- Long goal objectives truncate in the goal strip without shifting the send
  button out of view.
- While a goal suggestion is in flight, the composer shows an inline progress
  state, the text field is read-only, and goal controls plus send are disabled.
- Japanese and English goal copy are understandable and consistent with the rest
  of the coding workspace.

## Logging And Privacy

- Session logs are enabled by default, remain local, and are not committed.
- Confirm the goal suggestion request and response are useful for triage and do
  not include unexpected extra context.
- The goal objective shown in the composer matches the draft or clarification
  that triggered the suggestion.
