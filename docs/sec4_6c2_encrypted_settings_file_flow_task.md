# SEC4.6c2 Encrypted Settings File Flow

Status: completed on 2026-08-23.

## Task

- Goal: expose an explicit encrypted settings backup that can include secrets,
  and restore it through the same quarantine boundary as normal imports.
- User-visible behavior: the settings menu offers a clearly warned encrypted
  backup action with passphrase confirmation. Selecting an encrypted settings
  file requests its passphrase before import.
- Non-goals: secret-bearing QR exports, passphrase recovery, cloud backup, or
  changing the default secret-free export.

## Context

- Affected components: settings file service, settings notifier, settings
  actions menu, onboarding import, localization, and focused tests.
- Related finding: SA-11 in `docs/security_audit_2026-08-14.md`.
- Reference implementation: the SEC4.6c1 versioned AES-256-GCM envelope.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Keep the existing Export Settings and QR paths secret-free.
- Add a separate encrypted action whose warning names the credential classes
  included in the file and requires matching passphrase entries.
- Run PBKDF2 and AES-GCM through Flutter `compute` so native UI isolates remain
  responsive during the measured multi-second KDF operation.
- Detect the versioned envelope after file selection and request a passphrase
  only for encrypted imports.
- Bound selected and decoded input before settings parsing.
- Feed decrypted settings through normal validation and
  `ExecutableSettingsQuarantineService` before persistence.
- Keep encrypted QR out of scope because it adds visual and capture exposure.
- No generated files or new dependencies are required.
- Rollback unit: data flow, notifier integration, UI, localization, tests, and
  this task document.

## Similar-Pattern Search

- Search terms: `importSettings`, `exportSettings`, `SettingsActionsMenu`,
  `OnboardingPage`, `SettingsExportSanitizer`, and `quarantineImportedSettings`.
- Files inspected: file and QR settings services, notifier import paths,
  settings actions, onboarding, translation assets, and import-quarantine
  tests.
- Follow-up tasks found: SA-13 nested audit redaction and filesystem modes are
  the next uncompleted SEC4.6 data-protection slice.

## Acceptance Criteria

- Default file and QR exports remain secret-free.
- Secret-bearing exports require an explicit separate action, warning, minimum
  passphrase, and matching confirmation.
- The encrypted file contains no plaintext credential values and restores them
  only with the correct passphrase.
- KDF work does not execute on the native UI isolate.
- Encrypted import is available from settings and onboarding.
- Decrypted executable settings are quarantined before persistence.
- Cancellation, malformed input, wrong passphrases, oversized input, and
  authentication failures do not update settings.

## Verification

```bash
fvm flutter test --no-pub \
  test/features/settings/data/encrypted_settings_export_codec_test.dart \
  test/features/settings/data/settings_file_service_test.dart \
  test/features/settings/data/settings_qr_service_test.dart \
  test/features/settings/presentation/providers/settings_notifier_import_quarantine_test.dart \
  test/features/settings/presentation/widgets/settings_actions_menu_test.dart \
  test/features/onboarding/presentation/pages/onboarding_page_test.dart
fvm flutter analyze --no-pub
```

## Handoff Notes

- Summary: encrypted settings backup and restore are now explicit file-only
  flows, with responsive KDF execution and quarantine-preserving import.
- Tests run: the repository-standard focused gate passed with 46 Flutter tests,
  all workspace package analysis/tests, 10 notification relay tests, and no
  Flutter analysis issues.
- Risks or follow-ups: Flutter web implements `compute` without a background
  isolate, so the web build can remain busy during PBKDF2. Native mobile and
  desktop surfaces use the intended isolate boundary.
