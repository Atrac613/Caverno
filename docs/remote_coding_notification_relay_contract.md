# Remote Coding Notification Relay Contract

Status: FCM3a through the local FCM3c relay implementation completed on
2026-08-10. Environment provisioning, deployment, and a live FCM canary remain
pending.

## Security Boundary

The relay is the only component allowed to hold FCM registration tokens and
FCM provider credentials at the same time. The mobile application sends its FCM
registration token directly to the relay over HTTPS. The desktop may retain
only an opaque delivery handle, delivery key ID, expiry, and scoped delivery
secret. Remote Coding uses certificate-pinned `wss://` and rejects plaintext
credential transport. Relay management and delivery secrets must still never
be added to pairing, authentication, or snapshot payloads.

Registration requires a Firebase App Check token in
`X-Firebase-AppCheck`. The relay must verify that token with the Firebase Admin
SDK and reject missing or invalid tokens before processing the body. Merely
checking that the header exists is not sufficient in a deployed relay.

FCM service-account material must be available only in the relay runtime. Use
Application Default Credentials or Workload Identity where available. Never
commit a service-account key or distribute it to a Caverno application.

## Integrated pairing setup

Supporting protocol-v2 desktops advertise `capabilities.notificationRelaySetup`.
An unconfigured relay returns a setup error without affecting the connection. After a new pairing succeeds, a supporting
mobile client requests OS notification permission and registers directly with
the relay. An explicit disable or a prior permission denial is respected.
Saved connections do not automatically prompt again; notification setup can be
retried from the connected page.

The authenticated mobile sends `requestNotificationRelay` with an empty
payload. The server derives the target device from the authenticated session;
it rejects supplied target IDs. A correlated snapshot returns
`notificationRelayChallenge` with kind, challenge ID, SHA-256 digest, target
device ID, and expiry. The secret stays on the desktop. Each device has at most
one outstanding challenge, and requesting one does not invalidate another
device's challenge. Challenges expire and are consumed once.

The mobile creates the existing HTTPS delegation and sends
`relayDelegationReady`. It waits for the correlated activation snapshot, whose
`notificationRelayHandle` identifies only the authenticated device's active,
unexpired registration. The mobile checks the handle against its own
registration before reporting success. A matching active handle avoids repeat
delegation. Disconnects and timeouts fail notification setup without invalidating
an otherwise healthy pairing. The mobile keeps a local host/handle confirmation
for offline display; connected modern desktops remain authoritative.

Missing capability support retains the notification QR flow for older
protocol-v2 desktops. Protocol-v1 compatibility is not relaxed. Both flows keep
FCM/App Check tokens and management secrets between mobile and relay, and delivery
secrets between desktop and relay. Registration alone is shown as incomplete
until desktop authorization succeeds. Receive/tap listeners do not depend on
successful relay registration; local terminal notifications remain available
when push setup is incomplete or unavailable.

## Endpoints

All request and response bodies use `schemaVersion: 2`. Version 1 was never
deployed and is intentionally not accepted.

### Register an installation

```text
POST /v2/registrations
X-Firebase-AppCheck: <verified App Check token>
```

The body contains the mobile installation ID, `ios` or `android` platform, FCM
registration token, and UTC request timestamp. The response contains:

- An opaque delivery handle.
- A management key ID and secret retained in mobile secure storage.
- A management credential expiry timestamp.

Registration does not create or return a delivery credential. The mobile
application never receives a desktop delivery secret.

Registration responses and request bodies must never be logged.

### Rotate the FCM registration token

```text
PUT /v2/registrations/{deliveryHandle}/token
```

The body contains only the new FCM registration token. The request is signed
with the management credential.

### Revoke a registration

```text
DELETE /v2/registrations/{deliveryHandle}
```

The request is signed with the management credential. Revocation deletes the
FCM token and invalidates both scoped credentials. Repeating a successfully
processed revocation returns a stable idempotent response without restoring the
registration.

