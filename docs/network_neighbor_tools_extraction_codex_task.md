# Network Neighbor Tools Extraction

Status: complete on the current F5 refactoring stack.

## Task

- Goal: move ARP and NDP cache execution, platform selection, parsing,
  filtering, and ordering out of `network_tools.dart` behind an injectable
  process runner and platform value.
- User-visible behavior: none. Existing public signatures, commands, platform
  errors, filtering, ordering, and JSON envelopes remain compatible.
- Non-goals: route lookup, interface inventory, DNS, mDNS, path MTU, ping,
  traceroute, HTTP, raw sockets, or built-in tool schemas.

## Current Behavior Contract

- Supported `ip_version` values are `all`, `ipv4`, and `ipv6`; invalid values
  return the existing ordered validation error.
- macOS reads `arp -a` for IPv4 and `ndp -an` for IPv6. Linux reads
  `ip neighbor show` and `ip -6 neighbor show`.
- Non-zero commands contribute no entries. Unsupported platforms return the
  existing explicit error before any command runs.
- Incomplete, failed, missing-MAC, and broadcast-MAC entries are ignored.
- MAC addresses are lowercase. macOS ARP preserves hostnames except `?`;
  interface, state, source, and IP version fields retain current presence rules.
- Host filtering matches a normalized IP exactly or a case-insensitive
  hostname substring. IPv6 zone suffixes do not affect comparison.
- Results sort IPv4 before IPv6 and numerically within each family.
- `ndp` remains the IPv6-only compatibility wrapper.

## Implementation Notes

1. Add shared pure IP normalization and comparison helpers used by neighbor,
   route, interface, and mDNS code.
2. Add `NetworkNeighborTools` with an injected platform and process runner.
3. Move the neighbor entry model and all ARP/NDP-specific private helpers.
4. Leave exact-signature static delegates in `NetworkTools`.
5. Add direct tests for macOS, Linux, unsupported platforms, parser rejection,
   filtering, ordering, command failures, and NDP delegation.
6. Lower exact line-count ratchets for every new boundary.

## Constraints

- Do not execute real neighbor-cache commands in direct tests.
- Do not change command arguments, error text, JSON keys, or omission rules.
- Do not add network or process packages.
- Do not move adjacent route, interface, or mDNS models in this tranche.
- Generated files needed: none.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/network_neighbor_tools_test.dart \
  --test test/features/chat/data/datasources/network_tools_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run `tool/codex_verify.sh --coverage --no-codegen` before re-inventorying F5.

## Handoff Notes

- Summary: ARP and NDP process execution, platform selection, parsing,
  filtering, ordering, and result formatting now live in
  `NetworkNeighborTools`. `NetworkTools` retains the public static delegates,
  while shared IP normalization and ordering live in
  `network_address_utils.dart`.
- Tests run: the focused network and ratchet gate passed 178 root tests. The
  final repository gate passed static analysis, 3,794 root tests, and the
  previously completed 13-test internal-package gate.
- Coverage or low-coverage notes: the full root suite reached 73.99% line
  coverage. `NetworkNeighborTools` reached 98.10%, and the shared address
  helpers reached 88.89%.
- Risks or follow-ups: real platform commands remain outside deterministic
  unit tests. Re-run a macOS or Linux smoke only when command output behavior
  changes; no live smoke is required for this behavior-preserving move.
