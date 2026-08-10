# Remote Coding FCM Notification Tasks

Status: All repository-owned FCM1-FCM7 work completed on 2026-08-10. Firebase
app configuration, relay deployment, Apple App Attest registration, the APNs
authentication key, and the App Check token-verifier grant were completed on
the environment owner's project on 2026-08-10. Firestore replay TTL, the
release relay origin, release signing inspection, and physical device evidence
remain pending. Android is deferred, so evidence is being collected on iOS
first.

App Attest cannot attest a development-signed build: Apple issues the
attestation in its development environment and `exchangeAppAttestAttestation`
answers 403 `App attestation failed`. Development device runs therefore need
`--dart-define=CAVERNO_FIREBASE_APP_CHECK_DEBUG=true` and a debug token
registered for the Apple app. Production App Attest can only be proven with a
distribution-signed build.

## Goal

Deliver one user-visible notification when a remote-origin coding turn reaches
a terminal state, including when the mobile Caverno process is suspended or
terminated. Use Firebase Cloud Messaging (FCM) for Android and for iOS through
APNs.

## Architecture Boundary

The existing execution runtime is the source of truth for `run_completed` and
`run_failed`. Remote Coding must not infer completion from `ChatState.isLoading`
or message-list changes. A privacy-safe terminal event is sent through two
delivery paths:

1. WebSocket delivery while the mobile client is connected.
2. An authenticated HTTPS relay that submits an FCM notification message.

The relay payload must never contain prompts, model output, tool arguments,
tool results, file contents, command output, pairing secrets, or device
authentication tokens. Notification title and body remain generic by default.

## Task Order

### FCM1: Freeze the notification payload contract

- Goal: Define the allowlisted payload shared by WebSocket delivery, the relay,
  and FCM data.
- Affected components:
  - `lib/features/remote_coding/data/remote_coding_notification_payload.dart`
  - `test/features/remote_coding/data/remote_coding_notification_payload_test.dart`
- Preferred approach: Use a versioned data-only contract with opaque event,
  turn, and conversation IDs; a completed/failed outcome; generic title/body;
  and a UTC completion timestamp.
- Non-goals: Firebase SDK integration, relay transport, OS notification display,
  persistence, and deep links.
- Acceptance criteria:
  - Serialization emits only the documented allowlist.
  - Parsing rejects missing identifiers, unsupported versions, invalid outcomes,
    and invalid timestamps.
  - No model or tool content field exists in the contract.
- Verification:

```bash
tool/codex_verify.sh --test test/features/remote_coding/data/remote_coding_notification_payload_test.dart
```

### FCM2: Publish remote-origin runtime terminal events

Status: Completed on 2026-08-10.

- Goal: Route the existing `CavernoRuntimeRunCompleted` and
  `CavernoRuntimeRunFailed` events to Remote Coding with the exact turn owner
  and interaction origin.
- Affected components: execution runtime composition, `ChatNotifier` runtime
  adapter, and `RemoteCodingServerNotifier`.
- Preferred approach: Extend the runtime lifecycle boundary with an explicit
  interaction source. Do not add another `isLoading` transition detector.
- Acceptance criteria:
  - Only remote-origin turns produce Remote Coding terminal notifications.
  - Queued and concurrent turns preserve their exact conversation and turn IDs.
  - Success, failure, cancellation, and replaced-turn paths emit at most once.
- Verification: focused execution-runtime, detached-turn, and Remote Coding
  server tests.

Implementation notes:

- The execution runtime now carries `local` or `remote_coding` interaction
  origin on every event while preserving the existing local wire shape.
- `ChatNotifier` maps direct, queued, cancellation, and detached turns to the
  exact runtime owner and origin.
- `RemoteCodingServerNotifier` listens to the canonical terminal stream and
  broadcasts a `runTerminal` event only for authenticated clients and
  remote-origin turns.
- Terminal events are converted to the FCM1 allowlist before broadcast. Model
  output and failure details are not included.
- `RemoteCodingClientNotifier` parses the same contract and exposes one
  consumable terminal event for the later notification UX task.

### FCM3: Add the authenticated notification relay contract

