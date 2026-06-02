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
SPARKLE_FEED_URL = https://updates.example.com/caverno/macos/appcast.xml
SPARKLE_PUBLIC_ED_KEY = BASE64_PUBLIC_ED25519_KEY_FROM_SPARKLE
```

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

## S3 Publish

Use the publish helper after the artifact is signed, notarized, and stapled:

```bash
bash tool/publish_macos_sparkle_release.sh \
  --artifact build/release/Caverno-1.3.2.dmg \
  --release-notes docs/releases/caverno-1.3.2.md \
  --download-url-prefix https://updates.example.com/caverno/macos \
  --s3-uri s3://example-bucket/caverno/macos
```

Useful environment overrides:

- `SPARKLE_GENERATE_APPCAST`: explicit `generate_appcast` path.
- `SPARKLE_ED_KEY_FILE`: private EdDSA key file for `generate_appcast`.
- `SPARKLE_CHANNEL`: optional Sparkle channel.
- `SPARKLE_MAXIMUM_DELTAS`: delta count, default `0`.
- `CAVERNO_SPARKLE_UPDATES_DIR`: local updates directory.
- `CAVERNO_SPARKLE_DOWNLOAD_URL_PREFIX`: default download URL prefix.
- `CAVERNO_SPARKLE_S3_URI`: default S3 destination.

The script uploads the updates directory first and then overwrites the appcast
with `no-cache,max-age=0`, so clients do not see a new appcast before the
artifact is available.

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
