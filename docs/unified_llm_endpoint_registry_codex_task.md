# Unified LLM Endpoint Registry — Codex Task

Consolidate the two parallel LLM endpoint registries (`LlmEndpointProfile` and
`NamedEndpoint`) into a single registry. This document is self-contained: it
carries the background, the target design, and three sequential slices. Each
slice is one focused Codex run / review pass; land them in order. The app must
build, pass `flutter analyze` and `flutter test`, and behave correctly after
every slice.

## Background / Problem

Today the app has two independent notions of "an LLM endpoint":

1. **`LlmEndpointProfile`** (`lib/features/settings/domain/entities/app_settings.dart`,
   ~line 570) — manually registered primary-connection presets
   (`id` = UUID, `label`, `baseUrl`, `apiKey`, `model`, `createdAt`). Managed in
   `GeneralSettingsPage`. The active profile mirrors the top-level
   `AppSettings.baseUrl` / `apiKey` / `model` fields; the mirror invariant is
   maintained by `AppSettings.withNormalizedLlmEndpointProfiles()` because QR
   import and external settings sync write the top-level fields directly.
2. **`NamedEndpoint`** (same file, ~line 638) — the "LL8 LAN mesh" registry
   (`id` = lowercased normalized baseUrl, `label`, `baseUrl`, `apiKey`,
   `enabled`, `createdAt`). Populated from LAN discovery in `MeshSettingsPage`.
   Per-role endpoint pins (`memoryExtractionEndpointId`, `subagentEndpointId`,
   `goalSuggestionEndpointId`, `approvalAutoReviewEndpointId`) reference these
   ids and are resolved by `MeshEndpointRouter`
   (`lib/features/settings/domain/services/mesh_endpoint_router.dart`).

Symptoms of the split:

- The same physical server can be registered in both lists, with two labels and
  two API keys.
- A LAN-discovered server cannot become the primary endpoint without manually
  copying its URL into a profile; manually registered profiles do not appear as
  role-routing targets.
- `NamedEndpoint.id` is derived from the base URL, so a DHCP address change
  creates a new identity and orphans role pins and health state.
- Known production bug: a role pinned to a mesh endpoint with an empty role
  model resolves to the **primary** endpoint's model name
  (`AppSettings._resolveRoleModel`) and sends it to the mesh host, producing
  400 "model not found" once the primary points at a different server.

## Target Design

One entity, one list, one id space:

```dart
enum LlmEndpointSource { manual, discovered }

@freezed
abstract class LlmEndpoint with _$LlmEndpoint {
  const factory LlmEndpoint({
    required String id,          // opaque stable id; UUID v4 for new entries
    @Default('') String label,
    @Default('') String baseUrl,
    @Default('') String apiKey,
    @Default('') String model,   // default/preferred model for this endpoint
    @Default(true) bool enabled, // selectable as primary + role-routing target
    @JsonKey(unknownEnumValue: LlmEndpointSource.manual)
    @Default(LlmEndpointSource.manual)
    LlmEndpointSource source,
    DateTime? createdAt,
  }) = _LlmEndpoint;
}
```

- `AppSettings.llmEndpoints` replaces both `llmEndpointProfiles` and
  `namedEndpoints`. `activeLlmEndpointId` is retained and points into the
  unified list.
- The top-level `baseUrl` / `apiKey` / `model` mirror and its reconciliation
  method are **retained** (renamed `withNormalizedLlmEndpoints()`); the entire
  chat/data layer reads `settings.baseUrl`, and QR import / external sync still
  write it directly. Do not remove the mirror in this task.
- The id is opaque and **not** derived from the base URL, so an IP change is an
  edit, not a new identity. Base-URL uniqueness is NOT enforced at the entity
  level (two presets on the same server with different default models are a
  legitimate use case); only discovery registration dedupes by base URL.
- LAN discovery becomes a way to add entries to this single registry;
  `MeshSettingsPage` is deleted (slice 3) and a scan affordance moves into the
  endpoint list in `GeneralSettingsPage`.
- Role pins keep their field names but reference unified ids.
  `MeshEndpointRouter` / `EndpointHealthTracker` /
  `MeshSecondaryCompletionRunner` keep their behavior (primary fallback,
  demotion) — only the endpoint type changes. Renaming those classes is a
  non-goal.

### Non-goals (all slices)

- Do not change `ModelCapabilityProfile` / `ModelHarnessConfig` identity keying
  (still `provider|baseUrl|model`).
