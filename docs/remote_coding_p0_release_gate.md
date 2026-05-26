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

- `realDeviceMatrix`
- `failureUxMatrix`
- `releaseSigning`
- `dataProtection`

The generated report records blocked gate IDs and the next action for each
missing item.
