# macOS Sparkle CloudFront Migration

## Task

- Goal: Serve Caverno macOS Sparkle updates through CloudFront instead of
  direct S3 URLs.
- User-visible behavior: New macOS release builds check for updates and
  download update content from the CloudFront distribution.
- Non-goals: Add a custom domain, change Sparkle signing keys, or remove the
  legacy S3 feed before installed clients have migrated.

## Context

- Affected files or components: Sparkle release configuration, release
  publishing helpers, AWS provisioning helper, public verification, and the
  macOS update runbook.
- Related docs: `docs/macos_sparkle_s3_updates.md`.
- Reference implementation or pattern: Existing S3 publish helpers and the
  feedback endpoint AWS deployment helper.
- Known quirks, compatibility rules, or release gates: Existing builds retain
  their compiled S3 `SUFeedURL`, so direct S3 reads must remain available for a
  migration window.

## Implementation Notes

- Preferred approach: Use a CloudFront origin access control, an origin-cache
  policy with a zero minimum TTL, and an S3 bucket policy scoped to the
  distribution ARN.
- Constraints: Keep update uploads private to the release operator. Continue
  generating unique artifact names. Preserve `no-cache,max-age=0` for the
  appcast and `max-age=300,public` for artifacts.
- Generated files needed: None.
- Migration or data compatibility concerns: Publish one or more appcasts with
  CloudFront enclosure and release-note URLs before retiring the legacy public
  S3 read statement.

## Similar-Pattern Search

- Search terms: `caverno-macos-releases`, `SPARKLE_FEED_URL`,
  `CAVERNO_SPARKLE_DOWNLOAD_URL_PREFIX`, `appcast.xml`.
- Files or modules inspected: macOS Runner configuration, release drivers,
  publish/preflight/verification helpers, release docs, and static script tests.
- Follow-up tasks found: A custom Route 53 domain and ACM certificate can be
  added separately if a branded update hostname is needed.

## Acceptance Criteria

- Required behavior: CloudFront serves the existing appcast, artifacts, and
  release notes over HTTPS; release defaults generate CloudFront URLs; release
  builds compile the CloudFront appcast URL.
- Edge cases: Re-running provisioning reuses named CloudFront resources.
- Failure paths: Provisioning remains dry-run by default, validates the exact
  S3 bucket and prefix, and requires an explicit flag before removing legacy
  direct S3 access.
- Accessibility, localization, or platform expectations: No UI strings or
  accessibility behavior change.

## Verification

```bash
tool/codex_verify.sh --test test/tool/run_macos_computer_use_smoke_test_test.dart
bash tool/configure_macos_sparkle_cloudfront.sh
bash tool/run_macos_sparkle_s3_preflight.sh
bash tool/verify_macos_sparkle_public_release.sh
```

## Handoff Notes

- Summary: Record the CloudFront distribution ID/domain and the legacy S3
  retirement decision.
- Tests run: Focused static/script tests and live CloudFront HTTP checks.
- Coverage or low-coverage notes: AWS mutation paths are validated through
  dry-run output plus live resource inspection.
- Risks or follow-ups: Retire direct S3 access only after adoption evidence
  shows old S3-feed builds no longer need the migration bridge.