- Do not remove the top-level `baseUrl` / `apiKey` / `model` mirror.
- Do not rename `MeshEndpointRouter`, `EndpointHealthTracker`,
  `MeshSecondaryCompletionRunner`, or the `mesh_endpoint_provider.dart` file.
- Do not touch voice endpoints (`whisperUrl`, `voicevoxUrl`), MCP servers, or
  the feedback endpoint.
- No change to the Apple Foundation Models provider path beyond keeping current
  behavior compiling.

---

## Slice 1 — Unified entity, migration, mechanical call-site updates

### Goal

Replace `LlmEndpointProfile` + `NamedEndpoint` with `LlmEndpoint` and migrate
persisted settings. Pure consolidation: no user-visible behavior change beyond
the mesh page now listing all registered endpoints (acceptable transitional
state; the page is deleted in slice 3).

### Entity and AppSettings changes

In `lib/features/settings/domain/entities/app_settings.dart`:

- Add `LlmEndpoint` + `LlmEndpointSource` as above, with the usual companions
  mirroring the existing classes: `normalizeBaseUrl` (trim + strip trailing
  slashes, as `LlmEndpointProfile.normalizeBaseUrl` does today),
  `normalizedBaseUrl`, `normalizedLabel`, `normalizedModel`, `displayLabel`
  (label fallback to baseUrl), `isValid` (non-empty baseUrl),
  `normalizedForPersistence()`, and JSON list helpers following the
  `_namedEndpointsFromJson` / `_namedEndpointsToJson` pattern.
- Delete `LlmEndpointProfile` and `NamedEndpoint` and their JSON helpers.
- Replace the fields:
  - `llmEndpointProfiles` + `namedEndpoints` → `llmEndpoints`
    (`List<LlmEndpoint>`, `@Default([])`, JSON helpers).
  - Keep `activeLlmEndpointId` and `seededLlmEndpointId` as-is.
- Replace the getters/methods (same semantics, new type):
  - `usableLlmEndpointProfiles` → `usableLlmEndpoints` (normalized + valid).
  - `activeLlmEndpointProfile` → `activeLlmEndpoint`.
  - `enabledNamedEndpoints` → `enabledLlmEndpoints` (enabled + valid, in
    registration order). Note the semantics change deliberately: this list now
    includes the active endpoint too. Router paths tolerate that (resolving the
    active endpoint targets the same URL as the primary). See call-site rules
    below.
  - `namedEndpointForBaseUrl(baseUrl)` → `llmEndpointForBaseUrl(baseUrl)` —
    look up by case-insensitive normalized base URL comparison (the id is no
    longer URL-derived), last match wins as today.
  - `withNormalizedLlmEndpointProfiles()` → `withNormalizedLlmEndpoints()`,
    identical reconciliation: seed a single entry from top-level fields when
    the list is empty, repoint a dangling `activeLlmEndpointId`, mirror
    top-level `baseUrl` / `apiKey` / `model` into the active entry.

### Persisted-settings migration

Extend `AppSettings.migrateLegacyJson`. **Critical:** the method currently
returns early when `codingApprovalMode` exists, and every real install has that
key. Restructure it into independent steps so the endpoint migration always
runs:

```dart
static Map<String, dynamic> migrateLegacyJson(Map<String, dynamic> json) {
  var migrated = json;
  migrated = _migrateApprovalMode(migrated);   // existing logic + its guard
  migrated = _migrateUnifiedEndpoints(migrated); // new; guard: 'llmEndpoints' key
  return migrated;
}
```

`_migrateUnifiedEndpoints` rules (pure JSON transform, no entity dependency on
removed classes):

1. If the JSON already contains `llmEndpoints`, return unchanged.
2. Read legacy `llmEndpointProfiles` and `namedEndpoints` lists (either may be
   absent or malformed — skip non-map items defensively).
3. Start from the profiles, in order. Each becomes an `llmEndpoints` entry with
   its id, label, baseUrl, apiKey, model, createdAt preserved;
   `enabled: true`, `source: 'manual'`.
4. For each named endpoint, match against already-merged entries by
   case-insensitive normalized base URL:
   - **Match** → merge into the existing entry (profile id survives): keep the
     profile's label/apiKey when non-empty, otherwise take the named
     endpoint's; keep `enabled: true` (the profile was actively selectable —
     deliberate choice, note it in the code comment). Record the id mapping
     `namedId → survivingId`.
   - **No match** → append as a new entry preserving the legacy id string
     (opaque ids make the old URL-derived id acceptable, and role pins keep
     working without remapping), with `enabled`, label, apiKey, createdAt
     preserved, `model: ''`, `source: 'discovered'`.
