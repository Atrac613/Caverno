# Network Route Tools Extraction

## Task

- Goal: extract route lookup, interface inspection, and path-MTU measurement
  from `NetworkTools` into an independently testable service.
- User-visible behavior: none. Existing tool names, arguments, commands, JSON
  responses, validation errors, and fallback behavior must remain compatible.
- Non-goals: DNS, mDNS, ping, traceroute, HTTP, neighbor, socket, handler, or
  tool-definition changes.

## Context

- Affected files or components:
  - `lib/features/chat/data/datasources/network_tools.dart`
  - a new route-tools service under the same data-source directory
  - focused network data-source tests
  - file-size ratchets and the large-file refactor plan
- Related docs:
  - `docs/large_file_refactor_plan.md`
  - `docs/large_file_boundary_inventory_2026_07_18.md`
- Reference implementation or pattern: the existing HTTP, neighbor, and socket
  service extractions preserve the static `NetworkTools` facade while moving a
  coherent concern behind injected dependencies.
- Known quirks, compatibility rules, or release gates:
  - macOS uses `route` and `ifconfig`; Linux uses `ip` and may use
    `tracepath`.
  - Path MTU falls back to the selected interface MTU when active discovery
    does not produce a measurement.
  - Literal IP targets and host lookups must retain deterministic
    address-family filtering and ordering.
  - Existing imports of `NetworkProcessRunner` and `NetworkAddressLookup` from
    `network_tools.dart` must keep compiling.

## Implementation Notes

- Preferred approach:
  - introduce a route-tools service that owns route, interface, and path-MTU
    parsing plus their private value objects;
  - inject the target platform as well as process and address lookup callbacks
    so macOS, Linux, and unsupported behavior can be tested on any host;
  - keep the existing static `NetworkTools` methods as compatible delegates;
  - move shared dependency typedefs to a small dependency file and re-export
    them from `network_tools.dart`.
- Constraints:
  - preserve exact public method signatures and JSON shapes;
  - preserve process command order, lookup filtering, and fallback precedence;
  - keep unrelated DNS, mDNS, ping, and traceroute code unchanged;
  - avoid Dart `part` files so the extracted service is an independent library.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: route lookup helpers, interface parsers, path-MTU measurement,
  shared process runners, and address lookups.
- Files or modules inspected: `network_tools.dart`, its focused tests, the
  built-in network handler, and existing extracted network services.
- Follow-up tasks found: reassess the remaining DNS, mDNS, ping, and traceroute
  boundary only after this slice lands and the inventory is refreshed.

## Acceptance Criteria

- Required behavior:
  - `NetworkTools.routeLookup`, `interfaceInfo`, and `pathMtu` retain their
    existing public contracts;
  - macOS and Linux command selection, parsing, filtering, and JSON results are
    pinned by deterministic service tests;
  - the compatibility facade is covered by existing product-path tests;
  - shared dependency typedef imports remain source compatible.
- Edge cases:
  - invalid address-family values;
  - literal IPv4 and IPv6 targets;
  - missing interfaces or routes;
  - filtered interface families;
  - failed or empty process output;
  - Linux tracepath fallback and interface-MTU fallback.
- Failure paths: unsupported platforms and process or lookup failures retain
  structured JSON errors or empty results as currently defined.
- Accessibility, localization, or platform expectations: no UI or localized
  string changes; deterministic tests cover macOS, Linux, and unsupported
  platform branches.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/network_route_tools_test.dart \
  --test test/features/chat/data/datasources/network_tools_test.dart \
  --test test/features/chat/data/datasources/built_in_network_tool_handler_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: complete. `NetworkRouteTools` owns route, interface, and path-MTU
  behavior behind injected platform IO, while `NetworkTools` preserves its
  static API and re-exports the shared dependency typedefs.
- Tests run:
  - the focused verifier passed 91 root tests and 13 internal-package tests;
  - the full coverage gate passed analysis, 3,849 root tests, and 13
    internal-package tests.
- Coverage or low-coverage notes: the extracted service reached 93.88%
  (414/441); the remaining facade reached 23.36% (71/304); their combined
  executable coverage is 65.10% (485/745). Repository coverage is 74.67%
  (53,110/71,124).
- Risks or follow-ups: preserve the existing macOS behavior that omits scoped
  IPv6 `ifconfig` addresses whose zone identifiers contain non-hexadecimal
  letters. Address that parser gap only in a separate behavior-change task.