Status: In progress. FCM3a through the local FCM3c relay implementation
completed on 2026-08-10; environment deployment is pending.

- Goal: Define registration and delivery APIs without placing FCM service
  credentials in the desktop or mobile application.
- Affected components: Remote Coding pairing metadata, secure mobile storage,
  desktop paired-device persistence, and a deployable relay.
- Preferred approach: Store an opaque relay delivery handle on desktop. Keep
  FCM registration tokens and provider credentials only in the relay.
- Acceptance criteria:
  - Registration, rotation, revocation, and delivery are authenticated.
  - Relay logs redact tokens and payload identifiers.
  - Replays are rejected by event ID and bounded timestamp checks.
- Verification: contract tests, replay tests, and redaction tests.

Implementation slices:

- FCM3a, completed: Freeze the versioned registration, rotation, revocation,
  and delivery contract. Require App Check for registration, scoped HMAC
  credentials for later operations, bounded timestamp windows, nonce and event
  replay rejection, and structured log redaction.
- FCM3b-1, completed: Separate non-secret mobile registration metadata from
  management and delivery secrets in platform secure storage. Add optional
  delivery handle, key ID, and expiry fields to desktop paired-device state,
  with backward-compatible reads and per-device secure-secret deletion.
- FCM3b-2a, completed: Replace the pre-deployment relay contract with version 2
  and freeze relay-mediated one-time delegation. Registration returns only the
  mobile management credential. A dedicated high-entropy QR challenge is stored
  by digest in a short-lived `pending -> redeemed -> active` state machine, and
  the desktop receives its scoped delivery credential only by direct HTTPS
  redemption. Retried redemption is idempotent, while mismatched devices,
  mismatched challenges, expiry, and second redemption attempts fail closed.
- FCM3b-2b-1, completed: Add a fixed-origin HTTPS relay client for registration,
  token rotation, delegation, activation, scoped revocation, and delivery. Add
  mobile and desktop provisioning coordinators. Desktop persists secure secret
  and non-secret metadata in `pendingActivation` before relay activation, and
  retains `pendingRevocation` plus the secret across relay failures. Only
  `active`, unexpired credentials are usable for notification delivery.
- FCM3b-2b-2, completed: Connect the provisioning coordinators to a dedicated QR
  challenge and the authenticated Remote Coding device lifecycle. Keep the QR
  challenge secret and delivery credential off `ws://`, retry pending lifecycle
  operations after restart, and route desktop device revocation through remote
  scoped revocation before final local credential deletion.
- FCM3c-1, completed: Implement the Cloud Functions 2nd gen Node.js 22 relay,
  Firebase Admin App Check and FCM adapters, Firestore registration and replay
  storage, atomic delegation redemption, and a durable delivery outbox. Add
  fake-provider tests and Firestore emulator concurrency tests. Expose the
  bare HTTPS origin through Firebase Hosting rewrites.
- FCM3c-2, partially completed on 2026-08-10: The environment owner's project
  was selected, both mobile apps registered, the default Firestore database
  created in `asia-northeast1`, and the relay Functions, Firestore rules and
  indexes, and the Hosting rewrite deployed. `/health` answers
  `{"ok":true,"schemaVersion":2}` through the Hosting origin, and
  `POST /v2/registrations` without an App Check token fails closed with 401.
  Apple App Attest was registered on 2026-08-10. Still pending: the APNs
  authentication key, Firestore replay TTL on `replays.expiresAt`, and a
  test-device canary. Android is deferred, so the Play Integrity linkage and
  every Android delivery scenario stay open. Provider credentials remain
  environment-owned.

  The Functions runtime identity must hold `roles/firebaseappcheck.tokenVerifier`
  explicitly. The relay consumes limited-use tokens through
  `verifyToken(token, {consume: true})`, which requires
  `firebaseappcheck.appCheckTokens.verify`. `gcloud iam roles describe
  roles/editor` lists that permission, but the basic role does not confer it in
  practice: every registration failed with `app-check/permission-denied` until
  the dedicated role was granted to the runtime service account. Read the role
  definition as documentation, not as proof of an effective grant.

  The App Check REST API cannot confirm provider registration. Every
  `appAttestConfig`, `deviceCheckConfig`, and `playIntegrityConfig` record
  exists from project creation and returns only its token TTL, so registration
  status is an environment-owner report and must be proven by a device that
  successfully registers with the relay.

  Hosting rewrites to a function are only released after the target function
  exists. A first-time deployment that creates the functions and the Hosting
  release in one command leaves Hosting unreleased if function creation fails,
  so re-run `firebase deploy --only hosting` after the functions are live.

