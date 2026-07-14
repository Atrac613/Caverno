# Stable Diagnostic Signatures

## Goal

Activate stalled-diagnostic repair contracts only when the same authoritative
errors recur, independent of diagnostic ordering and unstable location text.

## Signature Semantics

Each Error diagnostic contributes normalized relative path, severity, code,
and message text. Components are deduplicated and sorted before joining.
Absolute path prefixes and volatile line or column numbers in messages are
normalized. The signature is internal evidence and is not shown to the model.

## Acceptance Criteria

1. Reordered equivalent diagnostics produce the same signature.
2. Changed code, path, or substantive message produces a different signature.
3. Absolute path and line or column changes alone do not change the signature.
4. Repair contracts require one repeated identical signature.
5. Session and canary telemetry report activation count, signature changes, and
   the maximum identical-signature streak without logging the raw signature.

## Verification

```bash
tool/codex_verify.sh
```
