# Remote Coding P1 Release Gate

Remote Coding P1 combines the audit-P0 authenticated-transport prerequisite
with later product hardening. Its transport and plaintext-containment checks
must pass before Remote Coding can appear in a release; resilience,
supportability, and multi-device evidence follow before broader product
promotion.

## Scope

P1 covers these release-hardening requirements:

- Transport security: use pinned authenticated WSS or equivalent application-
  layer authenticated encryption, reject plaintext downgrade before sending a
  pairing secret or token, and issue short-lived channel-bound session
  authorization.
- Resource boundaries: close unauthenticated connections after a bounded
  deadline and enforce connection, frame, message, and per-source rate limits.
- Resilience: unexpected WebSocket closures schedule bounded automatic
  reconnects, sockets use ping intervals, command responses are correlated by
  request ID, and timed-out commands become visible to the user.
- Supportability: mobile and desktop diagnostics expose protocol, endpoint,
  reconnect, snapshot, and active-session state without raw tokens, token
  hashes, or pairing secrets.
- Host metadata: snapshots advertise protocol version and safe mobile
  capabilities, including that project management stays desktop-only.
- Multi-device readiness: paired devices can coexist, active session counts are
  visible, revocation is scoped to the selected mobile device, and pending
  interactions are visible and resolvable only by their initiating device.
- Soak evidence: iOS and Android must pass a user-operated LAN soak with
  background/resume, desktop sleep/wake, and desktop IP change recovery.

The first two requirements are covered as of 2026-09-06, by the static gates
`transport_security` and `resource_boundary`. They were originally specified as
`transportSecurity` and `resourceBoundary` manual checklist sections, and are
deliberately not that: a person ticking "the transport is secure" proves
nothing, and the checker had no such sections at all, so a passing report said
nothing about the two requirements RC1 exists for. Each gate now reads the
implementation *and* the name of the test that proves it, so neither the code
nor its coverage can be removed while the gate stays green. See
`docs/security_audit_2026-08-14.md` SA-06 and SA-10.

## Command

Create a manual checklist template:

```bash
dart run tool/remote_coding_p1_release_gate.dart \
  --write-template build/remote_coding_p1_manual_checklist.json
```

Run the release gate:

```bash
dart run tool/remote_coding_p1_release_gate.dart \
  --manual-checklist build/remote_coding_p1_manual_checklist.json \
  --support-packet build/mobile_support_packet.json \
  --support-packet build/desktop_support_packet.json \
  --multi-device-evidence build/multi_device_evidence.json \
  --out-json build/remote_coding_p1_release_gate.json \
  --out-md build/remote_coding_p1_release_gate.md
```

The command exits non-zero until every automated static gate and every
user-operated checklist field is ready.

## Automated Gate Coverage

| Gate | Requirement | How it is decided |
|------|-------------|-------------------|
| `transport_security` | Transport security | Pinned WSS with platform roots disabled, credentials refused on a non-confidential transport, a release policy that refuses a plaintext LAN bind, and a channel-bound short-lived session — each with the test that names it |
| `resource_boundary` | Resource boundaries | Authentication deadline, per-source and total occupancy, inbound frame size, and message-rate windows, enforced before the WebSocket upgrade — each with the test that names it |

These two are static rather than user-operated because they are properties of
the code, not of a session anyone can watch. What a person still has to
observe — that a real LAN session survives backgrounding, sleep/wake, and an IP
change — stays in `resilienceSoak`.

## Checklist Evidence

Required sections:

- `resilienceSoak`
- `supportPacket`
- `multiDevice`

There is deliberately no `transportSecurity` or `resourceBoundary` checklist
section. Those two requirements are decided by the static gates above, because
they are properties of the code: a checklist field for them would be a person
attesting to something they cannot observe in a session. See **Automated Gate
Coverage**.

Keep real-device screenshots, copied diagnostics, and build logs next to the
JSON report when preparing a release candidate. Diagnostics must be reviewed to
confirm they do not include mobile device tokens, desktop token hashes, or
pairing secrets.

## Support Packet Flow

Copy a P1 support packet from both sides of a paired session:

- Desktop: Settings > Remote Coding Host > Copy Support Packet.
- Mobile: Remote Coding connection or session screen > Copy Support Packet.

Each copied packet uses `schemaName: remote_coding_p1_support_packet`, includes
the redacted diagnostics snapshot, and carries a `manualChecklistPatch` for the
`supportPacket` checklist section. Pass both packet JSON files to the release
gate with repeated `--support-packet` arguments. The gate merges true checklist
fields from the packets, but the user-operated review still owns confirming that
the exported diagnostics contain no mobile device tokens, desktop token hashes,
or pairing secrets.

## Multi-Device Evidence Flow

Copy P1 multi-device evidence from the desktop after pairing two mobile devices:

- Desktop: Settings > Remote Coding Host > Copy Multi-Device Evidence.
- Confirm the revocation and remote approval boundary checks in the dialog only
  after testing them on real devices.
- Save the copied JSON and pass it to the release gate with
  `--multi-device-evidence`.

Each copied file uses `schemaName: remote_coding_p1_multi_device_evidence`,
includes redacted paired-device snapshots and active-session counts, and carries
a `manualChecklistPatch` for the `multiDevice` checklist section. The gate
merges true checklist fields from evidence files, while the user-operated review
still owns confirming the real two-device household behavior.

The SEC4.5g source gate treats paired devices as separate principals. Automated
tests cover same-device reconnect, cross-device filtering and rejection,
desktop-origin and stale identifiers, and revoked-device rejection. The manual
two-device run remains required for RC1 product-promotion evidence.
