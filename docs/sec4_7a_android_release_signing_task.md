# SEC4.7a Android Release Signing Fail-Closed Gate

Status: completed on 2026-08-23.

## Task

- Goal: prevent Android release artifacts from silently using the debug signing
  configuration when release credentials are absent or invalid.
- User-visible behavior: debug development remains available, while release APK
  and app-bundle requests fail early with actionable signing guidance.
- Non-goals: provisioning a keystore, changing secret distribution, or fixing
  the other SA-16 supply-chain findings.

## Context

- Affected components: Android application Gradle configuration and its release
  regression test.
- Related finding: SA-16 in `docs/security_audit_2026-08-14.md`.
- Release gate: SEC4.7 supply-chain and release hardening.

## Implementation Notes

- Detect Gradle tasks that produce release artifacts, including Flutter's
  `assembleRelease` and `bundleRelease` entrypoints.
- Require `keyAlias`, `keyPassword`, `storeFile`, and `storePassword` plus an
  existing regular keystore file before configuring release signing.
- Throw a `GradleException` during configuration when a release artifact was
  requested without complete signing material.
- Leave non-release tasks usable without local signing credentials.
- Remove the release-to-debug signing fallback completely.

## Similar-Pattern Search

- Search terms: `signingConfig`, `key.properties`, `assembleRelease`,
  `bundleRelease`, `debug signing`, and release build scripts.
- Files inspected: Android application Gradle configuration, repository ignore
  rules, Flutter release guidance, existing release-gate tests, roadmap, and
  security audit.
- Follow-up tasks found: immutable GitHub Action pins, least-privilege workflow
  permissions, pinned FVM, npm Dependabot coverage, and a Gradle distribution
  checksum remain separate SA-16 slices.

## Acceptance Criteria

- Release APK and app-bundle tasks fail before compilation without signing
  material.
- Incomplete properties and a missing keystore file also fail closed.
- No release build can select the debug signing configuration.
- Debug and verification tasks remain usable without `key.properties`.
- The failure explains how to proceed without exposing secret values.

## Verification

```bash
fvm flutter test --no-pub test/tool/android_release_signing_test.dart
SERIOUS_PYTHON_SITE_PACKAGES="$PWD/build/serious_python_site" \
  android/gradlew -p android :app:tasks --quiet
SERIOUS_PYTHON_SITE_PACKAGES="$PWD/build/serious_python_site" \
  android/gradlew -p android :app:assembleRelease --dry-run
tool/codex_verify.sh --no-codegen --test test/tool/android_release_signing_test.dart
```

The release dry run is expected to fail with `Release signing is not
configured`; the other commands must succeed.

## Handoff Notes

- Summary: Android release artifact tasks now require complete, existing release
  signing material and never fall back to debug signing.
- Tests run: focused regression, non-release Gradle configuration, expected
  release dry-run rejection for every missing-material class, a successful
  release dry-run with temporary complete material, and the repository
  verification gate.
- Risks or follow-ups: release automation must provide its existing
  `android/key.properties` and keystore before invoking release tasks. Continue
  SA-16 with immutable GitHub Action pins as the next bounded slice.
