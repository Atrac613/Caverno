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

Passing this P0 gate does not establish transport confidentiality. The current
LAN channel uses plaintext `ws://`, so an active LAN attacker can observe or
modify pairing, authentication, snapshots, prompts, and approval traffic. The
2026-08-14 audit records this as SA-06 in
`docs/security_audit_2026-08-14.md`.

Until RC1/SEC4.5 ships authenticated confidential transport and downgrade
rejection, a release build must not expose a plaintext non-loopback Remote
Coding listener. Disable or remove the feature from the release artifact; an
isolated-LAN assumption is not closure because the reusable credential and
approval channel remain plaintext. The current P0 checker does not verify this
containment, so its report is necessary but not sufficient for product
promotion.

SEC4.5b must extend the generated checklist/schema and Dart gate with a required
`transportContainment` result, add a focused gate test, and run a release-mode
artifact/runtime smoke that proves a plaintext non-loopback listener cannot
start. Documentation or a default-off UI setting is not evidence for this gate.

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
