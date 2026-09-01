# Apple Watch Companion

Caverno ships a watchOS companion so a blocked turn can be answered, watched,
and driven by voice without taking the phone out.

## Why a native target

Flutter does not run on watchOS. The companion is a SwiftUI target inside
`ios/Runner.xcodeproj` (`CavernoWatch Watch App`, bundle id
`com.noguwo.apps.caverno.watchkitapp`, watchOS 10.0), embedded into `Runner.app`
by an `Embed Watch Content` copy phase. It is added by
`tool/add_watch_target.rb` rather than by hand: this repository is checked out
as several worktrees, and a merge conflict in a hand-written `project.pbxproj`
diff is far harder to resolve than re-running an idempotent script.

## Shape

```
watchOS app (SwiftUI)
  │  WCSession
  ▼
WatchBridgePlugin            ios/Runner/AppDelegate.swift
  │  MethodChannel  com.caverno/watch_bridge
  │  EventChannel   com.caverno/watch_bridge/commands
  ▼
WatchBridgeService           lib/core/services/watch_bridge_service.dart
  ▼
WatchSessionNotifier         lib/features/watch/presentation/
  ├── projection  ChatState  → WatchSnapshot
  └── commands    WatchCommand → ChatNotifier
```

This is the watch counterpart of `RemoteCodingServerNotifier`: same idea — an
external surface drives `ChatNotifier` — with a different transport and, more
importantly, a different trust model.

## The watch is not a remote principal

SEC4.5g (`docs/sec4_5g_remote_interaction_ownership_task.md`) scoped Remote
Coding so that only the paired device which started a turn may see or resolve
that turn's approvals and questions. Reusing that gate for the watch would hide
every iPhone-initiated approval from it, which is the entire point of the
companion.

The watch is treated as a peripheral of this device, not as a separate
principal:

- turns it sends use `ChatInteractionOrigin.local`;
- it sees pending approvals and questions of local origin;
- it never sees one owned by another paired device — `remoteDeviceId` is
  checked in `findPendingApprovalSummary` and `WatchApprovalMapper`, and both
  have regression tests naming SEC4.5g.

Its authority comes from the iOS↔watch pairing itself: `WCSession` talks only to
the watch paired with this phone.

## Payload budget

`WatchSnapshot` is a separate, small projection — deliberately not
`RemoteCodingServerNotifier._buildSnapshot`, which carries the full transcript
and dashboard statistics and does not fit a WatchConnectivity payload.
`WCSession` rejects oversized dictionaries at runtime, so every unbounded field
is capped, and `watch_snapshot_test.dart` asserts a maximal snapshot stays
inside `watchSnapshotMaxEncodedBytes`.

Snapshots carry a monotonic sequence number. WatchConnectivity gives no ordering
guarantee across transports — an application context can land after a newer
`sendMessage` — and dropping lower sequences is what stops a stale frame from
resurrecting an approval the user already answered.

State goes out twice: `updateApplicationContext` (coalescing, so a watch that
wakes later still sees the current frame) plus `sendMessage` when the watch app
is foreground-reachable. Streamed answer text goes out only over the message
path, as deltas — a coalescing transport would silently swallow sentences that
are being read aloud.

## Approvals

File, shell, and git approvals **cannot arise on iOS**. `mcp_tool_service.dart`
gates all three behind `isDesktopPlatform`, because writing arbitrary paths on a
sandboxed mobile OS is both risky and largely unusable. The watch's approval
path therefore serves a desktop-driven turn, or the kinds mobile does have —
BLE, SSH, browser, participant. `ask_user_question` is unconditional and is the
interaction the companion answers most often on a phone-only setup.

A dialog the watch resolves is not yet dismissed on the phone; see WATCH6 in
`docs/roadmap.md`.


`ChatState` keeps ten independent `Pending*` fields.
`describePendingApproval` flattens them into one shape; its switch is exhaustive
over the sealed `PendingToolApproval`, so a new kind is a compile error rather
than an approval that silently never reaches the wrist.

