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

The exclusion is written the way the Remote Coding gate is written — `origin`
first, a remote interaction with a missing owner counted against resolving here
rather than for it. Reading only `remoteDeviceId` inverts that, and the two
agreed in the shipped build only by coincidence. Recorded as SA-24 in
`docs/security_followup_review_2026-08-24.md`.

## Payload budget

`WatchSnapshot` is a separate, small projection — deliberately not
`RemoteCodingServerNotifier._buildSnapshot`, which carries the full transcript
and dashboard statistics and does not fit a WatchConnectivity payload.
`WCSession` rejects oversized dictionaries at runtime, so every unbounded field
is capped, and `watch_snapshot_test.dart` asserts a maximal snapshot stays
inside `watchSnapshotMaxEncodedBytes`.

The frame carries the tail of the thread, not just the last answer: the watch
draws a message transcript, and a single trailing paragraph cannot say what was
asked. Eight bubbles, 180 runes each with 400 for the newest — the one being
read — plus a flag saying the thread was cut. `lastAssistantText` stays in the
frame even though the transcript supersedes it, because the two apps ship as
one bundle but are not guaranteed to be the same build at runtime, and a watch
newer than its phone would otherwise render an empty thread.

Budget headroom is measured in a multi-byte script, not in ASCII. Every cap
counts runes, so an English-only measurement under-reports the real payload
threefold and would let a frame that is legal in English be rejected at runtime
in Japanese.

Snapshots carry a source identity, the time that source started, and a
monotonic per-source sequence number. WatchConnectivity gives no ordering
guarantee across transports — an application context can land after a newer
`sendMessage` — and dropping lower sequences is what stops a stale frame from
resurrecting an approval the user already answered. The source identity matters
when the iPhone app restarts: its sequence begins at one again while the watch
process may still remember a much larger number. A newer source start replaces
that cursor; a delayed frame from the retired source remains rejected.

Source-less snapshots from an older iPhone build retain the original sequence
behavior until the watch sees a source-aware frame. After that transition they
are rejected, because accepting an unversioned delayed application context
could restore an already-resolved interaction.

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

A dialog the watch resolves is dismissed on the phone by `ApprovalDialogPresenter`,
which pops by route name. That is deliberately a no-op when the dialog is not
topmost: popping whatever is on top would let a mistimed resolution close the
screen the user is actually looking at.

The watch also waits for the correlated command result before leaving an
approval, question, or thread picker. A failure stays on the current screen and
can be retried; a command queued while the phone is unreachable says so and
leaves only after a later snapshot confirms the state change. Transport errors
from message and control actions are also shown on the transcript.

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

## The transcript

The first screen after loading is always the message thread: bubbles with tails,
outgoing on the right in the phone's accent and incoming on the left in its dark
surface colour, a relative day-and-time header wherever the conversation paused
for more than fifteen minutes, and a typing bubble while an answer is being
written. A pending approval or question no longer replaces the thread; an
orange toolbar button opens it, then returns to the thread after the person
answers. Thread switching remains available beside the attention button while
something is waiting.
Once messages exist, the scroll area holds only the exchange and its status —
the controls that used to sit between the answer and the bottom of the screen
moved into a pinned compose bar and the navigation bar, because on a wrist every
row of chrome is a row of conversation.

The transcript follows new text only while the reader is already near the
bottom. Scrolling up opts out of live following until the reader returns, so a
streaming answer cannot pull older messages out from under them. An empty thread
has an explicit starting state rather than a blank surface. VoiceOver announces
each bubble with its speaker and announces the typing indicator as activity,
rather than relying on alignment and colour to carry meaning.

Three things are drawn on the watch rather than sent ready-made. Markdown is
reduced at render time, for the reason in the section below. Timestamps are
formatted here because only this device knows the locale and the 12/24-hour
setting the person reads; the frame carries UTC. And the streaming bubble
prefers whichever is longer of the live delta text and the frame's copy — the
deltas usually run ahead, but a watch that joined mid-turn has only what
arrived since it connected, and the frame has the whole answer.

A synthesized prompt never becomes a bubble. The tool-result envelope carries
`MessageRole.user` because that is the only role a model acts on; drawn as a
bubble it would put a `<tool_use>` blob on the wrist in the person's own voice,
and the speaker would read it aloud.

The app tint is scoped to the one button that wants it. A tint applied
app-wide also repaints every `role: .destructive` button in the accent colour,
which turned Deny on the approval screen into an ordinary-looking blue button —
the one place on this watch where a destructive action must not look ordinary.

## Voice

The compose-bar mic is a SwiftUI `TextFieldLink`, the public watchOS entry
point for the system text-input experience. On watchOS 11 and later the system
opens the last-used input method, including Dictation. Caverno does not try to
replace this UI with its own recorder or keyboard, and it does not label
`WKTextInputMode.plain` as a dictation-only mode: that value only excludes
emoji. Dictation needs to be selected once from the system input chooser if
the keyboard was the last method used.
The compose control shows both “Message” and a microphone so the system text
input is discoverable as more than dictation. `isVoiceMode` follows the "Read
replies" switch rather than being sent unconditionally: it shortens the phone's
answers for speech and holds back auto-continue, which is right for a spoken
turn and wrong for a typed one. That switch is persisted and off until asked
for — the speaker used to run only while a separate voice screen was open, and
it now runs on the screen a raised wrist lands on, so an on-by-default speaker
would make every glance start talking. Output uses
`AVSpeechSynthesizer` on the watch. Markdown is reduced to plain text on the
watch at render and speech time, never in the phone's projection:
`ParseResult.text` is a pure concatenation of the text segments and the stream
deltas depend on that prefix stability, which stripping would break. Synthesis is local rather than piped from
the phone because routing audio through Whisper or VOICEVOX adds a file transfer
in each direction, and the latency lands exactly between speaking and being
answered. A final stream marker is sent even when it carries no new text, so
the watch can read the last fragment of an answer that does not end in
punctuation. Remote synthesis stays available as a later option.

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

```bash
swiftc "ios/CavernoWatch Watch App/WatchModels.swift" tool/watch_snapshot_cursor_smoke.swift -o /tmp/watch_snapshot_cursor_smoke
/tmp/watch_snapshot_cursor_smoke
```

Pair the simulators from the command line — `xcrun simctl pair` exists and
`simctl boot <pair-udid>` brings both up; no GUI is needed. Two things about
that environment cost real time, so they are worth knowing: the app's
preferences live in its sandboxed container, not where `simctl spawn defaults`
writes, and cfprefsd caches them until the device is rebooted; and a simulator
configured for Japanese input turns typed ASCII into kana, so drive text entry
through `simctl pbcopy` and paste, or set `AppleKeyboards` to English first.
Keep the watch app running while restarting only the iPhone app at least once.
The first snapshot from the restarted projection has a reset sequence, so this
is the boundary test that proves source-aware ordering rather than only ordinary
in-process delivery. Three things need real hardware: notification forwarding
while the phone is locked, the effective background window, and haptics.
