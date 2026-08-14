# Pro Reasoning Local Candidate Routing

## Task

- Goal: Add a local-LLM-only option to Pro Reasoning candidate generation.
- User-visible behavior: Model Routing offers Local LLMs only alongside the
  selected-endpoint and all-enabled-endpoints policies.
- Non-goals: Do not change routing for framing, investigation, critique, or
  synthesis stages.

## Context

- Affected components: Pro Reasoning settings, candidate endpoint resolution,
  Model Routing UI, persistence, localization, and focused tests.
- Related docs: `docs/pro_reasoning_chat_mode_design.md`.
- Compatibility: Existing stored routing values and the mesh default remain
  unchanged.

## Implementation Notes

- Treat discovered endpoints, loopback and private IPs, link-local and unique
  local IPv6 addresses, `.local` names, and single-label DNS names as local.
- Keep each eligible endpoint's configured model. Apply the Pro Reasoning model
  override only when the selected endpoint is itself local.
- Regenerate Freezed and JSON serialization outputs after extending the enum.

## Acceptance Criteria

- Local-only routing excludes hosted endpoints from stage-three candidates.
- Local loopback, LAN, mDNS, discovered, and single-label endpoints remain
  eligible.
- The routing value persists and appears in the Model Routing dropdown.
- Existing selected-only and all-enabled behavior remains unchanged.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/pro_reasoning_candidate_endpoint_resolver_test.dart
tool/codex_verify.sh --test test/features/settings/domain/entities/app_settings_test.dart
tool/codex_verify.sh --test test/features/settings/presentation/pages/model_routing_settings_page_test.dart
```
