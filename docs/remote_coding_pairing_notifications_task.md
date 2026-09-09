# Pairing Notification Integration

## Task

- Goal: Complete mobile push setup as part of a successful Remote Coding pairing.
- User-visible behavior: One pairing QR, followed by the OS notification prompt;
  a notification failure leaves Remote Coding connected and offers retry.
- Non-goals: Change Firebase relay endpoints, upload app builds, or deploy services.

## Context

- Components: Mobile notification lifecycle, Remote Coding client/server,
  notification delegation, pairing UI, and repository preferences.
- Reference: `remote_coding_notification_relay_contract.md` and existing
  `relayDelegationReady` redemption/activation flow.
- Compatibility: Negotiate an additive protocol-v2 capability. Retain the
  notification QR path for protocol-v2 desktops without it.

## Implementation Slices

1. Preserve notification taps and WebSocket fallback during relay outages.
2. Add authenticated device-scoped setup and correlated activation responses.
3. Trigger notification setup after pairing, preserve user choices, and show
   completion only after desktop authorization.

## Acceptance Criteria

- Reject unauthenticated requests, supplied device IDs, expired challenges,
  and replayed delegation responses.
- Keep FCM and App Check tokens off the WebSocket; retain the challenge secret
  on desktop and delivery secrets on the desktop/relay HTTPS boundary.
- Respect explicit disable and OS denial; retain manual retry for saved hosts.
- Avoid duplicate registration/delegation and reject a connection change during setup.
- Keep the existing pairing and local notification fallback usable on failure.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/remote_coding
```

Signed iOS/Android background delivery and notification-tap checks remain a
physical-device release gate; unit and local WSS tests do not establish FCM
provider delivery. Firebase app files and the relay build define must be supplied
for each release checkout.

## Similar-Pattern Search

Inspect `relayDelegationReady`, `allowedClientCommands`, `_sendCommand`,
`_listenForMessages`, token-refresh state updates, and persisted notification
preferences. Legacy QR setup must also await desktop activation.

## Verification Results

- Static analysis passed for the application and workspace packages.
- Remote Coding, Chat page integration, and FCM gate tests passed: 247 tests.
- The final notification-tap preservation change passed all 29 mobile
  notification tests again.
- The expanded quality run exposed seven existing file-size ratchet failures
  in unchanged Chat sources (six primary files and the ChatNotifier library).
  `git diff ce73e7345^ -- lib/features/chat test/quality` was empty; no ceilings
  were raised and no unrelated Chat refactoring was included.
- Local pinned-WSS tests covered authenticated setup, rejected target injection,
  replay rejection, activation failure/retry, duplicate suppression, and a
  connection change during delegation. Mobile tests covered automatic pairing,
  explicit disable, existing OS denial, registration-time host changes, cold
  notification taps, and local fallback.
- Physical-device FCM/APNs delivery remains unverified. No release upload or
  Firebase deployment was performed.
