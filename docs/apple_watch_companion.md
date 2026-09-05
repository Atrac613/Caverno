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
is capped and the encoded frame is held to `watchSnapshotMaxEncodedBytes`
whatever the caps produce — see below.

The frame carries the tail of the thread, not just the last answer: the watch
draws a message transcript, and a single trailing paragraph cannot say what was
asked. Eight bubbles, 180 runes each with 400 for the newest — the one being
read — plus a flag saying the thread was cut. `lastAssistantText` stays in the
frame even though the transcript supersedes it, because the two apps ship as
one bundle but are not guaranteed to be the same build at runtime, and a watch
newer than its phone would otherwise render an empty thread.

The rune caps and the byte budget are two different constraints, and they do
not agree. A rune costs one byte in English, three in Japanese and four in
emoji, so a maximal frame sized only by runes lands at 36% of the budget in
English, 89% in Japanese and 116% in emoji. `WCSession` does not clip an
oversized dictionary — it refuses it — and the refusal surfaces as an `NSLog`
in `WatchBridgePlugin`, so the visible symptom is a watch silently stuck on
stale state.

`toJson` therefore enforces the budget rather than asserting it: it walks a
ladder of progressively smaller caps and sends the first frame that fits.
Almost every real frame fits on the first rung, which is the full projection.
The shedding order follows what the frame is for. The thread picker goes first
— it is navigation, not the decision, and `conversationsTruncated` already
tells the watch to point at the iPhone; the picker stays reachable on that flag
alone, so shedding the list does not also take the notice away. Transcript
depth follows under `messagesTruncated`. `lastAssistantText` is next, since it
duplicates the newest bubble and exists only for a watch older than its phone,
which is a smaller loss than a frame that reaches no watch at all. The pending
approval and question shrink last and never disappear.

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
sandboxed mobile OS is both risky and largely unusable. What the watch's
approval path actually serves is therefore the kinds mobile does have — BLE,
SSH, browser, participant. `ask_user_question` is unconditional and is the
interaction the companion answers most often on a phone-only setup.

A desktop-driven turn now reaches the wrist as a notification, but not in the
companion app. The Remote Coding server is desktop-only and mobile is
client-only, so a blocked desktop turn lives in `RemoteCodingClientState` on
the phone — a provider `WatchSessionNotifier` does not read. WATCH10 closed
half of that: `RemoteCodingMobileNotificationNotifier` raises the actionable
approval notification when the client receives one, iOS forwards it and its
actions to the wrist with no watchOS code, and Approve/Deny routes back by id
to whichever notifier owns the request. The notification names the host,
because approving a shell command without knowing which machine runs it is the
failure that path must not ship, and it is suppressed while the Remote Coding
page is on screen, since that page raises its own sheet. Showing the same
interaction inside the companion is WATCH11.

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

## The goal

A coding thread reached the wrist as bubbles with none of the state that makes
it a coding thread, and one piece of that state is a decision:
`ConversationGoalStatus.awaitingConfirmation` means the harness ran out of work
and cannot say the objective was met. It rendered as `WatchTurnStatus.idle` —
indistinguishable from a finished thread. It is now its own status, counted in
`needsAttention`, so the transcript's attention button, the glance and the
Smart Stack widget agree without any of them special-casing it.

The measured behaviour behind the whole feature is that the model does not
volunteer `update_goal` but answers when asked. Being asked is the mechanism,
and a wrist is where asking is cheapest.

`resolveGoal` routes through `markCurrentGoalStatus`, the writer the phone's
goal menu uses, rather than persisting a goal of its own. `validationStatus`
already has three writers and the lesson from that is not to add a fourth shape
of the same problem: a second path would drift from
`ConversationGoalStatusTransition` the moment either side changed. The decision
is stamped with the thread it was composed against for the reason WATCH3 gave
`sendMessage` the same stamp, and it is refused outright when the goal is no
longer asking — the frame the watch acted on can be seconds old, and quietly
closing a goal that resumed in the meantime is the stale-frame failure the
snapshot cursor exists to prevent.

The confirm screen shows the harness's `completionSummary` beside the choice.
Answering "was this met?" without it is answering blind. A blocked goal names
its blocker in the transcript footer, which is the difference between "this is
finished" and "this is stuck".

The thread picker labels each thread's workspace mode.
`ConversationsState.conversations` is unfiltered, so without it a coding agent
mid-task is offered as if it were another chat. Both the mode and the goal
status travel as strings rather than closed enums, for the reason
`WatchApproval.kind` does: a watch older than its phone must degrade to showing
less rather than failing to decode the frame.

**None of the goal half can fire on iOS today**, and the paired-simulator run
is what found it. `/goal` is gated on `isCodingWorkspace`, and on iOS the
coding workspace always renders `RemoteCodingPage` — `isMobileRemoteCoding` is
`isCodingWorkspace && isRemoteCodingMobilePlatform()`, and that predicate is
just `Platform.isAndroid || Platform.isIOS`. A local iOS thread therefore never
carries a goal, and `_goalFor` reads exactly that thread. This is the same
shape as the approval gap above: the machinery is right and points at the wrong
source. The goal a phone user has is on the desktop they are driving through
Remote Coding, which lives in `RemoteCodingClientState` — the second input
source WATCH11 adds. The code stays because it is tested, it is the shape
WATCH11 needs, and it fires the moment a goal reaches `ChatState`.

