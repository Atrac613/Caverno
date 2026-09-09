# Caverno v1.3.21

> Release date: 2026-09-06

## Summary

This release advances paired-device approval workflows across iOS, macOS, and Apple Watch, and expands macOS Remote Coding project management. It also strengthens approval auditing, notification behavior, delegated execution, and Anabasis orchestration.

## Changes

### Features

- **Paired-device approval workflows** — Show desktop approvals on the wrist, carry approval kinds to the initiating device, and record device decisions and notification responses.
- **Typed-code pairing** — Allow debug builds to pair by typed code instead of requiring a scan.
- **macOS coding project management** — Merge the project directory picker and allow creating coding project directories.
- **Remote Coding approval notifications** — Surface approvals as notifications and make their resolution observable.
- **Anabasis orchestration** — Make Anabasis conversational and record usage roles for logged requests.

### Fixes

- **Approval and notification state** — Preserve approval evidence, clear notification suppression correctly, withdraw answered notifications, and prevent declined commands from appearing as disconnections.
- **Watch and phone UI** — Keep the watch compose bar within the safe area, restore blocked-turn cards, and close read-only approvals on the phone.
- **Remote Coding lifecycle** — Remove sheets when interaction is withdrawn and preserve quoted commands in truncated plans.
- **Security and auditing** — Write audit entries atomically, revoke device authority correctly, and close the SA-16 supply-chain residuals.
- **Layout and payload handling** — Prevent activity heatmap failures on narrow screens, maintain drawer spacing, and keep Watch frames within payload budgets.

### Testing

- **Device and pairing verification** — Add coverage for Watch payload decoding, parsed-plan delegation, and typed-pairing behavior.
- **Approval audit coverage** — Pin that audit evidence remains visible and is never copied off the machine.

### Documentation

- **Release and milestone evidence** — Record the 2026-09-06 device session, Watch verification, SA-02 remediation, SA-26 constraints, and the status of WATCH9 through WATCH13.
- **Security and roadmap decisions** — Document P1 transport and resource boundaries, approval authority policy, and the portable memory investigation.

## Version

- `1.3.21+33`

## Notes

This release includes changes spanning iOS, macOS, and Apple Watch workflows. Hardware-dependent verification remains explicitly distinguished from simulator evidence in the project documentation.
