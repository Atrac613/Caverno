# Remote Coding P1 Release Gate

- Status: `blocked`
- Generated at: `2026-09-06T18:40:12.443181`
- Next action: Resolve blocked Remote Coding P1 gates before product release.

## Static Gates

- `mobile_auto_reconnect`: `ready`
  - Mobile schedules bounded automatic reconnect after unexpected LAN drops.
  - Evidence: Client notifier uses finite reconnect backoff, socket ping intervals, and reconnect state tests.

- `command_timeout_correlation`: `ready`
  - Mobile tracks request IDs and exposes timed-out remote commands.
  - Evidence: Client notifier tracks command IDs, clears them on correlated replies, and surfaces timeout state.

- `support_diagnostics`: `ready`
  - Mobile and desktop diagnostics expose support state without token material.
  - Evidence: Diagnostics include protocol and reconnect metadata, while widget and unit tests prove redacted copy support.

- `transport_security`: `ready`
  - Credentials travel only over a pinned confidential transport, and a session is channel-bound and short-lived.
  - Evidence: Pinned WSS with platform roots disabled, a release policy that refuses a plaintext LAN bind, and a channel-bound challenge, each named by a test.

- `resource_boundary`: `ready`
  - Unauthenticated connections expire, and connection, frame, and message rates are bounded per source.
  - Evidence: Occupancy, frame-size, and rate limits are enforced at the server and rejected before the WebSocket upgrade, each named by a test.

- `host_snapshot_metadata`: `ready`
  - Host snapshots advertise protocol and Remote Coding capabilities.
  - Evidence: Host snapshots expose protocol version, safe mobile capabilities, and active session count.

- `multi_device_evidence_flow`: `ready`
  - Desktop exports mergeable multi-device evidence for the P1 household checklist.
  - Evidence: Desktop settings copy multi-device evidence and the release gate merges its checklist patch.

- `p1_docs_and_gate`: `ready`
  - Remote Coding P1 has a documented release gate.
  - Evidence: P1 documentation names the automated gate and manual evidence sections.

## Manual Gates

- `resilience_soak`: `blocked`
  - iOS and Android survive LAN soak, background/resume, sleep/wake, and desktop IP change recovery.
  - Evidence: Missing or false checklist fields: resilienceSoak.iosLanSoakThirtyMinutes, resilienceSoak.androidLanSoakThirtyMinutes, resilienceSoak.desktopSleepWakeReconnect, resilienceSoak.mobileBackgroundResumeReconnect, resilienceSoak.desktopIpChangeRecovery
  - Next action: Run the P1 LAN resilience soak on real iOS and Android devices.

- `support_packet_review`: `ready`
  - Mobile and desktop support packets are useful and contain no token material.
  - Evidence: All required checklist fields are true.

- `multi_device_household`: `ready`
  - Multiple paired devices can coexist, revoke independently, and preserve remote approval boundaries.
  - Evidence: All required checklist fields are true.
