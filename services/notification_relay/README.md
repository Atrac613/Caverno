# Caverno Notification Relay

This directory contains the deployable FCM notification relay for Remote
Coding. It targets Cloud Functions for Firebase 2nd gen on Node.js 22 in
`asia-northeast1`. Firebase Hosting rewrites `/v2/**` to the HTTP function so
clients can use the bare HTTPS origin `https://PROJECT_ID.web.app`.

## Security boundary

- Registration consumes a limited-use `X-Firebase-AppCheck` token with the
  Firebase Admin SDK before parsing the request body.
- Management and delivery operations verify the versioned HMAC contract before
  parsing their bodies.
- Firestore transactions atomically enforce nonce replay, event replay,
  one-time delegation redemption, and delivery outbox creation.
- Delivery replay and outbox keys are scoped by registration, allowing the same
  terminal event to reach multiple devices while rejecting per-device replay.
- Provider retries use bounded exponential backoff, stop on permanent token
  rejection, and use platform collapse identifiers keyed by terminal event.
- FCM registration tokens, App Check tokens, credentials, request bodies, and
  payload identifiers are excluded from ordinary logs.
- Firestore Security Rules deny every client read and write. Only the relay's
  runtime identity uses the Admin SDK.
- FCM uses Application Default Credentials from the Functions runtime. Do not
  add a service-account key to this directory.

## Local verification

Install the locked production dependencies and run the fake-provider tests:

```bash
npm ci --ignore-scripts
npm test
npm audit --omit=dev
```

Run the durable-store concurrency tests with a demo-only Firestore emulator:

```bash
npx firebase-tools@15.26.0 emulators:exec \
  --only firestore \
  --project demo-caverno-relay \
  "npm --prefix services/notification_relay run test:firestore"
```

The emulator project ID must keep the `demo-` prefix so an unavailable emulator
cannot fall through to production resources.

## Environment prerequisites

Before deployment, the environment owner must provide and verify:

1. A Firebase project on the Blaze plan with Firestore and FCM HTTP v1 enabled.
2. Registered Apple and Android applications with enforced App Check providers.
3. APNs authentication configured for the Apple application.
4. A 2nd gen runtime service account with Firestore access, FCM send access,
   and `roles/firebaseappcheck.tokenVerifier`.
5. A Firebase Hosting site for the same project.

From the repository root, inspect and then bootstrap the selected project's
mobile applications:

```bash
fvm dart run tool/bootstrap_remote_coding_firebase.dart \
  --project PROJECT_ID
fvm dart run tool/bootstrap_remote_coding_firebase.dart \
  --project PROJECT_ID \
  --apply
```

The first command is read-only. The second registers only missing Caverno apps
and downloads their public SDK configuration files.

Check the live Firebase prerequisites and deployed relay identity:

```bash
fvm dart run tool/remote_coding_firebase_status.dart \
  --project PROJECT_ID
```

Configure Firestore TTL for replay documents after creating the database:

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=replays \
  --enable-ttl \
  --project=PROJECT_ID
```

Then deploy without creating a `.firebaserc` containing an assumed project:

```bash
firebase deploy \
  --only functions:notification-relay,firestore,hosting \
  --project PROJECT_ID
```

After deployment, verify `https://PROJECT_ID.web.app/health` and provide
`https://PROJECT_ID.web.app` as `CAVERNO_NOTIFICATION_RELAY_URL` at Flutter
build time.
