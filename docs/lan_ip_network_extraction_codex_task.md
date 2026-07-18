# LAN IP Network Extraction

## Task

- Goal: extract the public `LanIpNetwork` CIDR value object from
  `LanScanService` into an independently testable pure-Dart boundary.
- User-visible behavior: none. IPv4 and IPv6 parsing, normalization, host
  enumeration, containment, address ordering, scope handling, and existing
  import paths must remain compatible.
- Non-goals: scan planning, ping or TCP probing, port scanning, ARP/NDP or mDNS
  discovery, process execution, Riverpod provider wiring, or tool JSON changes.

## Context

- Affected files or components:
  - `lib/core/services/lan_scan_service.dart`
  - a new `lib/core/services/lan_ip_network.dart`
  - focused value-object and existing LAN service tests
  - file-size ratchets and the large-file refactor inventory
- Related docs:
  - `docs/large_file_refactor_plan.md`
  - `docs/large_file_boundary_inventory_2026_07_18.md`
- Reference implementation or pattern: recent network route and routine
  run-history slices first froze behavior, then moved one cohesive boundary
  behind narrow dependencies and exact line-count ratchets.
- Known quirks, compatibility rules, or release gates:
  - `lan_endpoint_discovery.dart` currently imports `LanIpNetwork` through
    `lan_scan_service.dart`;
  - `lan_scan_service.dart` must re-export the extracted type so downstream
    imports do not require migration;
  - IPv4 networks up to `/30` exclude network and broadcast addresses;
  - IPv6 ranges exclude the network address when host bits remain and refuse
    direct enumeration above `maxEnumeratedHosts`;
  - this branch is stacked on `feature/routine-run-history-extraction` until
    the preceding slices are integrated into `main`.

## Implementation Notes

- Preferred approach:
  - add direct characterization for all public `LanIpNetwork` operations;
  - move the class unchanged into `lan_ip_network.dart`;
  - import and export the new library from `lan_scan_service.dart`;
  - retain all scan orchestration and platform IO in `LanScanService`.
- Constraints:
  - preserve `LanIpNetwork` as the public class name;
  - preserve canonical address strings and comparison order;
  - introduce no Flutter, Riverpod, process, socket, or plugin dependency in
    the extracted library;
  - avoid Dart `part` files.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `LanIpNetwork`, CIDR, subnet enumeration, address comparison,
  scope ID, LAN endpoint discovery, and LAN scan tests.
- Files or modules inspected: `lan_scan_service.dart`,
  `lan_endpoint_discovery.dart`, all LAN scan and endpoint tests, coverage data,
  file-size inventory, and active worktrees.
- Follow-up tasks found: scan planning and link-layer table parsing remain
  possible later boundaries, but must not be mixed into this slice.

## Acceptance Criteria

- Required behavior:
  - valid IPv4 and IPv6 CIDRs normalize to the same network address and prefix;
  - host counts and enumerable addresses retain the existing caps and reserved
    address rules;
  - containment rejects invalid literals and mismatched address families;
  - address comparison keeps IPv4 before IPv6 and numeric ordering within a
    family;
  - scope stripping and IPv6 detection remain compatible;
  - existing imports from `lan_scan_service.dart` continue to compile.
- Edge cases:
  - malformed CIDRs and out-of-range prefixes;
  - IPv4 `/30`, `/31`, and `/32`;
  - small and wide IPv6 ranges;
  - scoped link-local IPv6 addresses;
  - invalid address strings and mixed-family comparisons.
- Failure paths: invalid inputs continue to return `null`, `false`, or lexical
  fallback ordering instead of throwing.
- Accessibility, localization, or platform expectations: none; this is a pure
  value-object extraction.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/core/services/lan_ip_network_test.dart \
  --test test/core/services/lan_scan_service_test.dart \
  --test test/core/services/lan_endpoint_discovery_test.dart \
  --test test/features/chat/data/datasources/built_in_lan_scan_tool_handler_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `LanIpNetwork` now owns pure IPv4 and IPv6 CIDR parsing,
  normalization, enumeration, containment, ordering, and scope handling in a
  199-line library. `lan_scan_service.dart` re-exports the type for source
  compatibility and fell from 1,038 to 843 physical lines. Both files have
  exact line-count ratchets.
- Tests run: the focused verification gate passed analysis, 13 internal-package
  tests, and 91 selected root tests. The full coverage gate passed analysis,
  13 internal-package tests, and 3,865 root tests.
- Coverage or low-coverage notes: overall line coverage reached 74.93%
  (53,311/71,147). The extracted value object reached 97.87% (92/94), while the
  remaining service reached 51.83% (170/328). Combined coverage rose from the
  original 57.82% snapshot to 62.09% (262/422).
- Risks or follow-ups: scan planning, platform parsing, and probe behavior
  remain in the service. Pause it now that the service is below 1,000 lines and
  refresh the inventory before selecting another extraction.