Contract reference:

- `docs/remote_coding_notification_relay_contract.md`

### FCM4: Integrate Firebase Messaging on mobile

Status: Application integration, platform wiring, and unsigned debug-build
evidence completed on 2026-08-10. Environment-owned Firebase configuration
remains pending.

- Goal: Initialize Firebase, request notification permission in foreground,
  register and rotate the FCM token, and receive foreground/tap events.
- Affected components: app bootstrap, notification providers, Remote Coding
  repository, iOS Runner configuration, Android application configuration, and
  package dependencies.
- Constraints: Firebase project configuration files and APNs credentials are
  environment-owned inputs. Do not invent or commit provider private keys.
- Acceptance criteria:
  - Disabled or unavailable Firebase configuration fails closed without
    breaking LAN Remote Coding.
  - Token refresh updates the relay registration.
  - Permission state is visible and can be retried from settings.
- Verification: provider tests plus iOS and Android debug builds.

### FCM5: Send terminal notifications from desktop

Status: Completed on 2026-08-10.

- Goal: Convert the FCM2 runtime terminal event to the FCM1 payload and submit
  it to every enabled paired-device delivery handle.
- Affected components: Remote Coding server notifier, relay client, retry
  policy, diagnostics, and paired-device settings.
- Acceptance criteria:
  - Delivery is best-effort and never fails the coding turn.
  - Retries are bounded and idempotent by event ID.
  - Revoked or disabled devices receive no delivery attempts.
- Verification: fake-relay tests covering success, retry, timeout, revocation,
  and concurrent paired devices.

### FCM6: Add notification UX, deduplication, and navigation

Status: Completed on 2026-08-10.

- Goal: Display one notification per terminal event and open the matching
  Remote Coding thread when the notification is tapped.
- Affected components: notification service, mobile navigation, Remote Coding
  client state, and local persistence.
- Preferred approach: Use the remote notification as authoritative when relay
  registration is active. Keep local notification as a fallback only, with a
  persistent bounded event-ID receipt cache.
- Acceptance criteria:
  - FCM and WebSocket delivery cannot produce duplicate notifications.
  - Multiple conversations do not overwrite one another.
  - Foreground behavior, lock-screen privacy, and notification-disabled state
    are explicit.
- Verification: notification routing tests and widget navigation tests.

### FCM7: Complete platform setup and real-device release evidence

Status: Repository-owned platform wiring and the fail-closed release gate were
completed on 2026-08-10. Firebase app files, deployment, release signing
inspection, and physical-device evidence remain environment-owned and pending.

- Goal: Configure the Firebase project, APNs authentication, Android app, iOS
  capabilities, and the Remote Coding release gate.
- Affected components: Firebase console artifacts, Xcode capabilities, Android
  Gradle configuration, deployment documentation, and P1 evidence tooling.
- Acceptance criteria:
  - iOS and Android pass foreground, background, locked, suspended, terminated,
    reconnect, token rotation, notification denial, and revocation scenarios.
  - Notification content remains generic on the lock screen.
  - Relay outage does not affect coding completion or LAN control.
- Verification: physical-device matrix and updated Remote Coding P1 gate.

Implementation notes:

- iOS now declares Push Notifications and Background Modes, including fetch and
  remote-notification execution modes, and requires iOS 15 for Firebase Apple
  SDK 12. Android applies Google Services only when its Firebase application
  file is installed.
- FCM auto-initialization is disabled on both platforms. Explicit enablement
  activates token creation; successful relay revocation deletes the local token
  and disables automatic regeneration.
- `tool/remote_coding_fcm_release_gate.dart` blocks on missing or mismatched
  Firebase application files, incomplete Firebase deployment, missing signed
  physical-device scenarios, or unverified release entitlements and privacy.
