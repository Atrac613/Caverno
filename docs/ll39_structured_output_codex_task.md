# LL39 Structured Output Probe

Status: implemented and live-canary verified on 2026-08-14.

## Task

- Goal: make every `ModelStructuredOutputSupport` profile value reachable from
  live diagnostic evidence.
- User-visible behavior: Live LLM Diagnostics tests strict JSON Schema first
  and reports JSON object support as a distinct fallback result.
- Non-goals: certifying every JSON Schema keyword, Responses API coverage,
  grammar/GBNF support, or replacing COMPAT1 protocol diagnostics.

## Context

- `openai_dart` already models `response_format`, but Caverno's production chat
  datasource did not expose it.
- `ModelCapabilityProfileBuilder` previously inferred `jsonObject` from a plain
  instruction-following probe, so `jsonSchema` was unreachable and the profile
  did not describe an actual `response_format` request.

## Implementation Notes

- Add an opt-in structured-output datasource capability instead of widening
  every `ChatDataSource` implementation.
- Request a strict schema whose keys and constants are not repeated in the user
  prompt. This prevents instruction-only JSON from masquerading as schema
  enforcement.
- Fall back to `json_object` after a rejected or violated schema request.
- Record `jsonSchema`, `jsonObject`, or `none` in machine-readable probe
  metadata and map it directly into the model capability profile.
- Keep request rejection classification with COMPAT1; LL39 records whether the
  requested model path produced a usable contract.

## Acceptance Criteria

- The OpenAI-compatible datasource serializes both response-format shapes.
- Strict schema success passes the probe and stores `jsonSchema`.
- Schema failure plus valid JSON object output warns and stores `jsonObject`.
- Failure of both formats stores `none`.
- Apple Foundation Models and datasources without this opt-in capability skip
  without penalty.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/chat_remote_datasource_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart
```

Live v8 canaries against `qwen3.6-27b-vision` and
`qwen3.6-35b-a3b-vision` at `http://192.168.100.241:1234/v1` both enforced the
strict supplied JSON Schema without needing the JSON object fallback.
