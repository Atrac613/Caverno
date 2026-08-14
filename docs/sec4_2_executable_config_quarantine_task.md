# SEC4.2 Executable Configuration Quarantine Task

Status: completed on `feature/sec4-2-executable-config-quarantine` on
2026-08-14.

## Task

- Goal: ensure that imported or synchronized configuration cannot establish
  process, MCP, full-access, or remembered-permission authority.
- User-visible behavior: ordinary settings still import, while executable hooks
  remain disabled and MCP servers remain pending until the user reviews their
  exact normalized configuration.
- Non-goals: redesign MCP transport, implement the SEC4.3 destination policy,
  or remove explicitly configured hooks and MCP servers.

## Context

- Affected components:
  - JSON, QR, and onboarding settings import;
  - external-settings load, resync, and agent-kb preset application;
  - settings persistence and provider rebuild;
  - hook dispatch and pending MCP review connection.
- Related docs:
  - `docs/security_audit_2026-08-14.md` SA-02;
  - `docs/local_llm_agent_roadmap.md` SEC4.2;
  - `docs/external_config.md`.
- Release gate: SEC4.2 is P0 and must close before an affected release.

## Implementation Tasks

1. **SEC4.2a — Shared quarantine contract.** Add one domain service that clears
   imported full-access modes and cached grants, disables imported hooks, and
   changes every imported MCP server to pending with no trusted timestamp.
2. **SEC4.2b — Import and persistence boundary.** Apply the same service before
   JSON and QR imports mutate notifier state. Onboarding inherits the JSON
   boundary. Persist only the quarantined aggregate.
3. **SEC4.2c — External configuration boundary.** Quarantine executable entries
   on initial sync, manual resync, and app restart. Imported global enable flags
   must not activate existing executable configuration.
4. **SEC4.2d — Exact review boundary.** Show a redacted command, argument,
   environment-key, URL, type, and source diff before activation. Review must be
   expiring and non-cacheable, and any normalized identity change invalidates
   it. Do not connect pending stdio MCP servers to discover tools before review.
5. **SEC4.2e — Preset and delayed-runtime evidence.** Route the agent-kb preset
   through the same review model and prove zero process/client starts across
   import, provider rebuild, next turn, restart, and resync.

## Implementation Notes

- Preferred approach: keep parsing and validation separate from authorization;
  place quarantine immediately before settings persistence and again at every
  external merge boundary.
- Constraints: imported trust labels, enable flags, full-access modes, and
  saved grants never count as user authority.
- Generated files needed: none for SEC4.2a-SEC4.2c. Regenerate Freezed outputs
  only if the later review receipt requires a persisted entity change.
- Migration concern: already persisted local settings are not silently treated
  as a new import. Their executable entries remain subject to the runtime trust
  and exact-review gates added by SEC4.2d.

## Similar-Pattern Search

- Search terms: `AppSettings.fromJson`, `importSettings`, `importFromQr`,
  `applySnapshot`, `applyAgentKbPreset`, `externalToolHooksEnabled`,
  `McpServerTrustState.trusted`, `overrideServers`, and `Process.start`.
- Files inspected: settings file/QR services, SettingsNotifier, external
  settings service, MCP settings review, remote MCP connection manager, MCP
  provider, hook service, and ChatNotifier hook call sites.
- Follow-up boundaries: HTTP destination policy remains SEC4.3; host-wide path
  authorization remains SEC4.4.

## Acceptance Criteria

- JSON, QR, onboarding, and external-config payloads persist hooks as disabled
  and MCP servers as pending regardless of payload trust claims.
- Imported coding/chat full-access modes, legacy confirmation bypasses, local
  command rules, and routine Computer Use grants are cleared.
- No imported hook process or stdio MCP client starts during import, rebuild,
  next turn, restart, or resync.
- Pending MCP review does not connect or execute the server before exact user
  approval.
- Review displays only redacted executable details and is invalidated by any
  command, argv, environment-key set, URL, type, source, or trust-identity
  change.
- Normal non-executable settings continue to import and synchronize.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/settings/domain/services/executable_settings_quarantine_service_test.dart
tool/codex_verify.sh --no-codegen --test test/features/settings/data/external_settings_service_test.dart
tool/codex_verify.sh --no-codegen --test test/features/settings/presentation/providers/settings_notifier_test.dart
tool/codex_verify.sh --no-codegen --test test/features/settings/domain/services/external_tool_hook_service_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/data/datasources/remote_mcp_connection_manager_test.dart
tool/codex_verify.sh --no-codegen --test test/features/settings/presentation/widgets/external_tool_hook_approval_sheet_test.dart
tool/codex_verify.sh --no-codegen --no-tests
```

## Handoff Notes

- Implementation commits:
  - `cc538379` quarantines imported executable settings;
  - `7263454f` blocks pending MCP connections before client construction;
  - `8cfdda00` binds hook and MCP review to exact identities with 30-day expiry;
  - `e7e2574c` proves zero process/client starts at delayed runtime boundaries;
  - `ccd778d6` proves persisted quarantine survives provider restart.
- Focused entity, import, external-sync, notifier, hook-runtime, MCP-runtime,
  and review-widget suites pass. Static analysis and all workspace package
  tests pass.
- The full root suite reached 7,547 passing tests and seven unrelated failures.
  A focused rerun reproduced six baseline failures: four file-size ratchets,
  one model-capability fixture count, and one collaborator manifest marker.
  No SEC4.2 test failed.
- Next security slice: SEC4.3a, which classifies every built-in HTTP verb and
  browser navigation/read result as remote and untrusted before approval or
  cached/full-access handling.
