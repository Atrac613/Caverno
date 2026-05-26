# Remote Coding P1 Release Gate

Remote Coding P1 is the product hardening gate after the P0 safety and launch
blockers are satisfied. It focuses on LAN resilience, supportability, and
multi-device behavior for mobile control of existing desktop coding projects.

## Scope

P1 covers these release-hardening requirements:

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

Keep real-device screenshots, copied diagnostics, and build logs next to the
JSON report when preparing a release candidate. Diagnostics must be reviewed to
confirm they do not include mobile device tokens, desktop token hashes, or
pairing secrets.
