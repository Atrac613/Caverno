# SEC4.6g Android Backup Exclusions

Status: completed on 2026-08-23.

## Task

- Goal: keep Caverno settings, logs, attachments, conversations, and other
  app-private state out of Android cloud backup and device transfer.
- User-visible behavior: reinstalling or moving to another Android device does
  not restore Caverno's local application data automatically.
- Non-goals: an application-managed encrypted backup, Google Drive integration,
  selective restoration, or changes to platform secure storage.

## Context

- Affected components: Android manifest, legacy full-backup rules, modern data
  extraction rules, and configuration regression tests.
- Related finding: SA-17 in `docs/security_audit_2026-08-14.md`.
- Reference behavior: Android Auto Backup includes almost all app-private data
  by default, and some Android 12+ device manufacturers can perform
  device-to-device transfer even when `allowBackup` is false.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Set `android:allowBackup="false"` as the primary application-wide policy.
- Reference `fullBackupContent` rules for Android 11 and lower.
- Reference `dataExtractionRules` with separate cloud and device-transfer
  sections for Android 12 and higher.
- Exclude root files, application files, databases, shared preferences,
  external app files, and all device-protected equivalents in both formats.
- Use all-domain exclusion rather than enumerating current filenames so future
  sensitive stores remain protected by default.
- No generated source files or new dependencies are required.

## Similar-Pattern Search

- Search terms: `allowBackup`, `fullBackupContent`, `dataExtractionRules`,
  `getApplicationSupportDirectory`, `SharedPreferences`, `session_logs`,
  `approval_audit`, and `attachments`.
- Files inspected: Android manifest/resources, drift and Hive locations,
  settings persistence, attachment storage, and local log stores.
- Follow-up tasks found: SA-18 privacy declarations, debug-log redaction, and
  attachment deletion is the next SEC4.6 lifecycle slice.

## Acceptance Criteria

- The manifest explicitly disables backup.
- The manifest references both legacy and modern rule resources.
- Legacy rules exclude every app-private storage domain.
- Modern rules exclude the same domains from cloud backup and device transfer.
- No include rule can accidentally re-enable a subset.
- Android resource compilation and manifest merging succeed in a debug APK.

## Verification

```bash
fvm flutter test --no-pub test/core/security/android_backup_boundary_test.dart
fvm flutter analyze --no-pub
SERIOUS_PYTHON_SITE_PACKAGES="$(pwd)/build/serious_python_site" \
  fvm flutter build apk --debug --no-pub
tool/codex_verify.sh --no-codegen --test \
  test/core/security/android_backup_boundary_test.dart
```

## Handoff Notes

- Summary: Android backup is disabled and both platform rule formats deny all
  cloud and device-transfer access to Caverno app-private data.
- Tests run: configuration regressions, static analysis, debug APK build, and
  the repository verification gate.
- Risks or follow-ups: users now need the explicit encrypted settings export
  for portable settings. SA-18 should complete the remaining privacy and local
  deletion lifecycle review.