Two kinds are surfaced read-only: computer-use needs smoke arming and SSH
connect needs credentials, and neither can be answered honestly with a single
yes/no. They report `isSimpleDecision: false` and the watch says "Continue on
iPhone".

## Notification fallback

When the watch app is not running, the approval notification itself carries
Approve/Deny (`NotificationService.approvalCategoryId`). iOS forwards a
notification and its actions to a paired watch automatically, so this path needs
no watchOS code and also works on the phone's lock screen.

Two rules keep it honest:

- the body names the command (`wants to run: dart analyze`) rather than saying a
  thread is waiting, because a button that approves an unseen command defeats
  the approval gate it belongs to;
- actions appear only when the approval id is known *and* the kind is a simple
  decision. Without the id, a second approval queuing behind the first would
  make the decision land on the wrong request.

The push path is not wired, and the blocker is not the one it looks like. The
only notification the relay sends is a run *completion*, so there is no
approval to attach a category to; carrying one would mean adding fields to
`RemoteCodingNotificationPayload`, whose contract calls that a
privacy-boundary change. The `firebase_messaging` limitation — it does not
surface `actionIdentifier` on iOS, so a native `UNUserNotificationCenter`
delegate would be needed — is real but secondary. See WATCH5 in
`docs/roadmap.md`.

## Thread switching and the glance

The snapshot carries the threads the watch may switch to, capped at the source
with a flag saying when the list was cut. `selectConversation` applies the
choice; a vanished id is refused with its own code rather than silently doing
nothing.

`CavernoWatchWidgetExtension` is embedded in the watch app and reads a small
record through the App Group — counts and a status word, never conversation
text, because a widget renders without anyone opening anything. App Group
containers are per-device, which is precisely what makes this work: the watch
app and its widget run on the same watch. `transferCurrentComplicationUserInfo`
is not used at all; the watch app already holds the state, so nothing needs to
cross from the phone and no delivery budget is spent.

An unsigned simulator build applies no entitlements, so the App Group container
is absent and the store degrades to a no-op. That is the safe failure, but it
renders identically to "nothing running" — confirm the glance on a signed
build.

## Voice

Input uses watchOS dictation through a SwiftUI `TextField`; output uses
`AVSpeechSynthesizer` on the watch. Markdown is reduced to plain text on the
watch at render and speech time, never in the phone's projection:
`ParseResult.text` is a pure concatenation of the text segments and the stream
deltas depend on that prefix stability, which stripping would break. Synthesis is local rather than piped from
the phone because routing audio through Whisper or VOICEVOX adds a file transfer
in each direction, and the latency lands exactly between speaking and being
answered. Remote synthesis stays available as a later option.

`VoiceModeNotifier` is not reused: it is built around the phone's own mic and
speaker and a barge-in loop.

## Background execution

`WCSession.sendMessage` can wake the iOS app in the background, but an LLM turn
routinely outruns the background window. Turns are wrapped with the existing
`BackgroundTaskService`. Beyond that window the completion still arrives as a
local notification, which iOS forwards to the watch.

## Verifying

```bash
tool/flutter_test_quiet.sh test/features/watch/
```

```bash
xcodebuild build -project ios/Runner.xcodeproj -target "CavernoWatch Watch App" -sdk watchsimulator26.5 -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Pair the simulators from the command line — `xcrun simctl pair` exists and
`simctl boot <pair-udid>` brings both up; no GUI is needed. Two things about
that environment cost real time, so they are worth knowing: the app's
preferences live in its sandboxed container, not where `simctl spawn defaults`
writes, and cfprefsd caches them until the device is rebooted; and a simulator
configured for Japanese input turns typed ASCII into kana, so drive text entry
through `simctl pbcopy` and paste, or set `AppleKeyboards` to English first. Three things need real hardware: notification forwarding
while the phone is locked, the effective background window, and haptics.