Adding these fields spent most of what was left. A maximal frame carrying a
goal encodes to 97.5% of the budget in Japanese — still the full projection,
which is the acceptance criterion, but the next field to go on the wire will
push a wide frame onto the shedding ladder rather than fitting beside it.

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

## Foreground notifications and the delegate

A notification raised while the app is in the foreground is the normal case for
this feature, not an edge case: the approval is raised precisely when the
person is not looking at the surface that owns it, which usually means they are
looking at another one.

That did not work, and the reason is worth writing down because the symptom is
silent. `FLTFirebaseMessagingPlugin` takes
`UNUserNotificationCenter.delegate`, and when no earlier delegate answers
`willPresentNotification` it returns `UNNotificationPresentationOptionNone`
unless `setForegroundNotificationPresentationOptions` has persisted otherwise.
There is one such delegate per app, so this suppressed every foreground
notification — including the local ones, because
`flutter_local_notifications` never claims the delegate at all and only
implements the callback. The log said the notification was raised and nothing
appeared.

The fix is native and deterministic: `AppDelegate` claims
`UNUserNotificationCenter.delegate` in `didFinishLaunchingWithOptions`, before
`didInitializeImplicitFlutterEngine` registers anything. Firebase then finds an
earlier delegate, captures it, and forwards `willPresentNotification` to it,
which reaches the plugin chain and lets each notification's own presentation
options decide.

Doing it from Dart was tried first and does not work: it needs Firebase
initialized, and on a device that never configured Firebase the call fails with
`[core/not-initialized]` — which is exactly the device that most needs
foreground notifications to work, since it has no push at all. Each
notification also states its own `presentBanner`/`presentList`/`presentAlert`,
rather than relying on defaults persisted in `NSUserDefaults` at plugin
initialization.

## Notification actions and UIScene

Approve and Deny appeared on the notification and every press was dropped. The
device log is what settled it, after several rounds of reading Dart that was
never the problem:

```
SpringBoard  Sending action(s) in update: <UINotificationResponseAction>
Runner       Received action(s) in scene-update: <UINotificationResponseAction>
SpringBoard  recieved action response <BSActionResponse ... "empty-response">
```

The app adopts `UIApplicationSceneManifest`, so iOS delivers the press as a
`UINotificationResponseAction` in a scene update. `flutter_local_notifications`
registers itself only through `addApplicationDelegate:` and never
`addSceneDelegate:`, so its own `UNUserNotificationCenterDelegate`
implementation is never reached on a scene-based app, and the app answers
"empty-response" — the notification showed its buttons and threw away every
answer.

`AppDelegate` catches the response and forwards the two fields Dart needs, the
action identifier and the payload the plugin stored under
`userInfo["payload"]`, over `com.caverno/notification_actions`. Deliberately
narrow: it does not reimplement the plugin and does not touch presentation,
which already works. The channel holds the last response until Dart attaches,
because a press can arrive before an isolate exists.

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

The Dart tests cover what the phone writes and the `xcodebuild` above covers
that the watch compiles. Neither covers the boundary between them, which is
where WATCH2 found ten defects: a renamed key or a status the watch does not
name crosses it silently and arrives as a default value. This checks both
directions — the frame the Dart encoder actually produces against the watch's
decoder, and every `WatchCommandType` against `WatchCommand.allowed`:

```bash
tool/watch_wire_contract_smoke.sh
```

The fixture is generated by `tool/watch_wire_fixture.dart` rather than checked
in. A checked-in fixture would only prove the watch decodes whatever the
fixture says, which is the same blind spot one layer up.

Pair the simulators from the command line — `xcrun simctl pair` exists and
`simctl boot <pair-udid>` brings both up; no GUI is needed. Four things about
that environment cost real time, so they are worth knowing.

The app's preferences live in its sandboxed container, not where `simctl spawn
defaults` writes, and cfprefsd caches them until the device is rebooted. A
simulator configured for Japanese input turns typed ASCII into kana, so drive
text entry through `simctl pbcopy` and paste, or set `AppleKeyboards` to
English first.

The other two both present as the watch sitting on "Loading…" forever, which
looks like a bridge defect and is not one. Read the phone's session state
before assuming anything:

```bash
xcrun simctl spawn <phone-udid> log show --last 2m --style compact \
  --predicate 'process == "Runner"' \
  | grep -oE "reachable: (YES|NO), paired: (YES|NO), appInstalled: (YES|NO)"
```

`appInstalled: NO` after `simctl install` of the iPhone app means the
WatchConnectivity daemon has not noticed the companion that `Runner.app/Watch`
carried onto the paired watch, even though `simctl listapps` on the watch shows
it. Shut both devices down and boot the *pair* again.

An activation with no session state at all — `informing daemon ready for
session state` and then silence, where a healthy launch answers within
milliseconds — is a wedged `wcd`, usually after a pair reboot. Restart it on
both devices and relaunch the phone app:

```bash
xcrun simctl spawn <udid> launchctl kickstart -k system/com.apple.wcd
```

Note that `timeout` is not installed on macOS by default, so a `log stream`
wrapped in it silently produces nothing. Prefer `log show --last`; an empty
result from a `timeout`-wrapped stream is not evidence.
Keep the watch app running while restarting only the iPhone app at least once.
The first snapshot from the restarted projection has a reset sequence, so this
is the boundary test that proves source-aware ordering rather than only ordinary
in-process delivery. Three things need real hardware: notification forwarding
while the phone is locked, the effective background window, and haptics.