5. Remap the four role-pin fields (`memoryExtractionEndpointId`,
   `subagentEndpointId`, `goalSuggestionEndpointId`,
   `approvalAutoReviewEndpointId`) through the merge mapping from step 4.
6. Remove the `llmEndpointProfiles` and `namedEndpoints` keys from the output.

### SettingsNotifier consolidation

In `lib/features/settings/presentation/providers/settings_notifier.dart`:

- `upsertLlmEndpointProfile` → `upsertLlmEndpoint`. Keep the current logic
  (empty id → `Uuid().v4()`, preserve createdAt on update, new entries become
  active) and add base-URL dedupe: when the incoming entry has a **new** id but
  an existing entry shares its normalized base URL AND the caller is a
  discovery registration, update that entry in place instead of appending.
  Implement this as an explicit parameter (`bool dedupeByBaseUrl = false`) so
  manual "Add endpoint" can still intentionally create a second preset for the
  same server.
- `selectLlmEndpointProfile` → `selectLlmEndpoint`; refuse selecting a
  disabled endpoint (no-op).
- `removeLlmEndpointProfile` → `removeLlmEndpoint` (same guards: last entry
  not removable, active removal falls back to first remaining).
- Fold `upsertNamedEndpoint` / `removeNamedEndpoint` away; add
  `setLlmEndpointEnabled(String id, bool enabled)` for the mesh page's toggle
  (and slice 3's UI). Disabling the **active** endpoint is a no-op.
- Replace every `withNormalizedLlmEndpointProfiles()` call (also in
  `lib/features/settings/data/settings_repository.dart`).

### Mechanical call-site updates (type/getter rename only, keep semantics)

- `lib/features/settings/domain/services/mesh_endpoint_router.dart` — router +
  tests take `List<LlmEndpoint>`.
- `lib/features/chat/data/datasources/mesh_secondary_completion_runner.dart`
- `lib/features/chat/data/datasources/participant_completion_runner.dart`
  (`settings.namedEndpoints` → `settings.enabledLlmEndpoints`; it previously
  received the raw list — check whether it filtered enabled itself and keep the
  effective set identical).
- `lib/features/chat/presentation/providers/chat_notifier_subagent_handlers.dart`
- `lib/features/chat/presentation/providers/worktree_agent_task_executor.dart`
- `lib/features/chat/presentation/providers/worktree_agent_task_launcher.dart`
  (`enabledNamedEndpoints` → `enabledLlmEndpoints`).
- `lib/features/chat/presentation/pages/chat_page.dart`,
  `lib/features/chat/presentation/widgets/participant_roster_bar.dart`.
- `lib/features/settings/presentation/providers/local_model_lifecycle_provider.dart`
  (builds endpoint options from primary + `namedEndpoints`; switch to the
  unified list, skipping the entry that duplicates the primary base URL so the
  options list does not show the primary twice).
- `lib/features/settings/presentation/pages/mesh_settings_page.dart` — keep the
  page compiling against the unified registry (registered section lists
  `settings.llmEndpoints`, register button calls
  `upsertLlmEndpoint(..., dedupeByBaseUrl: true)` with
  `source: LlmEndpointSource.discovered`; do not make a newly registered
  discovery entry active — preserve today's behavior where mesh registration
  does not switch the primary. Note: `upsertLlmEndpoint` activates new
  entries, so it needs an `activate` flag or equivalent; keep manual adds
  activating and discovery adds not activating).
- `lib/features/settings/presentation/pages/model_routing_settings_page.dart` —
  `_endpointConfig` + `_RoleEndpointDropdown` read the unified list
  (`enabledLlmEndpoints`).
- `lib/features/settings/presentation/pages/general_settings_page.dart` — uses
  the renamed notifier methods/getters; `_EndpointEditorDialog` produces an
  `LlmEndpoint`.

**Call-site rule:** paths that feed `MeshEndpointRouter` / the completion
runners get `enabledLlmEndpoints` (including active is harmless — same URL as
primary). Picker/roster paths that enumerate *additional* targets next to an
explicit primary (worktree launcher, participant roster) should exclude the
active endpoint to avoid presenting the primary twice; verify each call site's
current behavior and preserve the effective target set.

### Generated code and tests

- Run `dart run build_runner build --delete-conflicting-outputs` and commit the
  regenerated `*.freezed.dart` / `*.g.dart`.
- Update the existing tests mechanically:
  `test/features/settings/domain/entities/app_settings_test.dart`,
  `test/features/settings/presentation/providers/settings_notifier_test.dart`,
  `test/features/settings/domain/services/mesh_endpoint_router_test.dart`,
  `test/features/chat/data/datasources/mesh_secondary_completion_runner_test.dart`,
  `test/features/chat/data/datasources/participant_completion_runner_test.dart`,
  `test/features/chat/presentation/providers/worktree_agent_task_launcher_test.dart`,
  `test/features/chat/presentation/widgets/participant_roster_bar_test.dart`,
  `test/features/settings/domain/services/local_model_preparation_service_test.dart`,
  `test/features/settings/presentation/pages/local_stack_settings_page_test.dart`,
  `test/features/settings/presentation/pages/general_settings_page_test.dart`.
- Add migration tests in `app_settings_test.dart` from raw JSON maps:
  - profiles only → migrated 1:1, active id preserved.
  - named endpoints only → entries preserved with legacy ids; role pins intact.
  - overlap (same base URL, different case/trailing slash) → merged entry keeps
    the profile id/apiKey/label; role pin pointing at the named id is remapped.
  - both keys absent (fresh install JSON) → no `llmEndpoints` key materialized
    by migration; runtime seeding via `withNormalizedLlmEndpoints` still works.
  - JSON already containing `llmEndpoints` → untouched.
  - **JSON containing `codingApprovalMode`** → endpoint migration still runs
    (regression guard for the early-return restructure).

### Slice 1 acceptance criteria

- `flutter analyze` clean; full `flutter test` passes.
- No references to `LlmEndpointProfile` / `NamedEndpoint` /
  `llmEndpointProfiles` / `namedEndpoints` remain in `lib/` or `test/`
  (grep to confirm).
- A settings JSON captured from the current build loads with all endpoints,
  the active selection, and role pins intact.

---

## Slice 2 — Endpoint-aware role model resolution (400-bug fix)

### Goal

A role pinned to an endpoint with an empty role model must resolve to **that
endpoint's** default model, not the primary's model name. This fixes the
observed 400 "model not found" when the primary points at a different server.

### Changes

- `AppSettings._resolveRoleModel(String roleModel)` → extend to
  `_resolveRoleModel(String roleModel, String roleEndpointId)`:
  1. Apple provider → `effectiveModel` (unchanged).
  2. Non-empty trimmed `roleModel` → use it (unchanged).
  3. Empty role model + non-empty `roleEndpointId` resolving to a registered,
     enabled endpoint whose `model` is non-empty → use the endpoint's model.
  4. Otherwise → `effectiveModel` (unchanged fallback).
  Update the four `effectiveXModel` getters to pass their matching endpoint id
  field.
- Check every call site that pairs `effectiveXModel` with
  `xEndpointId` when invoking `MeshSecondaryCompletionRunner.run/resolve`
  (chat notifier and its handler part-files, routine execution, worktree
  executor): they must keep passing a primary-valid `fallbackModel`
  (`settings.model`) for demotion. The demotion path is unchanged.
- Discovery registration seeds the endpoint default model: in the mesh page's
  register action (and slice 3's scan UI), set `model` to the first advertised
  model id from `DiscoveredEndpoint.modelIds` when non-empty.

### Slice 2 acceptance criteria

- New unit tests in `app_settings_test.dart`:
  - role model empty + pinned endpoint with default model → endpoint model.
  - role model empty + pinned endpoint without default model → primary model
    (current behavior preserved).
  - role model set → role model wins regardless of pin.
  - pin references a missing/disabled endpoint → primary model.
- Existing runner/router tests still pass (demotion still uses
  `fallbackModel`).

---

## Slice 3 — UI consolidation

### Goal

One place to manage endpoints: the endpoint list in `GeneralSettingsPage`
gains LAN scan; `MeshSettingsPage` is deleted; role routing and local-stack
pages read the unified registry (already wired in slice 1 — this slice is UI
polish and removal).

### Changes

- `GeneralSettingsPage` endpoint section (`_buildEndpointList`):
  - Add a "Scan LAN" `TextButton.icon` next to "Add endpoint", driving
    `meshDiscoveryProvider` (`lib/features/settings/presentation/providers/mesh_endpoint_provider.dart`,
    which stays where it is).
  - While scan results are present, render a "Discovered on LAN" section below
    the registered list, reusing the tile content from the old
    `_DiscoveredTile` (server hint, host:port, model count). One-tap register →
    `upsertLlmEndpoint(dedupeByBaseUrl: true, activate: false)` with
    `source: discovered`, label `'{serverHint} ({host})'`, and default model
    from `modelIds.first`. Entries whose base URL already exists show the
    "registered" state instead of the button (via `llmEndpointForBaseUrl`).
  - Endpoint tiles: show a `source: discovered` indicator (small icon or badge)
    and the enabled state. Add an enabled toggle to `_EndpointEditorDialog`
    (plus the endpoint default model field if not already present). Disabled
    endpoints render dimmed and cannot be selected as active (guarded in the
    notifier since slice 1 — surface a SnackBar on tap).
- Delete `mesh_settings_page.dart`, its `AdvancedSettingsPage` entry
  (`lib/features/settings/presentation/pages/advanced_settings_page.dart`
  ~line 53–66), and any mesh-page-specific tests. Keep
  `meshDiscoveryProvider` and the router/health providers.
- `ModelRoutingSettingsPage`: role endpoint dropdowns list **all** enabled
  endpoints by `displayLabel` (including the active one — excluding it would
  dangle a stored pin when its endpoint becomes active), with the existing
  empty option meaning "Primary". The role model dropdown for a pinned
  endpoint already fetches that endpoint's model list via `_endpointConfig`;
  verify it now resolves from the unified registry and that an empty role model
  displays the effective default (endpoint model, from slice 2) as hint text.
- Localization (`assets/translations/en.json`, `assets/translations/ja.json`):
  - Add keys for the scan affordance in general settings (e.g.
    `settings.endpoint_scan`, `settings.endpoint_scan_scanning`,
    `settings.endpoint_discovered_section`, `settings.endpoint_registered_badge`,
    reusing existing `settings.mesh_*` copy where it fits).
  - Remove `settings.mesh_*` keys that become unused (verify each with grep
    before deleting; `settings.mesh_title` etc. must not be referenced).
  - Both locales updated in the same commit; translation JSON is the one place
    where Japanese text is expected.
- Widget tests:
  - `general_settings_page_test.dart`: scan button triggers discovery notifier;
    a discovered tile registers a non-active, source=discovered endpoint with
    default model; an already-registered URL shows the registered state;
    a disabled endpoint cannot be activated.
  - Update/remove mesh page tests; `advanced_settings_page` test (if any) loses
    the mesh entry.

### Slice 3 acceptance criteria

- `MeshSettingsPage` is gone; no dangling routes, imports, or i18n keys.
- Scan → register → pin a role to the new endpoint → switch primary — all from
  the settings UI without typing a URL manually.
- `flutter analyze` clean; full `flutter test` passes.

---

## Similar-Pattern Search

Before finishing each slice:

- Search terms: `NamedEndpoint`, `namedEndpoints`, `LlmEndpointProfile`,
  `llmEndpointProfiles`, `withNormalizedLlmEndpointProfiles`,
  `enabledNamedEndpoints`, `namedEndpointForBaseUrl`, `settings.mesh_`,
  `upsertNamedEndpoint`.
- Also check non-Dart surfaces: `assets/translations/*.json`, `docs/`,
  `CLAUDE.md` (architecture section mentions mesh settings), integration tests
  under `integration_test/`, and any CLI/headless code under `lib/` that
  deserializes `AppSettings` JSON.
- Record follow-ups found instead of expanding the slice.

## Verification

```bash
tool/codex_verify.sh
```

For focused runs while iterating:

```bash
tool/codex_verify.sh --test test/features/settings/domain/entities/app_settings_test.dart
tool/codex_verify.sh --test test/features/settings/presentation/providers/settings_notifier_test.dart
```

After entity edits, regenerate before testing:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Handoff Notes (fill in per slice)

- Summary:
- Tests run:
- Migration risks: (call out anything that could lose a user's registered
  endpoint, active selection, or role pin on upgrade)
- Follow-ups: (candidates already known: renaming `MeshEndpointRouter` →
  `LlmEndpointRouter`; endpoint-identity-aware `ModelCapabilityProfile` keying
  so an IP change keeps probe history; discovery re-match proposal "endpoint X
  moved to a new IP" using the advertised model-list fingerprint)
