# Remote Coding P0 Release Gate

Remote Coding P0 is the product-release gate for LAN mobile control of an
existing desktop coding project. It combines automated static checks with
user-operated evidence for the parts that require real devices, signing
credentials, and upgraded local data.

## Scope

P0 covers these release blockers:

- Real-device matrix: macOS host with iOS and Android must pass pairing,
  reconnect, streaming, stop, approval, and revocation.
- Failure UX matrix: host stopped, Wi-Fi mismatch, desktop IP change, expired
  QR, and token rejection/revocation must show actionable mobile recovery
  guidance.
- Safety: remote-origin file mutations, git writes, and non-read-only local
  commands must require approval; saved deny rules must block before mobile
  approval; mobile must not add or remove desktop projects.
- Release signing and permissions: macOS notarization, iOS signing, Android
  signing, local-network metadata, and socket entitlements must be reviewed.
- Data protection: mobile tokens must stay in secure storage, desktop state must
  store token hashes only, redacted diagnostics must exclude token material, and
  existing settings/conversations must start after upgrade.

## Security Audit Qualification

Passing this P0 gate does not close reusable transport tokens. SEC4.5c now
uses pinned `wss://` with a certificate pin on pairing QR codes, and the
client refuses plaintext downgrade before `auth`. The 2026-08-14 audit still
records reusable session tokens as SA-06 remainder (SEC4.5d) in
`docs/security_audit_2026-08-14.md`.

A release build must not expose a plaintext non-loopback Remote Coding
listener. Isolated-LAN assumptions are not closure for remaining token
lifetime work.

SEC4.5b adds a required `transportContainment` result to this gate. The Dart
checker fails when the production server can still bind `InternetAddress.anyIPv4`
directly. The product-isolate smoke must also print
`plaintext_non_loopback_listener_can_start=false`:

```bash
dart run --define=dart.vm.product=true tool/remote_coding_plaintext_lan_smoke.dart
```

Documentation or a default-off UI setting is not evidence for this gate.

## Command

Create a manual checklist template:

```bash
dart run tool/remote_coding_p0_release_gate.dart \
  --write-template build/remote_coding_p0_manual_checklist.json
```

Run the release gate:

```bash
dart run tool/remote_coding_p0_release_gate.dart \
  --manual-checklist build/remote_coding_p0_manual_checklist.json \
  --out-json build/remote_coding_p0_release_gate.json \
  --out-md build/remote_coding_p0_release_gate.md
```

The command exits non-zero until every automated static gate and every
user-operated checklist field is ready.

## Checklist Evidence

The checklist is intentionally boolean and evidence-driven. Keep supporting
screenshots, build logs, or App Store/Play Console/Xcode artifacts next to the
JSON report when preparing a release candidate.

Required sections:

- `transportContainment` (automated; schema version 2)
- `realDeviceMatrix`
- `failureUxMatrix`
- `releaseSigning`
- `dataProtection`

The generated report records blocked gate IDs and the next action for each
missing item.
