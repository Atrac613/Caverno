# SEC4.5f Credential-Bearing LLM HTTPS Policy

## Task

- Goal: prevent API keys and private LLM request content from crossing a
  plaintext non-loopback connection.
- User-visible behavior: endpoint editing rejects a real API key paired with a
  non-loopback HTTP URL and explains that HTTPS is required.
- Non-goals: secure credential storage, encrypted exports, certificate pinning,
  or changing the credentialless local-LAN default.

## Context

- Affected components: endpoint settings, chat completions, model catalog
  discovery, embeddings, and llama.cpp slot transports.
- Related docs: `docs/security_audit_2026-08-14.md` SA-12 and
  `docs/local_llm_agent_roadmap.md` SEC4.5f.
- Release gate: P1 authenticated transport containment.

## Implementation Notes

- Use one pure policy at every LLM client construction boundary.
- Treat an empty key and `no-key` as credentialless local placeholders.
- Permit plaintext only when the endpoint is loopback or credentialless.
- Keep the runtime boundary authoritative even if settings arrive from an old
  persisted payload, CLI override, import, or a non-UI route.

## Similar-Pattern Search

- Search terms: `OpenAIClient.withApiKey`, `Authorization`, `Bearer`,
  `ModelRemoteDataSource`, `EmbeddingsClient`, `LlamaCppSlotTransport`.
- Files inspected: chat/model/embedding data sources, llama.cpp slot discovery
  and transport, Pro Reasoning endpoint probes, onboarding, and settings UI.
- Follow-up tasks found: SA-11 secure storage and secret-free exports remain
  SEC4.6; certificate pinning for arbitrary LLM endpoints is not part of SA-12.

## Acceptance Criteria

- HTTPS endpoints accept configured API keys.
- HTTP loopback endpoints accept configured API keys.
- Credentialless HTTP LAN endpoints remain supported.
- HTTP non-loopback endpoints with a configured API key fail before any request.
- UI validation and runtime clients share the same policy.

## Verification

```bash
tool/codex_verify.sh --test test/core/security/llm_endpoint_transport_policy_test.dart
```

## Handoff Notes

- Summary: one shared transport policy now gates endpoint editing and every
  primary LLM HTTP client boundary before a credential-bearing request can be
  created.
- Tests run: the standard Codex verification entrypoint passed, followed by 90
  focused policy, chat, model-catalog, embeddings, and llama.cpp client tests.
- Risks or follow-ups: existing insecure persisted settings remain visible but
  fail closed at runtime; secure storage and secret-free export remain SEC4.6.
