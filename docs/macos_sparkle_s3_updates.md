# macOS Sparkle S3 Updates

This runbook describes the direct-distribution update lane for Caverno macOS
builds. Sparkle owns update discovery, signature validation, download, install
handoff, and user-facing update prompts. S3 only hosts static update files.

## App Configuration

Sparkle is integrated through the macOS Runner target and exposed to Flutter
with the `com.caverno/sparkle_updates` method channel.

Release builders must provide these local values in the ignored
`macos/Runner/Configs/Signing.local.xcconfig` file:

```xcconfig
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_IDENTITY = Developer ID Application
SPARKLE_FEED_URL = https:/$()/caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos/appcast.xml
SPARKLE_PUBLIC_ED_KEY = BASE64_PUBLIC_ED25519_KEY_FROM_SPARKLE
```

The `https:/$()/` form is intentional in `.xcconfig` files. It expands to
`https://` while avoiding `//` comment parsing.

Repository defaults keep `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` blank
so debug builds do not contact the production appcast.

Sparkle defaults for Caverno:

- Automatic checks are enabled.
- Automatic downloads and silent installs are disabled.
- Scheduled checks run every 3600 seconds.
- Update archives are verified before extraction.

## First-Time Key Setup

Install or fetch Sparkle, then run its key generator once:

```bash
generate_keys
```

Store the private EdDSA key securely. Put the printed public key in
`SPARKLE_PUBLIC_ED_KEY`. The private key must stay out of the repository and
out of the S3 hosting location.

## Release Artifact Requirements

Before publishing an update, build a release artifact that is:

- Built from an incremented `pubspec.yaml` build number.
- Signed with a Developer ID Application identity.
- Notarized by Apple.
- Stapled.
- Packaged as a Sparkle-supported archive, preferably `.dmg` or `.zip`.

Run the existing static release packaging report before publishing:

```bash
bash tool/run_macos_computer_use_release_packaging.sh
```

## Build, Notarize, Package, and Publish

Create a notarytool keychain profile on the release Mac before the first real
release:

```bash
xcrun notarytool store-credentials caverno-notary \
  --apple-id APPLE_ID@example.com \
  --team-id YOURTEAMID \
  --password APP_SPECIFIC_PASSWORD
```

Prepare the S3 bucket before the first real publish. A minimal direct-S3
hosting policy for this lane is:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadCavernoMacosUpdates",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::caverno-macos-releases/caverno/macos/*"
    }
  ]
}
```

Keep write access limited to the release operator or release automation role.
Review the direct-S3 public read update before applying it:

```bash
bash tool/configure_macos_sparkle_s3_public_read.sh
```

Apply it only after confirming the bucket and prefix:

```bash
bash tool/configure_macos_sparkle_s3_public_read.sh --apply
```

Run the S3 preflight before the first upload:

```bash
bash tool/run_macos_sparkle_s3_preflight.sh
```

Use `--dry-run` to inspect the AWS commands without contacting S3.

Then run the Sparkle release driver:

```bash
bash tool/build_macos_sparkle_release.sh \
  --notary-profile caverno-notary \
  --package zip \
  --download-url-prefix https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos \
  --s3-uri s3://caverno-macos-releases/caverno/macos \
  --release-notes docs/releases/caverno-1.3.2.md
```

The driver runs release signing preflight, the static packaging report,
`fvm flutter build macos --release`, deep codesign verification, notarytool
submission, stapler validation, Sparkle packaging, and the S3 appcast publish
helper. Use `--dry-run` to inspect commands without running them.

For a local packaging rehearsal without Apple notarization or S3 upload:

```bash
bash tool/build_macos_sparkle_release.sh \
  --skip-notarization \
  --skip-publish \
  --dry-run
```

For a staging publish rehearsal that exercises the publish path without
uploading to S3, use the dummy staging wrapper:

```bash
bash tool/run_macos_sparkle_staging_rehearsal.sh
```

The wrapper defaults to
`https://updates.example.invalid/caverno/macos/staging` and
`s3://caverno-macos-releases/caverno/macos/staging`, keeps notarization disabled, and
passes `--dry-run` to the release driver. A real run is blocked until the
download URL is overridden.

## S3 Publish

Use the lower-level publish helper when the artifact is already signed,
notarized, and stapled:

```bash
bash tool/publish_macos_sparkle_release.sh \
  --artifact build/release/Caverno-1.3.2.dmg \
  --release-notes docs/releases/caverno-1.3.2.md \
  --download-url-prefix https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos \
  --s3-uri s3://caverno-macos-releases/caverno/macos
```

Useful environment overrides:

- `SPARKLE_GENERATE_APPCAST`: explicit `generate_appcast` path.
- `SPARKLE_ED_KEY_FILE`: private EdDSA key file for `generate_appcast`.
- `SPARKLE_CHANNEL`: optional Sparkle channel.
- `SPARKLE_MAXIMUM_DELTAS`: delta count, default `0`.
- `CAVERNO_SPARKLE_UPDATES_DIR`: local updates directory.
- `CAVERNO_SPARKLE_DOWNLOAD_URL_PREFIX`: default download URL prefix.
- `CAVERNO_SPARKLE_S3_URI`: default S3 destination.
- `CAVERNO_SPARKLE_PUBLIC_VERIFY_SCRIPT`: public post-publish verifier path.
- `CAVERNO_SPARKLE_EXPECTED_VERSION`: expected public appcast short version.
- `CAVERNO_SPARKLE_EXPECTED_BUILD`: expected public appcast build number.
- `CAVERNO_SPARKLE_STAGING_DOWNLOAD_URL_PREFIX`: staging wrapper download URL.
- `CAVERNO_SPARKLE_STAGING_S3_URI`: staging wrapper S3 destination.
- `CAVERNO_SPARKLE_STAGING_RELEASE_NOTES_PATH`: staging wrapper notes file.

The script uploads the updates directory first and then overwrites the appcast
with `no-cache,max-age=0`, so clients do not see a new appcast before the
artifact is available. It then runs the public verifier against the hosted
appcast and artifact unless `--skip-public-verify` is provided.

To repeat the public verification manually, check the appcast, linked artifact,
release notes, Sparkle signature field, and S3 cache headers:

```bash
bash tool/verify_macos_sparkle_public_release.sh \
  --expected-version 1.3.2 \
  --expected-build 13 \
  --expected-artifact-url https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos/Caverno-1.3.2-13.zip \
  --expected-min-length 30000000
```

Before removing `--dry-run` from the release driver, run:

```bash
bash tool/run_macos_sparkle_s3_preflight.sh
bash tool/build_macos_sparkle_release.sh \
  --notary-profile caverno-notary \
  --package zip \
  --download-url-prefix https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos \
  --s3-uri s3://caverno-macos-releases/caverno/macos \
  --release-notes docs/releases/caverno-1.3.2.md \
  --dry-run
```

## App-Side Verification

Open Caverno and use:

```text
Settings > Advanced > Debug > macOS Updates
```

The row shows whether Sparkle is configured for the current build. The manual
check button calls Sparkle's standard update UI. Scheduled launch and hourly
checks are handled by Sparkle, not by a Dart timer.

## Rollback

To stop rollout, replace the hosted `appcast.xml` with the previous known-good
appcast or remove the newest item from the appcast and upload it with no-cache
headers. Leave old artifacts available until clients have moved past the bad
feed.