### Deliver a terminal notification

```text
POST /v2/registrations/{deliveryHandle}/deliveries
```

The request is signed with the delivery credential and contains only the FCM1
notification allowlist. Prompts, model output, tool data, file contents,
command output, pairing credentials, and provider credentials are forbidden.

### Create a desktop delegation

```text
POST /v2/registrations/{deliveryHandle}/delegations
```

The mobile request is signed with the management credential and binds a
short-lived challenge ID and SHA-256 challenge digest to one authenticated
Remote Coding device ID. The challenge secret is generated by desktop, appears
only in the legacy local QR flow, and is never sent through the LAN WebSocket
or this creation request. Integrated setup exchanges only its digest. The response contains an opaque delegation ID and expiry.

### Redeem a desktop delegation

```text
POST /v2/delegations/{delegationId}/redeem
```

Desktop submits the dedicated challenge secret directly to the configured relay
HTTPS origin with the challenge ID, target device ID, and an idempotency key.
The relay atomically verifies `pending`, expiry, device binding, and the stored
digest before creating a per-device delivery credential. The first accepted
request transitions to `redeemed`; a retry with the same proof and idempotency
key returns the same response. Any other second redemption fails closed.

The response contains the delivery handle, delivery key ID, delivery secret,
and credential expiry. The request and response bodies must never be logged.

### Activate a redeemed credential

```text
POST /v2/registrations/{deliveryHandle}/delegations/{delegationId}/activate
```

Desktop signs activation with the newly redeemed delivery credential only after
both the secret and paired-device metadata have been saved successfully. The
relay transitions `redeemed` to `active` atomically. Rotation must keep the old
credential active until this transition succeeds.

### Revoke one desktop delivery credential

```text
DELETE /v2/registrations/{deliveryHandle}/delivery-credentials/{deliveryKeyId}
```

The request is signed by the same delivery credential and can revoke only that
credential. Desktop retains retryable remote-revocation state and its secure
secret until relay revocation succeeds or the credential expires.

## Signed Request Headers

FCM token rotation, registration revocation, delegation creation, delegation
activation, scoped delivery-credential revocation, and notification delivery
require:

```text
X-Caverno-Relay-Key-Id
X-Caverno-Relay-Timestamp
X-Caverno-Relay-Nonce
X-Caverno-Relay-Signature
```

The signature is unpadded base64url HMAC-SHA256 over this UTF-8 canonical
request:

```text
caverno-relay-v1
<UPPERCASE HTTP METHOD>
<EXACT PATH>
<KEY ID>
<UNIX TIMESTAMP SECONDS>
<NONCE>
<LOWERCASE SHA-256 BODY DIGEST>
```

The relay resolves the scoped secret from the delivery handle and key ID,
recomputes the signature, and compares it in constant time. A key must have
exactly one scope: management or delivery.

## Freshness and Replay Rules

- Signed requests are accepted only within five minutes of relay time.
- Delivery events are accepted only from fifteen minutes in the past through
  five minutes in the future.
- A `(key ID, nonce)` pair is accepted once.
- A terminal `eventId` is accepted once, even with a fresh nonce.
- Production replay checks must be atomic and shared across relay instances.
- Replay entries must live at least as long as the accepted event window.
- Replay-ledger capacity exhaustion must fail closed instead of evicting an
  entry that is still inside the replay window.

The in-app replay guard is a bounded single-instance reference implementation.
It is not the production persistence mechanism.

## Logging and Error Responses

Ordinary relay logs may include operation name, outcome, HTTP status, latency,
and coarse platform. They must redact:

- FCM, App Check, OAuth, and authorization tokens.
- Management and delivery secrets, signatures, key IDs, and nonces.
- Delivery handles, installation IDs, event IDs, turn IDs, and conversation
  IDs.
- Delegation IDs, challenge IDs, challenge digests, challenge secrets, target
  device IDs, and idempotency keys.