- `tool/bootstrap_remote_coding_firebase.dart` inspects a selected project,
  registers only missing namespace-matched mobile apps, and downloads both SDK
  configuration files after an explicit `--apply`.
- The evidence workflow is documented in
  `docs/remote_coding_fcm_release_gate.md`.
- Android and iOS unsigned debug builds pass without Firebase application files,
  preserving fail-closed LAN Remote Coding behavior before deployment.
- The Runner target copies `GoogleService-Info.plist` into the app bundle
  through a conditional `Copy Firebase Configuration` build phase. The Apple
  Firebase SDK reads the plist from the bundle, and the file is gitignored, so
  a required Xcode resource reference would break Firebase-less builds. The
  release gate asserts the build phase so the wiring cannot regress silently.
- Android creates the Remote Coding channel before relay registration and uses
  the same channel as the FCM manifest default for terminated delivery.

## Similar-Pattern Search

- Search terms: `CavernoRuntimeTerminalEvent`, `run_completed`, `run_failed`,
  `showResponseCompleteNotification`, `showSubagentCompletionNotification`,
  `isLoading`, `pendingApproval`, and `pendingQuestion`.
- Inspected modules: execution runtime, ChatNotifier terminal funnel, local
  notification service, Remote Coding client/server, iOS background task bridge,
  and Android notification permissions.
- Follow-up found: approval-required and ask-user-question remote notifications
  should reuse the relay after terminal delivery is stable, but remain outside
  this task sequence.

## Handoff Notes

- FCM1 added the versioned allowlist and passed the repository verification
  entrypoint, including project/package analysis and six focused tests.
- FCM2 added canonical interaction-origin propagation, the privacy-safe
  terminal mapper, authenticated WebSocket delivery, and client receipt state.
  Project and package analysis, all package tests, 36 Remote Coding tests, and
  focused queued/cancelled turn ownership tests passed.
- FCM3a added the relay wire contract, scoped HMAC signing and verification,
  bounded request and event freshness checks, nonce and event replay rejection,
  and recursive structured-log redaction. Project/package analysis, all package
  tests, and 14 focused relay tests passed.
- FCM3b-1 added independently testable secure storage, mobile registration
  separation, backward-compatible desktop relay references, privacy-safe
  diagnostics, and local secret deletion on paired-device revocation. Relay
  credential transfer remains deliberately disconnected from plaintext LAN
  pairing.
- FCM3b-2a removed the delivery credential from mobile registration, added the
  version 2 delegation endpoints and desktop-only redemption response, extended
  relay log redaction for delegation identifiers and challenge material, and
  added the reference one-time state machine. Thirty-one focused relay and
  secure-persistence tests pass.
- FCM3b-2b-1 added strict HTTPS-origin validation, signed relay transport,
  privacy-safe errors, device-bound provisioning coordinators, and persisted
  pending activation and revocation states. Focused relay, persistence, and
  Remote Coding server tests pass; the project analyzer reports no issues.
- FCM3c now isolates replay and outbox identity by delivery handle and event ID,
  applies bounded provider retries, classifies permanent token failures, and
  collapses duplicate provider delivery per event. Memory and Firestore
  emulator tests cover multi-device delivery and per-device replay rejection.
- FCM4 adds FlutterFire Messaging and App Check integration, explicit foreground
  permission flow, secure registration lifecycle, token rotation, revocation,
  and visible disabled or unavailable states. It intentionally fails closed
  when Firebase configuration is absent.
- FCM5 fans each remote-origin terminal event out to active paired devices with
  isolated best-effort retries and privacy-safe delivery diagnostics. Missing,
  revoked, pending, and expired credentials do not affect the coding turn.
- FCM6 adds a bounded seven-day event receipt cache, one local presentation per
  event, WebSocket fallback only when relay notifications are disabled, FCM and
  local-notification tap parsing, and reconnection plus thread selection after
  navigation to the Coding workspace.
- Firebase project identifiers, APNs authentication credentials, and relay
  deployment authority are not present in the repository.
- Keep the current LAN WebSocket protocol operational when FCM is unavailable.
- Update this document after each focused task rather than combining the tasks
  into one broad change.
