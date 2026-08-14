# SEC4.3a Network Classification Task

Status: completed on 2026-08-14.

## Task

- Goal: classify every built-in HTTP operation as network access and every
  HTTP/browser result as remote, untrusted content before later authorization
  and taint decisions consume that metadata.
- User-visible behavior: approval and audit surfaces describe HTTP mutations as
  high-risk remote state changes and never describe HTTP/browser output as
  project-trusted content.
- Non-goals: centralize approval dispatch (SEC4.3b), enforce destination/DNS/
  redirect policy (SEC4.3c), or add response/time limits (SEC4.3d).

## Context

- Affected components:
  - `ToolCapabilityClassifier` in `caverno_tool_contracts`;
  - `DataSourceClassifier` and `ToolPerimeterClassifier`;
  - built-in HTTP and browser tool catalogs;
  - approval/audit perimeter summaries.
- Related docs:
  - `docs/security_audit_2026-08-14.md` SA-03;
  - `docs/local_llm_agent_roadmap.md` SEC4.3a;
  - `docs/roadmap.md` SEC4.
- Release gate: SEC4.3a is P0 and must close before an affected release.

## Implementation Tasks

1. **SEC4.3a-1 — Catalog contract.** Freeze the complete built-in HTTP and
   browser name sets in classifier tests so a newly added operation cannot
   silently fall back to `other` or project-trusted provenance.
2. **SEC4.3a-2 — Capability classification.** Add a distinct network-mutation
   capability for POST, PUT, PATCH, and DELETE. It must be high risk, mutate
   remote state, access the network, and have an external-side-effect command
   effect. Classify status, GET, and HEAD as network fetches.
3. **SEC4.3a-3 — Result provenance.** Classify every `http_*` and `browser_*`
   result as `remoteWeb` with `untrusted` trust, including errors, status-only
   results, navigation, page actions, waits, and close results.
4. **SEC4.3a-4 — Perimeter evidence.** Prove the combined perimeter context and
   summary carry the capability, network, mutation, provenance, and trust facts
   consumed by approval UI, audit logging, and SEC2 taint tracking.

## Implementation Notes

- Preferred approach: keep classification pure and centralized; use
  conservative family-prefix fallbacks after exact built-in mutation sets.
- Constraints: do not reroute execution or add a new approval mechanism in this
  slice. Existing taint/audit consumers receive the corrected classification
  and may therefore fail closed. Unknown non-network tool names retain their
  existing fallback.
- Generated files needed: none.
- Compatibility concern: adding an enum value requires updating every exhaustive
  switch over `ToolCapabilityClass`.

## Similar-Pattern Search

- Search terms: `http_get`, `http_head`, `http_post`, `http_put`, `http_patch`,
  `http_delete`, `http_status`, `browser_`, `networkFetch`, `remoteWeb`,
  `localDiagnostic`, and `ToolPerimeterContext`.
- Files inspected: capability/provenance classifiers and tests, browser policy,
  built-in network/browser handlers, perimeter summary, planning policy,
  routine policy, scheduler, and audit/taint consumers.
- Follow-up boundaries: approval bypass remains SEC4.3b; schemes, DNS, peers,
  redirects, and credentials remain SEC4.3c; buffering remains SEC4.3d.

## Acceptance Criteria

- `http_status`, GET, and HEAD are medium-risk network fetches that do not
  mutate state.
- POST, PUT, PATCH, and DELETE are high-risk network mutations with remote
  external side effects.
- Every built-in HTTP and browser result has `remoteWeb` provenance and
  `untrusted` trust, regardless of whether the operation reads or mutates.
- Mixed-case and whitespace-padded tool names normalize identically.
- Local diagnostics and project search tools retain their current provenance.
- Perimeter summaries expose `network`, remote mutation where applicable, and
  `output: untrusted (remote web)`.

## Verification

```bash
fvm dart test packages/caverno_tool_contracts/test/tool_capability_classifier_test.dart
fvm flutter test test/core/security/data_source_classifier_test.dart
fvm flutter test test/core/security/tool_perimeter_context_test.dart
fvm flutter test test/features/chat/presentation/widgets/tool_perimeter_summary_test.dart
tool/codex_verify.sh --no-codegen --no-tests
```

## Handoff Notes

- The task contract, classifier implementation, regression tests, and roadmap
  evidence were squash-integrated into `main` as one reviewable change.
- Verification passed:
  - 20 package classifier tests;
  - 53 focused Flutter perimeter, provenance, taint, UI, and approval tests;
  - `fvm dart analyze packages/caverno_tool_contracts`;
  - `fvm flutter analyze`;
  - `tool/codex_verify.sh --no-codegen --no-tests`.
- Do not mark SEC4.3 complete when SEC4.3a closes. SEC4.3b and SEC4.3c remain
  independent P0 release blockers.
- Next task: SEC4.3b must route every network mutation through the central
  approval boundary and prove that cached or full-access authorization cannot
  bypass untrusted-influence enforcement.
