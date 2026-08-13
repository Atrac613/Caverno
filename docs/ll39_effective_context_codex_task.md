# LL39 Effective Context Probe

Status: implemented and live-canary verified on 2026-08-14.

## Task

- Goal: replace advertised-only context capacity with an opt-in, measured lower
  bound for the active model and endpoint.
- User-visible behavior: exported diagnostics and the capability panel show the
  largest successful endpoint-reported prompt-token count and the ladder trials.
- Non-goals: destructive stress testing, tokenizer-specific exact prompt
  construction, automatic execution during normal diagnostics, or certifying
  the server's advertised maximum.

## Safety And Cost Contract

- The probe is disabled by default and skips without allocating a long prompt.
- Only the headless canary opts in through
  `CAVERNO_EFFECTIVE_CONTEXT_MAX_TOKENS`.
- The ladder starts at approximately 2,048 tokens, doubles until the configured
  maximum, and stops at the first rejection, missing usage, or marker failure.
- The implementation rejects canary values above 1,048,576 and clamps the
  service defensively to the same hard maximum.
- The configured sizes guide prompt construction only. Capability profiles use
  the endpoint-reported `prompt_tokens` from successful requests, never the
  approximation.

## Measurement Contract

- Each prompt places a unique marker at both ends of a large data block.
- A trial passes only when the model returns both markers exactly and the
  endpoint reports positive prompt-token usage.
- Reaching the configured ceiling passes. Finding a boundary after at least one
  successful trial warns but retains the measured lower bound. No successful
  measured trial fails.
- A measured lower bound takes precedence over advertised model metadata in
  `ModelCapabilityProfile.usableContextTokens`.
- The capability remains outside the bounded conformance score with zero
  points; `cavernobench` v8 records the changed probe set without moving the
  1,000-point denominator.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/entities/live_llm_diagnostic_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/pages/live_llm_diagnostic_page_test.dart \
  --test test/tool/run_live_llm_benchmark_canary_test.dart
```

The focused suite passed with 81 tests. The repository verification entrypoint
also passed project/package analysis, package tests, and notification-relay
checks and tests.

## Live Validation

The focused capability-only canary ran against `qwen3.6-27b-vision` with a
configured approximate ceiling of 65,536 tokens. Boundary recall passed through
16,498 endpoint-reported prompt tokens and the endpoint rejected the next
32,768 approximate-token trial. The successful rerun completed in 79 seconds
with four of five trials passing and main readiness reported as ready.

The first run also exposed a canary harness mismatch: capability-only probes
carry zero conformance points, while the harness treated zero attempted points
as proof that every probe skipped. The gate now checks attempted probe state,
preserving the all-skipped safeguard without rejecting physical-only metrics.
