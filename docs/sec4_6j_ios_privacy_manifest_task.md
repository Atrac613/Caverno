# SEC4.6j iOS Privacy Manifest Reconciliation

Status: completed on 2026-08-23.

## Task

- Goal: make Caverno's iOS privacy declaration match its implemented
  developer-owned off-device collection.
- User-visible behavior: the bundled privacy report accurately discloses
  feedback and notification-relay data without claiming tracking.
- Non-goals: changing endpoint payloads or retention, editing external App Store
  Connect metadata, or duplicating third-party SDK manifests.

## Context

- Affected components: iOS privacy manifest, disclosure documentation,
  configuration regression, security audit, and roadmap.
- Related finding: SA-18 in `docs/security_audit_2026-08-14.md`.
- Reference behavior: Apple's collection definition, privacy manifest schema,
  collected-data categories, purposes, linking, and tracking rules.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Declare feedback text and session-log content, performance, and diagnostics
  as unlinked, non-tracking data used for analytics and applicable app support.
- Declare notification relay installation and terminal-event data as linked,
  non-tracking data used only for app functionality.
- Keep user-directed provider traffic outside the Caverno-owned collection
  boundary unless a distributor changes a default to its own service.
- Preserve the existing required-reason API declarations.
- Document the matching App Store Connect answers and release verification.
- No generated source files, migrations, or new dependencies are required.

## Similar-Pattern Search

- Search terms: `PrivacyInfo`, `NSPrivacy`, `feedbackEndpointUrl`,
  `FeedbackSubmissionService`, `CAVERNO_NOTIFICATION_RELAY_URL`,
  `installationId`, `fcmRegistrationToken`, `RemoteCodingNotificationPayload`,
  Firebase manifests, tracking, analytics, and privacy policy.
- Files inspected: iOS manifest and project integration, feedback defaults and
  payload, LLM session-log schema, notification registration and durable relay
  store, generic notification payload, Info.plist permissions, and dependencies.
- Follow-up tasks found: SEC4.7/SA-16 release supply-chain hardening is the next
  unresolved security slice.

## Acceptance Criteria

- The app manifest declares all six Caverno-owned collection categories.
- Feedback categories are unlinked and non-tracking.
- Notification relay categories are linked, non-tracking, and limited to app
  functionality.
- Global tracking stays disabled with no tracking domains.
- UserDefaults and file-timestamp required-reason entries remain present.
- The App Store Connect mapping and release review steps are documented.

## Verification

```bash
plutil -lint ios/Runner/PrivacyInfo.xcprivacy
fvm flutter test --no-pub test/tool/ios_privacy_manifest_test.dart
fvm flutter analyze --no-pub
tool/codex_verify.sh --no-codegen --test test/tool/ios_privacy_manifest_test.dart
fvm flutter build ios --debug --no-codesign --no-pub
plutil -lint build/ios/iphoneos/Runner.app/PrivacyInfo.xcprivacy
cmp ios/Runner/PrivacyInfo.xcprivacy \
  build/ios/iphoneos/Runner.app/PrivacyInfo.xcprivacy
```

## Handoff Notes

- Summary: iOS now declares feedback and notification-relay collection using
  Apple's canonical categories, purposes, linkage, and tracking fields.
- Tests run: plist lint, manifest regression, static analysis, the repository
  verification gate, and a no-codesign iOS build with an exact bundled-manifest
  comparison.
- Risks or follow-ups: App Store Connect is external state and must be updated
  to match the documented matrix before the next submission. Continue security
  work with the first bounded SEC4.7/SA-16 supply-chain slice.
