# Remote Coding FCM Release Gate

This gate prevents Remote Coding completion notifications from being treated as
release-ready until repository configuration, Firebase deployment, signed
physical-device delivery, and lock-screen privacy evidence are complete.

## Repository-owned configuration

The repository enables the iOS Push Notifications and Background Modes
capabilities, declares `fetch` and `remote-notification`, requests the APNs
entitlement, pins the CocoaPods deployment target to iOS 15 for Firebase Apple
SDK 12, and wires the Android Google Services plugin when
`google-services.json` is present. FCM token auto-initialization is disabled on
both platforms. The app enables it only after an explicit user action and
deletes the token after relay revocation.

Android creates `remote_coding_completion` before registering its FCM token and
declares the same ID as the default FCM notification channel. This keeps
background and terminated notifications on the user-visible channel selected
when completion notifications were enabled.

The environment owner must provide matching Firebase app configuration files:

- `ios/Runner/GoogleService-Info.plist`
- `android/app/google-services.json`

Both applications use bundle/package ID `com.noguwo.apps.caverno`. Firebase
configuration files identify the project but must never contain APNs private
keys or service-account private keys. Both files are gitignored, so every
checkout must obtain them from the environment owner.

Because the files are environment-owned, neither platform may treat them as a
required build input. Android applies the Google Services plugin only when
`android/app/google-services.json` exists. iOS mirrors that with the Runner
target's `Copy Firebase Configuration` build phase, which copies the plist into
the app bundle when it is present and otherwise emits a warning and leaves push
notifications disabled. A plain Xcode resource reference must not be used: the
Apple Firebase SDK reads `GoogleService-Info.plist` from the bundle, and a
missing required resource would break every build made without Firebase
configuration.

## Desktop keychain capability

The desktop stores its relay delivery credential through
`flutter_secure_storage`, so both macOS entitlements files declare
`keychain-access-groups`. The entitlement alone is only a request: the
provisioning profile must carry the matching Keychain Sharing capability, or
signing fails with `Provisioning profile ... doesn't include signing
certificate`. Add the capability once in Xcode under Runner ->
Signing & Capabilities -> Keychain Sharing; automatic signing then updates the
App ID and regenerates the profile.

Without the entitlement the build still succeeds and the keychain rejects every
write at runtime with `errSecMissingEntitlement` (-34018), which also breaks the
SSH credentials manager. Treat a macOS signing failure here as the capability
being absent from the profile, not as a reason to drop the entitlement.

## Bootstrap the Firebase mobile apps

Create or select a dedicated Firebase project first. Project creation is kept
outside the repository tool because its ID, organization, billing account, and
data location are environment-owner decisions. Inspect the selected project
without changing it:

```bash
fvm dart run tool/bootstrap_remote_coding_firebase.dart \
  --project <firebase-project-id>
```

After confirming the project, register only missing Caverno apps and download
their SDK configuration:

```bash
fvm dart run tool/bootstrap_remote_coding_firebase.dart \
  --project <firebase-project-id> \
  --apply
```

The command is namespace-scoped and fails closed if duplicate iOS or Android
apps use `com.noguwo.apps.caverno`. It does not select an active Firebase
project globally and does not create, upload, or print private credentials.

Inspect live deployment prerequisites and deployed relay identity at any time:

```bash
fvm dart run tool/remote_coding_firebase_status.dart \
  --project <firebase-project-id>
```

The JSON result distinguishes `blocked`, `ready_to_deploy`, and `deployed`.
It verifies both relay functions by codebase, region, runtime, and active state.

## Generate the evidence checklist

```bash
dart run tool/remote_coding_fcm_release_gate.dart \
  --write-template build/remote_coding_fcm_manual_checklist.json
```

Keep every field `false` until its supporting console record, signed-build log,
device video or screenshot, or relay health result exists.

## Run the gate

```bash
dart run tool/remote_coding_fcm_release_gate.dart \
  --manual-checklist build/remote_coding_fcm_manual_checklist.json \
  --out-json build/remote_coding_fcm_release_gate.json \
  --out-md build/remote_coding_fcm_release_gate.md
```

The command exits non-zero while any gate is blocked. The generated artifacts
contain no FCM registration tokens, APNs keys, App Check tokens, relay secrets,
or notification payload identifiers.

## Firebase deployment evidence

Record evidence only after all of the following are true:

1. The Firebase project and both mobile apps are registered.
2. Create the default Firestore database in an explicitly selected region.
3. FCM HTTP v1, App Check enforcement, and the APNs authentication
   key are configured.
4. The notification relay Functions, Firestore rules and indexes, and Hosting
   rewrite are deployed.
5. Firestore TTL is enabled for replay documents and the deployed `/health`
   endpoint succeeds.
6. The release build uses the deployed HTTPS origin through
   `CAVERNO_NOTIFICATION_RELAY_URL`.

## Physical-device matrix

Use signed iOS and Android builds. Complete one remote-origin coding run for
each foreground, background, locked, and terminated state. Verify notification
tap routing, FCM token rotation, permission denial, registration revocation,
and relay outage isolation. Notification title and body must remain generic on
the lock screen.

On iOS, also inspect the signed archive entitlements and verify the distribution
profile supplies the production APNs environment. On Android, inspect the
release resources and confirm they came from the intended Firebase project.
