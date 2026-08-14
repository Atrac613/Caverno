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
  visible, and revocation is scoped to the selected mobile device.
- Soak evidence: iOS and Android must pass a user-operated LAN soak with
  background/resume, desktop sleep/wake, and desktop IP change recovery.

The current P1 checker predates the first two requirements and does not yet
accept or validate `transportSecurity` or `resourceBoundary` checklist
sections. Until the RC1/SEC4.5 implementation updates the checker and focused
tests in the same change, a passing P1 report is not final Remote Coding product
promotion evidence. See `docs/security_audit_2026-08-14.md` SA-06 and SA-10.

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

## Checklist Evidence

Required sections:

- `resilienceSoak`
- `supportPacket`
- `multiDevice`

The RC1 transport slice must add required `transportSecurity` and
`resourceBoundary` sections to the checklist schema, generated template, Dart
gate, and gate tests. Documentation alone does not satisfy those controls.

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
