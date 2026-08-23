# iOS App Privacy Disclosure

Last reconciled: 2026-08-23.

This document maps Caverno-owned off-device collection to
`ios/Runner/PrivacyInfo.xcprivacy` and the matching App Store Connect privacy
answers. It is a release checklist, not proof that external App Store Connect
metadata has already been updated.

## Collection Boundary

Apple defines collection as transmitting data off device so the developer or a
third-party partner can access it longer than necessary to service the request
in real time. On-device persistence alone is not collection.

Caverno owns two collection paths:

1. The default `/feedback` endpoint stores an explicitly submitted feedback
   message and a redacted LLM session log. The log can include user prompts,
   model output, tool activity, timings, token use, and errors. The payload has
   conversation-scoped identifiers but no account or installation identifier.
2. A release configured with `CAVERNO_NOTIFICATION_RELAY_URL` stores an
   installation identifier, FCM registration token, and generic remote-coding
   terminal events. These records are linked to the registered device so push
   delivery can function.

Normal chat, image, video, speech, MCP, webhook, and model traffic goes only to
destinations configured or invoked by the user. Those destinations are not
Caverno-owned collection. A distributor that changes a default to its own
service must reassess this boundary and update both declarations.

Firebase SDK collection belongs to the SDK's own privacy manifest. Confirm the
aggregated Xcode privacy report for every release instead of duplicating SDK
entries in Caverno's application manifest.

## App Store Connect Matrix

| Data type | Linked | Tracking | Purpose | Caverno path |
|---|---:|---:|---|---|
| Customer Support | No | No | Analytics; App Functionality | Explicit feedback text |
| Other User Content | No | No | Analytics; App Functionality | Redacted session prompts, responses, and tool content |
| Performance Data | No | No | Analytics | Session timing and token-use diagnostics |
| Other Diagnostic Data | No | No | Analytics | Session errors and execution diagnostics |
| Device ID | Yes | No | App Functionality | Installation ID and push registration token |
| Product Interaction | Yes | No | App Functionality | Remote-coding terminal event identifiers and outcome |

## Release Checklist

- Keep `NSPrivacyTracking` false and tracking domains empty while Caverno has no
  advertising, data-broker sharing, or cross-app tracking behavior.
- Match all six rows in App Store Connect before submitting the next build.
- Generate the Xcode privacy report from the release archive and review merged
  third-party SDK declarations, especially Firebase.
- Re-run the repository manifest regression and `plutil -lint`.
- Reconcile again when a Caverno-owned endpoint, payload, retention policy,
  analytics SDK, advertising feature, or default provider changes.

## Sources

- Apple, App privacy details on the App Store:
  <https://developer.apple.com/app-store/app-privacy-details/>
- Apple, Describing data use in privacy manifests:
  <https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests>
- Apple, TN3184 Adding data collection details to your privacy manifest:
  <https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest>
