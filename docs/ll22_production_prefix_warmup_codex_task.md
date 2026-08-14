# LL22 Production-Prefix KV Cache Warm-Up

## Task

- Goal: make the idle KV-cache stage warm the same production prefix and prove
  the first `ChatNotifier` turn benefits under reset-controlled live A/B.
- User-visible behavior: the first tool-aware coding turn after idle maintenance
  can reuse the production initial prefix even when the full-list
  prefix-stable loop is disabled.
- Non-goals: changing production tool selection, adding slot pinning, or
  claiming which server cache layer performs the reuse.

## Context

- Affected components: LL22 maintenance stage, KV warm-up tests, and the Local
  LLM roadmap evidence.
- Related docs: `docs/ll39_cold_path_ab_codex_task.md` and
  `docs/evidence/ll39_cold_path_ab_2026-08-14.json`.
- Reference implementation: `ChatNotifier._sendWithTools` selects either the
  full catalog in prefix-stable mode or
  `ToolDefinitionSearchService.buildInitialSelection` otherwise.
- Known quirk: the LL39 reset-controlled A/B measured a 90.23% median reduction
  only when the discarded request reused the same 48-tool initial prefix. A
  tool-free warm-up reduced the median by just 3.2%.

## Implementation Notes

- Select warm-up definitions through the same production branch as the first
  tool-aware chat request.
- Build the warm-up system prompt from the selected definitions, not the full
  catalog, so its tool-name guidance matches the attached schemas.
- Preserve the full-list behavior when prefix-stable mode is enabled.
- Treat missing or empty tool catalogs as a soft skip and keep endpoint failures
  non-fatal to idle maintenance.
- No generated files or persistence migration are needed.

## Similar-Pattern Search

- Search terms: `enablePrefixStableToolLoop`, `buildInitialSelection`,
  `getOpenAiToolDefinitions`, and `KvCacheWarmupService`.
- Files inspected: `chat_notifier.dart`,
  `maintenance_scheduler_provider.dart`, `tool_definition_search_service.dart`,
  and the LL22/LL39 focused tests and evidence.
- Follow-up tasks found and completed: the scheduler now fingerprints every
  production-prefix input and reruns only `precompute -> warm_cache` when that
  fingerprint changes while the idle gate remains open. A full maintenance run
  is not repeated.

## Acceptance Criteria

- Default mode warms `buildInitialSelection(allTools).toolDefinitions` instead
  of skipping.
- Prefix-stable mode continues to warm the complete catalog.
- The system prompt advertises exactly the names present in the selected
  warm-up definitions.
- Empty catalogs and failed endpoint requests remain soft skips.
- Existing LL22 stage ordering and repo-map precompute behavior remain intact.
- Warm-up and production use the same LSP-backed repo-map inputs, locale,
  AGENTS.md, skill index, harness/profile, project, and tool catalog.
- Dynamic turn context follows the deterministic system-prompt core so clock
  and memory drift do not invalidate the large leading prefix.
- A reset-controlled live A/B records a measurable first-turn improvement
  through `maintenance warm_cache -> ChatNotifier.sendMessage`.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/domain/services/system_prompt_builder_test.dart \
  --test test/features/chat/domain/services/kv_cache_warmup_service_test.dart \
  --test test/features/maintenance/presentation/providers/maintenance_stages_test.dart \
  --test test/features/maintenance/domain/services/idle_maintenance_scheduler_test.dart \
  --test test/features/maintenance/presentation/providers/maintenance_scheduler_provider_test.dart \
  --test test/tool/run_ll22_production_warmup_canary_test.dart
```

## Handoff Notes

- Summary: the LL22 idle stage mirrors ChatNotifier's production tool selection
  and stable prompt inputs, including LSP repo-map symbols. Dynamic turn context
  is behind the deterministic core, and input drift triggers a bounded warm-up
  refresh without repeating the full maintenance pipeline.
- Tests run: the final `tool/codex_verify.sh --no-codegen` run completed project
  and package analysis, all three package suites, 86 focused LL22 tests, and 10
  notification-relay tests. The focused set covers prompt stability, LSP-aware
  repo-map caching, KV warm-up, stage wiring, bounded scheduler refresh, refresh
  fingerprint inputs, and the production-path canary runners.
- Coverage or low-coverage notes: the provider branch is covered through its
  request boundary. No additional line-coverage run was needed for this narrow
  orchestration change.
- Live evidence: three alternating, reset-controlled cold/warm blocks against
  `qwen3.6-35b-a3b-vision` used the same 48-tool initial catalog. Median TTFT
  fell from 6875 ms to 418 ms, a 6457 ms / 93.92% reduction. Every warm arm
  shared 34,179 leading system-prompt characters with its interactive turn.
  See `docs/evidence/ll22_production_warmup_ab_2026-08-14.json`.
- Risks or follow-ups: runtime slot pinning and cache persistence across model
  server restarts remain outside LL22.