Authentication failures use a generic `401` response. Replays and stale
requests use `409`. Invalid bodies use `400`. Error bodies must not echo secret
or identifier values.

## Remaining Implementation Slices

### FCM3b-1: Secure persistence (completed)

- Mobile relay metadata is stored separately from management and delivery
  secrets, which use platform secure storage.
- Desktop delivery secrets use per-device secure-storage keys. Paired-device
  settings contain only the delivery handle, delivery key ID, and expiry.
- Legacy paired-device JSON remains readable, and incomplete relay state fails
  closed.
- Revoking a relay-enabled paired device deletes its local delivery secret.

### FCM3b-2a: Delegation contract (completed)

- Version 2 registration returns only a mobile management credential.
- The relay-mediated creation, one-time redemption, activation, and scoped
  delivery-credential revocation endpoints are frozen.
- The in-memory reference state machine covers challenge and device binding,
  expiry, one-time redemption, response-loss retry, activation, and revocation.
- Structured relay redaction covers every delegation identifier and secret.

### FCM3b-2b-1: Relay client and local lifecycle (completed)

- Relay URLs are accepted only as bare HTTPS origins; paths, user information,
  queries, fragments, and plaintext HTTP fail closed.
- Registration uses App Check. Management and delivery operations use the
  versioned HMAC signature, while one-time redemption sends its proof directly
  to relay HTTPS without exposing it in errors.
- Desktop stores the delivery secret and non-secret metadata as
  `pendingActivation` before activation. Activation failure remains retryable,
  and only active, unexpired credentials are eligible for delivery.
- Revocation changes local state to `pendingRevocation` before contacting relay.
  The secret is retained until idempotent remote revocation and local cleanup
  both succeed.

### FCM3b-2b-2: QR and Remote Coding lifecycle wiring (completed)

- Desktop creates a dedicated, device-bound, five-minute QR challenge without
  reusing the LAN pairing secret or encoding a relay origin. Mobile sends only
  the challenge digest to relay. The authenticated WebSocket response contains
  only the challenge ID, delegation ID, and expiry.
- Desktop consumes the challenge once for the authenticated device, redeems the
  delegation directly over relay HTTPS, persists the scoped delivery credential
  as `pendingActivation`, and then activates it.
- Pending activation and revocation are retried after desktop startup. Device
  revocation immediately disables LAN authentication and disconnects active
  sockets, but retains a tombstone and delivery secret until scoped remote
  revocation succeeds.
- FCM token rotation and mobile registration cleanup remain in FCM4 because
  they depend on Firebase Messaging and App Check lifecycle integration.

### FCM3c: Deployable relay

- The local Cloud Functions 2nd gen implementation verifies App Check before
  registration body parsing and verifies signed requests before parsing their
  bodies. The Firebase Admin SDK uses the runtime identity for FCM.
- Firestore transactions cover registration collision safety, nonce and event
  replay, one-time delegation redemption, and atomic event/outbox acceptance.
  A scheduled worker retries accepted provider failures under a delivery lease.
- Firebase Hosting rewrites preserve the client contract's bare HTTPS origin.
  Firestore Security Rules deny all client access.
- Fake-provider tests cover the complete credential and delivery lifecycle.
  Firestore emulator tests prove concurrent replay, redemption, and outbox
  behavior. Locked production dependencies currently audit with zero known
  vulnerabilities.
- Environment provisioning, deployment, replay TTL configuration, and a live
  FCM device canary remain pending until Firebase project IDs, App Check
  providers, APNs configuration, and runtime identity are supplied.

## Firebase References

- [Verify App Check tokens from a custom backend](https://firebase.google.com/docs/app-check/custom-resource-backend)
- [Authorize FCM HTTP v1 send requests](https://firebase.google.com/docs/cloud-messaging/send/v1-api#authorize-http-v1-send-requests)
