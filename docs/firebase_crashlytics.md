# Firebase Crashlytics

Caverno reports uncaught Flutter and native crashes to Firebase Crashlytics on
iOS, Android, and macOS. The same environment-owned app files already used for
Remote Coding FCM also gate Crashlytics. Checkouts without those files, the
CLI frontend, and Flutter tests never initialize Crashlytics.

## Requirements

- `ios/Runner/GoogleService-Info.plist`
- `android/app/google-services.json`
- `macos/Runner/GoogleService-Info.plist`

All three files are gitignored. Obtain them with
`tool/bootstrap_remote_coding_firebase.dart` as described in
`docs/remote_coding_fcm_release_gate.md`. Enable the Crashlytics product on
that Firebase project if it is not already on.

iOS and macOS share bundle ID `com.noguwo.apps.caverno`. Firebase cannot
register two Apple apps with that bundle ID, so macOS reuses the iOS Apple
app. Bootstrap copies the iOS plist onto `macos/Runner/GoogleService-Info.plist`.
The macOS Runner target prefers that copy and otherwise falls back to
`ios/Runner/GoogleService-Info.plist`, then fail-closes if neither file exists.

## Collection policy

- Profile and release collect crashes after Firebase initializes.
- Debug disables collection. Native Android debug builds also set
  `firebase_crashlytics_collection_enabled` to false.
- Force debug collection with `--dart-define=CAVERNO_CRASHLYTICS_DEBUG=true`.
- Analytics stays disabled. Crashlytics does not turn on Google Analytics.

Reports include stack traces, device and app metadata, and build provenance
keys (`build_commit`, `build_dirty`). They must not include prompts, API
keys, or other session content. Do not add Crashlytics log breadcrumbs that
copy chat or tool payloads.

## Verification

1. Build a configured iOS, Android, or macOS app.
2. Temporarily run with `CAVERNO_CRASHLYTICS_DEBUG=true` or use a profile
   build, then throw an uncaught exception.
3. Confirm the crash appears in the Firebase Crashlytics dashboard. macOS
   reports land on the same Apple app as iOS.

iOS and macOS release/profile builds upload dSYMs from each Runner target's
`Upload Crashlytics dSYMs` phase when the plist is in the bundle. Debug
builds skip that upload. Android mapping-file upload is handled by the
Crashlytics Gradle plugin when `google-services.json` is present.
