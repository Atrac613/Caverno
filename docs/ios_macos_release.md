# iOS and macOS Release Workflow

Use `tool/release_ios_macos.sh` as the normal entrypoint for Caverno iOS and
macOS production releases. The script reads the current `pubspec.yaml` version
by default and delegates platform-specific work to the existing Flutter, Xcode,
Sparkle, notarization, and S3 release tools.

## Safety Boundary

Running the script without `--dry-run` is a production action:

- The iOS lane uploads the build to App Store Connect by default.
- The macOS lane notarizes the app, publishes the Sparkle archive to S3, and
  updates the public appcast.
- The script does not submit the iOS build for App Review.
- The script does not change `pubspec.yaml`, create commits, push, or tag.

Run a dry run first whenever changing arguments or release destinations.

```bash
bash tool/release_ios_macos.sh --dry-run \
  --macos-release-notes docs/releases/caverno-1.3.3.md
```

## Normal Release

Prepare the release notes first, then run the combined release:

```bash
bash tool/release_ios_macos.sh \
  --macos-release-notes docs/releases/caverno-1.3.3.md
```

The script uses:

- `fvm flutter pub get`
- `fvm flutter build ipa --release` with a generated App Store Connect
  `ExportOptions.plist`
- `tool/build_macos_sparkle_release.sh` for Developer ID signing verification,
  Apple notarization, stapling, Sparkle packaging, S3 upload, and public appcast
  verification

## Platform-Specific Runs

Upload only the iOS build to App Store Connect:

```bash
bash tool/release_ios_macos.sh --only ios
```

Publish only the macOS Sparkle S3 release:

```bash
bash tool/release_ios_macos.sh --only macos \
  --macos-release-notes docs/releases/caverno-1.3.3.md
```

Export the iOS IPA locally instead of uploading it:

```bash
bash tool/release_ios_macos.sh --only ios --ios-destination export
```

## Version Overrides

The default build name and build number come from `pubspec.yaml`, for example
`version: 1.3.3+14`. Override them only when intentionally building a different
artifact from the checked-in version:

```bash
bash tool/release_ios_macos.sh \
  --build-name 1.3.3 \
  --build-number 14 \
  --macos-release-notes docs/releases/caverno-1.3.3.md
```

Environment equivalents are also supported:

```bash
CAVERNO_RELEASE_BUILD_NAME=1.3.3 \
CAVERNO_RELEASE_BUILD_NUMBER=14 \
bash tool/release_ios_macos.sh \
  --macos-release-notes docs/releases/caverno-1.3.3.md
```

## iOS Options

Defaults:

- Scheme: `Runner`
- Bundle ID: `com.noguwo.apps.caverno`
- Team ID: `89UG59TBNX`
- Export destination: `upload`
- Export root: `/private/tmp/caverno-ios-appstore-VERSION-BUILD`

Useful overrides:

```bash
bash tool/release_ios_macos.sh --only ios \
  --ios-destination upload \
  --ios-team-id 89UG59TBNX \
  --ios-bundle-id com.noguwo.apps.caverno \
  --ios-export-root /private/tmp/caverno-ios-appstore-1.3.3-14
```

The script generates an automatic-signing App Store Connect
`ExportOptions.plist` with `manageAppVersionAndBuildNumber` set to `false` so
Xcode does not rewrite the build number during upload.

## macOS Options

Defaults:

- Notary profile: `caverno-notary`
- Package: `zip`
- Download URL prefix:
  `https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos`
- S3 URI: `s3://caverno-macos-releases/caverno/macos`
- Release notes: `docs/releases/caverno-VERSION.md` when that file exists

Useful overrides:

```bash
bash tool/release_ios_macos.sh --only macos \
  --macos-notary-profile caverno-notary \
  --macos-package zip \
  --macos-download-url-prefix https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos \
  --macos-s3-uri s3://caverno-macos-releases/caverno/macos \
  --macos-release-notes docs/releases/caverno-1.3.3.md
```

For lower-level Sparkle, S3, or rollback details, see
`docs/macos_sparkle_s3_updates.md`.

## Verification

Before committing release workflow changes, run:

```bash
bash -n tool/release_ios_macos.sh
bash tool/release_ios_macos.sh --dry-run \
  --macos-release-notes docs/releases/caverno-1.3.3.md
bash tool/release_ios_macos.sh --dry-run --only ios --ios-destination export
bash tool/release_ios_macos.sh --dry-run --only macos \
  --macos-release-notes docs/releases/caverno-1.3.3.md
```

After a real macOS publish, the lower-level Sparkle driver verifies the public
appcast and artifact URLs. After a real iOS upload, wait for App Store Connect
processing before using the build in TestFlight or App Review.
