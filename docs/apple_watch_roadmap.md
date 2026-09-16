# Apple Watch Companion Roadmap

Scope, acceptance criteria, and dated evidence for this track.
[Cross-track priorities](roadmap.md#active-focus) remain in the main
roadmap; dated investigation notes below preserve the implementation history.

## Apple Watch Companion Track

The companion lets a person chat and answer a blocked turn from the wrist.
Flutter does not run on watchOS, so it is a SwiftUI target embedded in
`Runner.app` talking to the Flutter app over `WCSession`; the design, and the
reasoning behind treating the watch as a peripheral of this device rather than
as a paired principal, is in `docs/apple_watch_companion.md`. These milestones
use `WATCH<number>` and live here rather than in the Local LLM roadmap because
this is a user-facing surface, not local-LLM execution work.

Current direction (2026-09-16): [WATCH14](#watch14-remote-projects-and-voice-threads)
is `current`. Its first two slices add paired-host project/thread browsing,
confirmed selection, and a compact filtered remote transcript. Destination-bound
dictated instructions are next. WATCH11 completed remote approvals and questions.
WATCH5 remains `current` for its push device matrix, and WATCH4 still needs its
signed-build glance check.

### WATCH1: Companion Bridge, Approvals, And Voice

Status: `done`

Scope:
- `WatchBridgePlugin` (`ios/Runner/AppDelegate.swift`) plus
  `WatchBridgeService` and `WatchSessionNotifier` on the Dart side: project
  `ChatState` outward as a bounded `WatchSnapshot`, apply `sendMessage`,
  `resolveApproval`, `resolveQuestion`, `cancelStreaming`, and
  `requestSnapshot` back onto `ChatNotifier`.
- watchOS app: running-turn glance with cancel, Approve/Deny with haptics, a
  tappable `ask_user_question` option list, and dictation with the reply read
  back by `AVSpeechSynthesizer`.
- Actionable approval notifications as the fallback for when the watch app is
  closed, which iOS forwards to the wrist with no watchOS code involved.

Acceptance criteria (met):
- The watch sees local-origin pending interactions and never one owned by
  another paired Remote Coding device, preserving SEC4.5g.
- A maximal snapshot stays inside the WatchConnectivity payload budget.
- Notification actions appear only when the approval id is known and the kind
  is a plain yes/no; SSH connect and computer-use stay read-only.
- `flutter analyze` clean of new issues, full suite green (8899 tests), and the
  watchOS target builds for `watchsimulator`.

Verification evidence:
- Commits `d3f46c89`, `473826d9`, `6af09bff`, `67955486` on
  `claude/apple-watch-app-features-d25b53`.
- `tool/flutter_test_quiet.sh` (44 new tests under `test/features/watch/` and
  `test/features/chat/.../pending_approval_*`).
- `xcodebuild -target "CavernoWatch Watch App" -sdk watchsimulator26.5` →
  BUILD SUCCEEDED; `AppDelegate.swift` typechecked against the real
  `Flutter.xcframework`.

Next action:
- None. The gap this leaves is that nothing has been run; see WATCH2.

### WATCH2: End-To-End Device Verification

Status: `done`

Scope:
- Run the companion. Every unit test crosses a fake bridge, so the
  `WatchBridgePlugin` <-> `WatchBridgeService` boundary — channel names, payload
  framing, `WCSession` activation and reachability, the embed phase, and
  installability — is the one seam the suite cannot reach.

Evidence (2026-09-01/02, iPhone 17 Pro Max / iOS 26.5 paired with Apple Watch
Series 11 / watchOS 26.5, against a LAN `qwen3.8-27b-vision`):
- The round trip works in both directions. The phone log shows the watch's
  `requestSnapshot` inbound and the answer going out as both
  `updateApplicationContext` and `sendMessageData`.
- A live turn renders on the watch: real conversation title, streaming status
  with elapsed seconds, and the answer arriving as deltas.
- **A pending `ask_user_question` was answered from the wrist.** The options
  rendered on the watch, tapping one resolved it, and the phone's model
  continued with "You chose Startup".
- Packaging is validated. `flutter build ipa --no-codesign` produces an archive
  whose only root product is `Runner.app`, with the companion at
  `Runner.app/Watch/` as a watchOS binary, and both bundles install.

Ten defects surfaced, none of which a green suite could catch:
`Cycle inside Runner` from the embed phase order; a leaked
`__new_conversation__` title sentinel; a missing `sessionReachabilityDidChange`
handler; a missing `SUPPORTED_PLATFORMS` that built the watch against the iOS
SDK; raw `<tool_use>` markup reaching the watch; a latched availability flag;
commands dropped before Dart subscribed; a missing `NSExtension` dictionary; and
absent `CFBundleVersion` on both watch targets. Raw markdown reaching the watch
label and speaker was fixed in the same pass.

Note on approvals: file, shell, and git approvals **cannot arise on iOS**.
`mcp_tool_service.dart` gates all three behind `isDesktopPlatform` by design —
"writing arbitrary paths on a sandboxed mobile OS is both risky and largely
unusable". The watch's approval path therefore serves a desktop-driven turn, or
the kinds mobile does have (BLE, SSH, browser, participant). That is a scoping
fact worth carrying into any further watch work, not a defect.

Environment notes that cost real time:
- Bare `flutter` on this machine is 3.47.0 while `.fvmrc` pins 3.44.8; the wrong
  one rewrites `.dart_tool/package_config.json` and makes a direct
  `xcodebuild archive` fail with `Type 'ui.HitTestResponse' not found`.
- CocoaPods dies on a non-UTF-8 `LANG` while reporting a stale spec repository.
- Simulator pairing needs no GUI (`xcrun simctl pair`), but app preferences live
  in the sandboxed container rather than where `simctl spawn defaults` writes,
  and cfprefsd caches them until the device is rebooted.
- A simulator configured for Japanese input turns typed ASCII into kana; set
  `AppleKeyboards` to English or drive entry through `simctl pbcopy`.

Next action:
- None. Remaining watch work is tracked as WATCH4's signed-build check and
  WATCH6.

### WATCH3: Deferred Watch Command Conversation Binding

Status: `done`

Scope:
- Bind a watch command to the conversation it was composed against.
  `WatchSessionClient.send` falls back to `transferUserInfo` when the phone is
  unreachable, which guarantees delivery but not promptness, and the command
  carries no conversation id. `resolveApproval` degrades safely because
  approval ids are unique and a stale one simply fails to resolve, but a
  `sendMessage` delivered minutes later lands in whichever thread is current
  by then.

Acceptance criteria:
- `sendMessage` carries the `conversationId` the watch was showing, and
  `_handleSendMessage` refuses it with a distinct code when it no longer
  matches, rather than sending into the wrong thread.
- The watch reports the refusal instead of silently dropping the text.
- A focused test covers the mismatch path.

Shipped 2026-09-01 (`1ed84dac`). The watch stamps the conversation it was
showing, and `_handleSendMessage` refuses a mismatch with `conversation_changed`
rather than sending into the wrong thread. An unstamped command is still
accepted, so a watch that has not synced the new app keeps working.

### WATCH4: Glanceable Surfaces And Thread Choice

Status: `done`

Scope:
- A Smart Stack widget showing whether anything is running or waiting, and
  switching which conversation the watch mirrors.

Shipped 2026-09-01 (`d9079b3f`, `9cd06fd7`):
- The snapshot carries the threads the watch may switch to, capped at the
  source, with a flag saying when the list was cut so the watch points at the
  iPhone instead of implying it is complete. `selectConversation` applies the
  choice and refuses a vanished id with its own code.
- `CavernoWatchWidgetExtension` is embedded in the watch app and reads a small
  record through the App Group. The record is counts and a status word, never
  conversation text: a widget renders without anyone opening anything.
- The glance is written only when the value actually changes and the timeline
  is reloaded only then; the timeline itself has no refresh policy. WidgetKit
  budget is finite and re-rendering an identical glance spends it for nothing.
  This is why `transferCurrentComplicationUserInfo` is not used at all — the
  watch app already has the state, so nothing needs to cross from the phone.

Not verified:
- The widget's data path. An unsigned simulator build applies no entitlements,
  so the App Group container does not exist and `UserDefaults(suiteName:)`
  returns nil. The store degrades to a no-op and the widget renders its idle
  state, which is the safe failure but also indistinguishable from "no work
  running". Confirming it needs a signed build.

Next action:
- Check the glance on a signed build. Circular, rectangular, and inline
  accessory families are already supported; this check is for the App Group
  data path, not another family implementation.

### WATCH5: Push-Originated Notification Actions

Status: `current`

Reopened 2026-09-09 by a device check, which found the premise this milestone
had been deferred on was wrong. The local path was believed to cover the
backgrounded phone, with push mattering only for a terminated app. It does not
cover either:

- `ios/Runner/Info.plist` declares `fetch` and `remote-notification`. Neither
  keeps a WebSocket alive, and no mode that would is available for this use.
- `beginBackgroundTask` exists (`AppDelegate.swift`, `com.caverno/background_task`)
  but is called only by `ChatNotifier`, around a turn running *on that device*.
  The Remote Coding client never calls it.

So iOS suspends a backgrounded phone within seconds, the socket is torn down,
no Dart runs, and the approval never arrives — there is nothing for
`remote_coding_mobile_notification_notifier.dart` to raise a notification from.
The person learns nothing until they open the app. Push is not a refinement
here; it is the only path.

Both 2026-09-01 blockers are now closed:

- **The payload existed only as a run completion.** Settled by choosing what
  *not* to send. `RemoteCodingApprovalNotificationPayload` carries an
  allow-listed `approvalKind` and a `hasWarning` boolean, and no command text,
  path, target, or warning prose. The displayed title and body are composed by
  a pure function of the kind, the flag and the host name, so no caller can
  route request data onto a lock screen. Today's warning strings are static
  catalogue entries, but forwarding them would make every future edit to those
  catalogues a privacy decision taken by someone who does not know they are
  taking one. The command is one tap away in the app.
- **The simulator permission circularity** is worked around the same way it
  always could be: raise one local notification in the foreground first, or
  request permission at startup, before testing a push.

Shipped 2026-09-09:

- The relay validates the new shape independently of the sender — its own
  `requireExactKeys` and kind allow-list mirroring `RemoteCodingGrantKinds.all`
  — so a desktop that starts sending command text is rejected rather than
  forwarded. Deployed to `caverno-4977f`, revision 3.
- An approval push takes its own Android channel (`approval_required`, created
  at registration so a terminated-app delivery does not fall to the manifest
  default), collapses on the approval id rather than the event id, and carries
  `aps.category = caverno_approval` so the buttons WATCH10 registered appear.
- The desktop sends from the `approvalRequested` site, gated per device by the
  same `_canResolveInteraction` the snapshot uses: a device that may not answer
  this kind is not told the approval exists.

**Delivery is verified on hardware** (2026-09-09): a desktop approval reached a
backgrounded iPhone on the lock screen. Two environment blockers had to be
cleared first and are worth remembering, because neither produces a useful
error from the app's side — the App Check App Attest provider was never
registered in the Firebase console, so registration failed with a 403
`exchangeAppAttestAttestation` "App attestation failed", and the APNs auth key
was missing, so no push could have arrived even with a correct payload.

The mobile half is built but not yet exercised on a device: both notification
shapes are parsed, a pushed approval reconnects so the snapshot puts it back in
reach, and Approve/Deny sends the id once connected. Local verification is
deliberately not duplicated there — `_handleResolveApproval` re-checks the id
against the current pending list and that device's grant and records a refusal,
so an id the phone cannot verify resolves nothing it should not.

**Answering from the lock screen is verified on hardware** (2026-09-09):
press to resolution in 438ms, with the desktop's dialog closing and the turn
continuing. Two defects stood between the build and that run, and both were
found only on a device:

- **The press never reached Dart.** `AppDelegate` read it from
  `userInfo["payload"]`, where `flutter_local_notifications` stores it for a
  *local* notification. A push has no such key — FCM spreads the relay's data
  fields across `userInfo` itself — so the guard dropped every Approve and
  Deny. The button appeared only to open the app.
- **The answer gave up 25ms too early.** `connectSavedHost` returns once the
  connect is under way, not once it has completed, so checking `isConnected`
  straight afterwards abandoned the press at +233ms while the approval landed
  at +258ms. It now waits for the approval itself, which is the stronger
  condition: one answered elsewhere while the phone slept never arrives and
  nothing is sent.

Neither was visible from the device console, because the file log sink fell
back to `$HOME/.caverno/app_logs` — a desktop path. On iOS `HOME` is the
sandbox root, the first write threw, and the sink latched disabled, so a
device produced no log at all. Fixing that came first; `xcrun devicectl device
copy from --domain-type appDataContainer` then pulls the file without Xcode.

Stale pushed notifications are withdrawn as of the same day, and the first
attempt at it is worth recording because it could not have worked. A push
arrives when the app is not running, so nothing records it and the
conversation-keyed withdrawal cannot reach it; the sweep was therefore hung off
the `pendingApproval` snapshot listener, "the moment the phone learns what is
actually live". On a device the notification did not go away. `ref.listen` fires
on a *change*, and the scenario the notification exists for is exactly the one
in which nothing changes: the phone is suspended while the desktop resolves the
request, and comes back to an empty pending approval that was empty before —
so the listener never fired at all. The same pass found a second defect in it,
that a socket blip clears `pendingApproval` too, which would have swept away the
notification for a request still blocking the desktop.

The fix is that the desktop says so. Only it knows the request is over, and only
a push reaches a suspended phone, so `remote_coding_approval_resolved` is
delivered to the same devices the request went to, by the same
`_canResolveInteraction` check. It is silent by construction — no `notification`
block, `content-available` on APNs, no title or body anywhere on the wire — and
carries an approval id the device was already sent, so it stays inside the
privacy boundary of the request rather than widening it. iOS handles it in
`AppDelegate` before Flutter is involved, which is both what lets it work on a
suspended phone and what keeps it clear of the headless-launch crash class a
background notification action already cost us. The snapshot sweep stays as a
backstop for a silent push iOS declines to deliver, now gated on `isConnected`
and fired on the connection edge as well as on approval changes.

Verified on hardware 2026-09-10, on relay revision 4: the desktop resolves the
request and the lock-screen notification clears itself, with the phone never
having run a line of Dart to notice.

What is left: **the device matrix**, per
`docs/remote_coding_fcm_release_gate.md` — foreground, background, locked and
terminated; tap routing, token rotation, permission denial, registration
revocation, and relay outage isolation. Android has no background message
handler, so a suspended Android phone still waits for the reconnect backstop;
only iOS clears while asleep.

RC2 — retiring the notification-relay QR path — is gated on that matrix.

### WATCH6: Dismiss A Resolved Interaction On The Phone

Status: `done`

Scope:
- Close an approval or question dialog on the phone when it is resolved
  somewhere else — today, the Apple Watch.

Shipped 2026-09-02 (`8caa529c`):
- `ApprovalDialogPresenter` owns both halves. Twelve listeners were repeating
  the same open-on-id-change shape and none of them closed anything; they
  collapse into one helper.
- Dismissal pops by route name, not by popping the top route. `popUntil` with a
  name predicate closes the dialog when it is topmost and does nothing at all
  when something else is, so a mistimed resolution cannot take away the screen
  the user is looking at. A test pushes an unrelated route over an open
  approval sheet and asserts it survives.
- The route name lives beside the approval sheets rather than with the
  presenter: the sheets push the route, and a widget should not import from
  `pages/`.

Verified 2026-09-02 on paired simulators: a pending `ask_user_question`
answered from the wrist closes the phone's sheet, and the model continues from
that answer.

The refactor paid for itself against the line ratchet — `chat_page.dart` fell
38 lines and its library 52 — so both budgets were lowered rather than raised.

Next action:
- None.

### WATCH7: A Message Thread On The Wrist

Status: `done`

Scope:
- Replace the single-answer glance with the transcript a person expects when
  they raise their wrist mid-conversation.

Shipped 2026-09-02:
- `WatchSnapshot` carries `messages` — eight bubbles, 180 runes each with 400
  for the newest, plus a truncation flag. `lastAssistantText` stays for a watch
  that is newer than the phone it is paired with; `TranscriptView` falls back
  to it so that pairing shows one bubble rather than an empty thread. That
  fallback is the path that was actually exercised on the simulator, because
  the paired phone was running the previous build.
- The budget test now measures in a multi-byte script as well as ASCII. Every
  cap counts runes, so the ASCII-only measurement under-reported the payload
  threefold — the transcript is what made that headroom matter.
- A synthesized prompt never becomes a user bubble. Those envelopes are built
  for the request payload and do not reach `ChatState.messages` today; the
  guard is there because if one ever did, the watch would draw a `<tool_use>`
  blob in the person's own voice and read it aloud.
- `StatusView` and `VoiceView` are gone. Their controls live in the compose
  bar's "+" sheet and the navigation bar, so the scroll area holds only the
  exchange. Dictation moved to a `TextFieldLink`, which is what lets the
  collapsed field be drawn as a placeholder capsule.
- `isVoiceMode` follows the "Read replies" switch instead of being sent
  unconditionally, since it shapes the phone's answer for speech. That switch
  is now persisted and defaults off: the speaker moved from a screen you had to
  open onto the screen a raised wrist lands on, and leaving it on by default
  would have made every glance start talking.

Two defects were caught by looking at it rather than by compiling it:
- The transcript opened at the top of the thread. `onAppear` runs before the
  scroll view lays its content out; `defaultScrollAnchor(.bottom)` is the fix.
- An app-wide `.tint` — added to colour the toolbar button — repainted every
  `role: .destructive` button in the accent colour, so Stop and Deny rendered
  as ordinary blue buttons. The tint is now scoped to the one button.

Next action:
- None. Verified 2026-09-04 against a rebuilt iPhone app that sent the actual
  `messages` array to the paired watch rather than exercising the compatibility
  fallback.

### WATCH8: Restart-Safe Snapshot Ordering

Status: `done`

Scope:
- Preserve stale-frame rejection when `updateApplicationContext` and
  `sendMessage` arrive out of order, while accepting the first frame after the
  iPhone process restarts and its per-process sequence returns to one.

Completed 2026-09-04:
- `WatchSnapshot` now carries a random source instance id and the source start
  time. Sequence numbers remain small and monotonic within that source.
- `WatchSnapshotCursor` selects a newer source by start time, orders frames from
  that source by sequence, and rejects frames from retired sources. A legacy
  source-less phone remains compatible until a source-aware frame is accepted;
  source-less frames are rejected after that point so they cannot resurrect a
  resolved approval.
- The paired-simulator check used matching current iPhone and watch builds. An
  actual user message and streaming state arrived through the native/Dart
  bridge. The Watch process then stayed alive while only the iPhone app
  restarted; the reset-sequence frame replaced the old 38-second streaming
  state with the restarted app's current idle conversation.

Verification evidence:
- `tool/codex_verify.sh --no-codegen --test test/features/watch/` passed 61
  tests and all analyzers.
- `tool/watch_snapshot_cursor_smoke.swift` accepted old-source sequence 8, rejected 7,
  accepted new-source sequence 1, rejected delayed old-source sequence 9, and
  accepted new-source sequence 2.
- The Watch simulator target and the full iPhone simulator app with the embedded
  companion both built successfully.

Next action:
- None. WATCH4's signed-build App Group check remains the only open Watch
  verification item. (WATCH5's push approval contract was defined and deployed
  on 2026-09-09; that milestone is `current`, not blocked.)

### WATCH9: Goal State On The Wrist

Status: `done`

The companion mirrors `ChatState` and the conversation list, and nothing else.
A coding thread therefore reaches the wrist as bubbles with none of the state
that makes it a coding thread. The gap that matters is
`ConversationGoalStatus.awaitingConfirmation`: the harness has stopped
scheduling and is asking whether the objective was met, and `_statusFor`
renders that as `WatchTurnStatus.idle` — indistinguishable from finished. It is
a wrist-shaped decision the wrist cannot see. The measured behaviour behind it
is that the model does not volunteer `update_goal` but answers when asked, so
the ask is the whole mechanism.

Scope:
- Carry `workspaceMode` and a projected goal (`objective`, `status`,
  `completionSummary`, `blockedReason`) in `WatchSnapshot`, capped like the
  existing title and detail fields and counted in runes.
- Treat `awaitingConfirmation` as an attention state: its own
  `WatchTurnStatus`, included in `needsAttention` so the transcript's attention
  button, the glance, and the widget agree.
- Add `resolveGoal` (complete / keep going) to `WatchCommand.allowed`, routed
  through the same path the phone's goal menu uses rather than a second writer
  — `validationStatus` already has three writers and does not need a fourth
  shape of the problem.
- Label the thread picker with each thread's workspace mode.
  `ConversationsState.conversations` is unfiltered, so chat, coding, and
  routine threads are presented today as if they were the same kind of thing.

Acceptance criteria:
- A goal awaiting confirmation raises the same attention affordance an approval
  does, and answering it from the wrist moves the goal exactly as the phone's
  menu would.
- A blocked goal names its blocker instead of reading as idle.
- A maximal snapshot carrying a goal stays inside
  `watchSnapshotMaxEncodedBytes`, measured in a multi-byte script. The
  transcript already spends most of that budget, so this is the gate, not a
  formality.
- An older watch build ignores the new fields; an older phone leaves the goal
  affordance absent rather than empty, the way `lastAssistantText` already
  covers the reverse skew.

Dependencies:
- None beyond the shipped companion.

Prerequisite, completed 2026-09-05:
- The headroom re-measurement asked for here found a live defect rather than a
  number. Rune caps are a screen constraint and `watchSnapshotMaxEncodedBytes`
  is a transport one, and a maximal frame encoded to 36% of the budget in
  English, 89% in Japanese and **116% in emoji**. The two budget tests covered
  only the one-byte and three-byte cases, so the overrun was invisible.
  `WCSession` refuses an oversized dictionary instead of clipping it, and the
  refusal is only an `NSLog`, so the symptom would have been a watch silently
  stuck on stale state.
- `WatchSnapshot.toJson` now enforces the budget by walking a ladder of
  progressively smaller caps and sending the first frame that fits, shedding
  the thread picker, then transcript depth, then `lastAssistantText`, and
  shrinking the pending decision last. The emoji frame now encodes to 91%.
  `TranscriptView` opens the thread picker on `conversationsTruncated` alone,
  so shedding the list no longer removes the "More threads on iPhone" notice
  with it.
- Headroom for this milestone: 1,755 bytes in a maximal Japanese frame. A goal
  projection larger than that does not fail — it costs the thread picker on
  that frame — but sizing the new fields to fit is the point of measuring.

Completed 2026-09-05:
- `WatchSnapshot` carries `workspaceMode` and a projected `WatchGoal`
  (`objective`, `status`, `completionSummary`, `blockedReason`), each capped at
  `watchSnapshotGoalTextLimit` and counted in runes. A disabled or
  objective-less goal is not projected at all, because an empty affordance on a
  wrist is worse than none.
- `WatchTurnStatus.awaitingGoalConfirmation` is its own status and is counted
  in `needsAttention`, so the transcript's attention button, the glance and the
  widget agree without any of them special-casing it — the widget already
  renders "Needs you" from that flag.
- `resolveGoal` routes through `markCurrentGoalStatus`, the same writer the
  phone's goal menu uses. It is stamped with the thread it was composed against
  (WATCH3, applied to goals) and refused with `goal_not_awaiting` when the goal
  has moved on, so a seconds-old frame cannot close a goal that resumed.
- `GoalView` shows the harness's `completionSummary` beside the choice and
  waits for the correlated result the way the approval and question screens do.
  A blocked goal names its blocker in the transcript footer.
- The thread picker labels each thread's workspace mode. Mode and goal status
  travel as strings, so a watch older than its phone degrades to showing less
  rather than failing to decode the frame.

Verification evidence:
- `tool/flutter_test_quiet.sh test/features/watch/` passed 79 tests, up from
  61; the full suite passed 9270 and `flutter analyze` is clean.
- A maximal frame carrying a goal encodes to 40.1% of the budget in English,
  **97.5% in Japanese** — still the full projection, which is the acceptance
  criterion — and 64.3% in emoji after the ladder sheds the thread list and
  half the transcript. The budget test covers all three.
- `xcodebuild -target "CavernoWatch Watch App"` succeeded and the snapshot
  cursor smoke test still passes.

Follow-up, completed 2026-09-05:
- `tool/watch_wire_contract_smoke.sh` closes the cheaper half of the bridge
  gap. The Dart tests proved what the phone writes and `xcodebuild` proved the
  watch compiles; nothing proved the two agree, so a renamed key or a status
  the watch does not name would have arrived as a default value in silence. It
  decodes a frame generated by the Dart encoder — not a checked-in fixture,
  which would only prove the watch decodes whatever the fixture says — and
  checks `WatchCommandType` against `WatchCommand.allowed` in both directions.
- Verified by mutation, not by passing: renaming a snapshot key, renaming a
  goal key, removing `resolveGoal` from the watch's command list, and adding a
  status the watch does not name each fail it with a named diagnostic.

Partial paired-simulator run, 2026-09-05:
- The WATCH9 build was installed on an iPhone 17 Pro Max / Watch Series 11 pair
  and the bridge itself was proved end to end: the watch rendered a real frame
  projected from the phone's `ChatState`, with the empty-thread state, the
  thread-picker affordance, and the compose bar. The `MethodChannel` /
  `WCSession` path therefore works in this build.
- The goal path — the attention button, `GoalView`, and `resolveGoal` moving a
  goal — was **not** reached. Driving the phone's compose bar through the
  simulator control tool would not fire the send button, so `/goal` never
  submitted and no goal ever entered `awaitingConfirmation`.
- Two environment traps cost most of that session and are now written up in
  `docs/apple_watch_companion.md`: `appInstalled: NO` until the *pair* is
  rebooted, and a wedged `wcd` that activates and never answers with a session
  state. Both present as the watch sitting on "Loading…" and neither is a
  bridge defect.

Reachability gap found by that run, 2026-09-05:
- Trying to set a goal on the phone answered "Goals are available in coding
  threads." `/goal` is gated on `isCodingWorkspace`
  (`slash_command_action_coordinator.dart`), and on iOS the coding workspace
  always renders `RemoteCodingPage` — `isMobileRemoteCoding` in
  `chat_page.dart` is `isCodingWorkspace && isRemoteCodingMobilePlatform()`,
  and that predicate is simply `Platform.isAndroid || Platform.isIOS`.
- So a local iOS thread can never carry a goal, and `_goalFor` reads exactly
  that: `conversationsNotifierProvider.currentConversation.goal`. **The goal
  projection, the `awaitingGoalConfirmation` attention state, and `resolveGoal`
  cannot fire on the only platform the companion ships to.**
- This is WATCH10's defect class, not a coding error: the machinery is right
  and points at the wrong source. The goal a phone user actually has is on the
  *desktop* they are driving through Remote Coding, which is
  `RemoteCodingClientState` — the second input source WATCH11 exists to add.
- What does survive on iOS: `workspaceMode` in the frame, the thread picker's
  mode labels for chat and routine threads, and the payload budget work the
  measurement produced. The goal code stays rather than being reverted: it is
  tested, it is the shape WATCH11 needs, and it fires the moment a goal reaches
  `ChatState`.

Next action:
- Fold the goal source into WATCH11 rather than re-running this on simulators.
  Verifying `resolveGoal` against a source that cannot exist on iOS proves
  nothing.
- Haptics on the new attention transition and notification forwarding still
  need real hardware, as they do for WATCH1.
- Note for whoever adds the next wire field: rung 0 is now 97.5% full in
  Japanese, so the next field pushes a wide frame onto the shedding ladder
  rather than fitting beside the thread picker.

### WATCH10: Remote Coding Approvals As Notifications

Status: `done`, and its premise was wrong

**The correction, found by running it.** This milestone said a Mac waiting on
`dart analyze` "reaches the wrist through no path at all: not the companion,
and not a notification either. Fix the wiring, then fix the sentence." The
wiring was never the reason. `RemoteCodingServerNotifier._pendingRemoteApproval`
puts an approval in the snapshot only when `_canResolveInteraction` passes, and
that requires `origin == ChatInteractionOrigin.remote` with an owner matching
the authenticated device. A turn started on the desktop itself is
`origin: local`, so the approval is *deliberately withheld* from the paired
phone. That is SEC4.5g doing exactly what it was built to do.

The phone's own log said so in one line — `pendingApproval=none` on a connected
snapshot — after three rounds of guessing at the notification code, which was
never the problem.

**Two consequences.** This milestone covers approvals from turns the *phone*
started: those carry `origin: remote` with the phone as owner, reach the
snapshot, and raise the notification. That is a real case — drive a coding turn
from the phone, move to another screen, get told when it blocks — and it is
what to verify.

And no transport fixes the desktop-initiated case. A push contract (WATCH5)
would carry only what the phone is already entitled to see, so the option of
"solve it with push" does not exist. Deciding whether the owner's own paired
phone may see their desktop's approval is a security-policy question, and it is
WATCH13.

The Remote Coding server is desktop-only
(`Platform.isMacOS || isLinux || isWindows`); mobile is client-only. A blocked
desktop turn therefore lives in `RemoteCodingClientState` on the phone, and
nothing outside `features/remote_coding/` reads that provider —
`remoteCodingClientProvider` has three call sites, none of them the watch and
none of them `ChatNotifier`. `showPendingApprovalNotification` is called only
from `ChatNotifier`. The result is that a Mac waiting on `dart analyze` reaches
the wrist through no path at all: not the companion, and not a notification
either.

That contradicts `docs/apple_watch_companion.md`, which reasons that since
file, shell, and git approvals cannot arise on iOS, "the watch's approval path
therefore serves a desktop-driven turn". The intent is written down; the wiring
is not there. Fix the wiring, then fix the sentence.

This is not WATCH5. WATCH5 was blocked because no *push* carried an approval;
it no longer is, as of 2026-09-09. This path needs no push: the client holds a
live WebSocket while connected and the approval arrives on it.

Read "while connected" strictly. The 2026-09-09 device check found that an iOS
app loses the socket within seconds of being backgrounded, so this path covers
the foreground and nothing else — which is why WATCH5 was reopened rather than
left closed by this one. The notification is raised locally, and iOS
forwards it and its actions to the paired watch with no watchOS code involved
— the same mechanism WATCH1 already relies on.

Scope:
- Raise the actionable approval notification from the Remote Coding client when
  a pending approval arrives, reusing `showPendingApprovalNotification` and the
  `RemoteCodingNotificationReceiptStore` dedup that terminal notifications
  already use.
- Route Approve/Deny back through `RemoteCodingClientNotifier.resolveApproval`.
  `approvalNotificationActionsProvider` resolves only against
  `chatNotifierProvider`, so an action carrying a remote approval id resolves
  nothing at all today, silently.
- Name the host in the body. `RemoteCodingHost` carries the server name, and
  "wants to run: dart analyze" without saying which machine will run it is
  exactly the failure this must not ship.
- Suppress the notification while the Remote Coding page is foregrounded,
  matching the existing terminal-notification behaviour.

Acceptance criteria:
- All three remote approval kinds — `file`, `localCommand`, `gitCommand` — are
  bare yes/no decisions, so Approve/Deny is a truthful answer for each and the
  notification carries the actions for all three.
- The action resolves by approval id against the owning notifier. A stale id
  fails visibly rather than resolving whatever else is pending.
- Resolving on the desktop leaves no orphan notification on the phone.

Dependencies:
- None. Independent of WATCH9 and a prerequisite for WATCH11.

Reachability confirmed before building, 2026-09-05:
- WATCH9 shipped a feature whose source could not exist on iOS, so this one was
  checked first. `RemoteCodingClientState.pendingApproval` is populated from
  the WebSocket snapshot on the client, `RemoteCodingClientNotifier`
  `.resolveApproval` exists, `showPendingApprovalNotification` takes a
  `NotificationService` and a summary rather than anything chat-shaped, and
  `RemoteCodingMobileNotificationNotifier` already lives app-wide on mobile
  through `RemoteCodingNotificationNavigationShell` in `main.dart`. Every input
  exists on the shipping platform.

Built 2026-09-05:
- The approval notification is raised from
  `RemoteCodingMobileNotificationNotifier`, which already listens to the client
  for terminal notifications and holds the notification service.
- Approve/Deny routes by id to the owning notifier: chat first — which reports
  whether it held the request — then the Remote Coding client when the pending
  approval's id matches, and an id nothing owns is logged rather than applied
  to whatever else is pending.
- The host name is the notification title and appears in the body, so
  "wants to run: dart analyze" always says which machine will run it.
- The notification is suppressed while the Remote Coding page is on screen,
  since that page raises its own approval sheet. The page registers its own
  visibility: the notifier cannot infer "the user is looking at this" from any
  state it holds. This matches `ChatNotifier`, which notifies only for a thread
  other than the visible one.
- Two defects in the suppression signal, both found by Leg A rather than by
  any test. The second is the one that mattered: `dispose` read `ref`, which
  throws a `StateError` there, so the flag was never cleared and every later
  approval was suppressed on every screen for the rest of the session — and
  `dispose` aborted before releasing the page's controllers. The notifier is
  now captured while the page is mounted. A stuck suppression flag silences the
  whole feature, so it has a widget test of its own that fails against the
  defective form.
- Suppression also needs the app foregrounded as well as the page mounted:
  backgrounding does not dispose the page, so a phone left on the Coding tab —
  the tab a Remote Coding user is obviously on, and the exact state the
  notification exists to serve — was silenced by its own suppression. Mounted
  and looked-at are different facts and only their conjunction is a reason to
  stay quiet.
- The notification is withdrawn when the approval leaves the client state, so
  answering on the desktop does not leave buttons on the phone that resolve
  nothing. `NotificationService` had no cancel at all; the new one derives its
  id exactly the way the raise does, so one thread's withdrawal leaves
  another's notification alone.

Two corrections to this milestone's own plan:
- It said to reuse `RemoteCodingNotificationReceiptStore` for dedup. Its keys
  are frozen to `^[A-Za-z0-9_-]{1,256}$`, which an approval id need not match,
  and its week-long persistence exists because a *push* can be redelivered
  after a restart. A WebSocket approval cannot outlive its connection, so dedup
  is an in-memory set of raised ids.
- It said suppression would match "the existing terminal-notification
  behaviour". There is no such behaviour: the terminal path dedups and skips
  when relay push is enabled, and never checks whether anything is on screen.

Verification evidence:
- `tool/flutter_test_quiet.sh` passed 9283 tests, up from 9270; the new cases
  cover the raise, host naming, all three kinds being answerable, dedup across
  a reconnect, page suppression, withdrawal when the desktop answers, and the
  action routing to the owning notifier.
- `flutter analyze` clean.

The phone-initiated chain, checked link by link rather than assumed — the step
skipped twice already:
- `_handleSendMessage` calls `sendMessage(origin: remote, remoteDeviceId:
  client.deviceId)`, which sets `_activeInteractionOrigin` and
  `_activeRemoteDeviceId` for the turn.
- `PendingLocalCommand`, `PendingFileOperation` and `PendingGitCommand` are all
  constructed with `origin: _activeInteractionOrigin` and
  `remoteDeviceId: _activeRemoteDeviceId`, so the approval inherits the turn's
  owner rather than defaulting to local.
- `_canResolveInteraction` therefore passes, `_pendingRemoteApproval` puts the
  approval in the snapshot, and the client's listener raises the notification.

Verified live, 2026-09-05, Mac server and a real iPhone client:
- The banner appears. A `localCommand` approval from a phone-initiated turn
  raised a notification titled with the host and shown while the app was
  foregrounded on another screen.
- It took four defects to get there, all of them invisible from the app itself:
  suppression that a mounted-but-backgrounded page never cleared, a `dispose`
  that threw before clearing it at all, a permission latch that recorded the
  attempt rather than the answer, and Firebase owning
  `UNUserNotificationCenter.delegate` and answering
  `UNNotificationPresentationOptionNone` for every foreground notification.
- The first banner then showed the fifth: it read "wants to run: Local Command
  Approval" instead of naming the command. The wire model puts the kind's label
  in `title` and the command in `detail`, and mapping the fields across
  verbatim produced exactly the notification WATCH1 says must not ship. Fixed
  and covered per kind; the banner now reads "MacBook-Pro-3.local wants to run:
  fvm dart analyze."
- Approve/Deny are present on the notification, on the lock screen and in
  app, and the log agrees: `actionable=true category=caverno_approval`. They
  appear on long press rather than in the collapsed list, which is how iOS
  renders every notification action and not a defect.
- Approve pressed on the notification resolves the turn on the desktop. The
  whole chain is in one log: `raising for <id> on "MacBook-Pro-3.local"` →
  `actionable=true category=caverno_approval` → `scene action
  actionId=caverno_approve` → `sent to the desktop (approved=true)` →
  `withdrawing the notification; the approval is gone`. The withdrawal is the
  desktop's own answer coming back: the approval left the server's snapshot
  because the resolution landed there.
- Seven defects stood between the first build and that log, and every one of
  them presented as silence — no notification, or a button that did nothing.
  Three were suppression and lifecycle mistakes of this milestone's own making;
  two were the notification service's (a permission latch on the attempt rather
  than the answer, and a dropped action identifier on a cold launch); one was
  Firebase owning `UNUserNotificationCenter.delegate`; and the last was
  `UIApplicationSceneManifest`, where `flutter_local_notifications` registers
  only as an application delegate and never sees a scene-delivered action.
  None was diagnosable until the path logged its own decisions and the device
  log was read beside them.
- Still unproven: that a paired watch receives the forwarded actions. That is
  iOS forwarding, the mechanism WATCH1 already relies on.

Earlier evidence:
- A `localCommand` approval from a phone-initiated turn reached the phone and
  raised the notification naming the host, and the notification was withdrawn
  when the approval was resolved. The phone's log carried the whole path:
  `snapshot: connected, pendingApproval=<id>` → `approval <id> (localCommand)
  is pending` → `raising for <id> on "MacBook-Pro-3.local"` → `withdrawing the
  notification ...; the approval is gone`.
- What that log proves is that the raise and the withdrawal were called. It
  does not prove the notification was visible on the lock screen or that
  Approve/Deny resolved the turn — those need a person to say what they saw and
  which surface they answered on. Recorded as still open rather than assumed.

Next action:
- Confirm the two things the log cannot: that the notification appears, and
  that answering it from the notification (not the Mac) moves the desktop turn.
- Then add the paired watch, which only confirms iOS forwarding — a mechanism
  WATCH1 already proved.
- This worktree cannot build the desktop app at all — it holds no
  `.macos-canonical` sentinel — so the Mac side runs from the canonical
  checkout. It needs no change from this branch.

### WATCH11: Remote Coding Interactions In The Companion

Status: `done`

Current summary: approvals and questions shipped on 2026-09-06 with source
selection, host labels, and owner-routed resolution. SA-26 settled inherited
phone authority. The proposed remote goal surface was withdrawn, as recorded
below; it is not unfinished WATCH11 scope. WATCH14 now owns remote project and
thread browsing, compact transcripts, and dictated instructions. The local-only
transcript below describes this completed slice, not the future product limit.

Scope:
- Give `WatchSessionNotifier` a second input source alongside
  `chatNotifierProvider`: `remoteCodingClientProvider`.
- Decide precedence when a local interaction and a remote one block at the same
  time. One screen, one decision; `WatchApprovalMapper._byPriority` already
  ranks by consequence and the same principle has to extend across sources.
- Add a source label to `WatchApproval` carrying the server name, and render
  it. Approving a shell command without knowing which machine runs it is the
  failure mode this milestone exists to avoid, so the label is load-bearing
  rather than decoration.
- Route `resolveApproval` and `resolveQuestion` to the owning notifier, keeping
  the existing correlated-result wait so a failure stays on the screen where it
  happened.
- Keep the transcript local-only in this slice. Two transcripts on one wrist
  screen is a separate design problem, and the payload budget cannot carry both.

Trust model — a new judgement, not a restatement:
- SEC4.5g scopes a Remote Coding interaction to the paired device that started
  the turn. That device is the iPhone, and WATCH1 established the watch as a
  peripheral of this device rather than a principal of its own. Surfacing the
  phone's own remote-coding approval on the phone's own watch therefore does
  not widen the principal set.
- It is not a relaxation of `WatchApprovalMapper`'s `isOwnedByRemoteDevice`
  exclusion. That guard covers the desktop-as-server case and cannot fire on
  iOS, where `ChatState` never holds a remote-origin approval. Reaching remote
  coding means adding a second source, not widening the existing gate — and
  conflating the two would quietly undo SEC4.5g on desktop.
- Write the reading into `docs/apple_watch_companion.md` and record it beside
  SA-24 in `docs/security_followup_review_2026-08-24.md` before shipping.

Acceptance criteria:
- A pending approval on the connected desktop renders on the wrist naming its
  host, and answering it resolves that request over the WebSocket.
- A local interaction and a remote one pending together produce one screen with
  a decided, tested precedence.
- The snapshot carrying remote fields stays inside the payload budget in a
  multi-byte script.
- A remote interaction owned by a *different* paired device is still excluded.

Dependencies:
- WATCH10, which proves the client-side wiring and the host naming with far
  less machinery.

Added 2026-09-05, withdrawn 2026-09-06 — the goal:
- The plan was to point WATCH9's goal machinery at `remoteCodingClientProvider`
  alongside the approvals, since it has a wire model, an attention state, a
  confirm screen and a resolve path, and no source on iOS. That is dropped.
- `awaitingConfirmation` arises in two places
  (`turn_goal_completion_finalizer.dart`): the model reported completion with no
  mechanical gap found, or the goal hit its budget cap. Both are unattended-run
  moments, which is a real argument for the wrist — goals do get stuck, and one
  measured log burned 163k tokens on `update_goal` refused five times.
- Against it, three things and one alternative. The evidence rule that keeps
  WATCH12 `later` applies here too, and harder: the goal screen has never once
  run on iOS, so there is no usage at all to argue from. The cost is a goal
  field on the Remote Coding wire, which was then the same privacy-boundary
  change that blocked WATCH5. (WATCH5 made its own on 2026-09-09, by carrying an
  allow-listed kind and a boolean rather than any prose; a goal field would not
  get off that lightly.) And confirming completion closes a goal that may not be
  done, from the surface with the least context — the screen's own comment
  calls that "confirming blind".
- The alternative costs nothing new: **questions now reach the wrist** (WATCH11,
  2026-09-06). A desktop that wants a completion confirmed can ask for it as an
  `ask_user_question`, with options, over the path that already exists. That
  keeps "something needs your answer" as one mechanism rather than two, and it
  is where this should go if unattended goal confirmation ever earns a wrist.

Settled 2026-09-06 by SA-26 — what the wrist may do with a remote card:
- The watch inherits **exactly** the phone's authority and no more. It is the
  phone's peripheral, so a kind this phone has been granted is actionable on
  the wrist, and one it has not is read-only with the reason on screen.
- `isSimpleDecision` still applies on top: SSH credentials and computer-use
  smoke arming need a gesture no compact surface can represent honestly, so
  they stay read-only even on a fully granted device.
- That removes the open trust question this milestone was carrying. The
  principal set does not widen — the watch adds no authority of its own, which
  is the same reason SA-24 accepted it in the first place.

Next action:
- No remaining implementation in this scope. WATCH5 owns the outstanding push
  device matrix. Continue the requested remote conversation UI under WATCH14;
  WATCH12 remains separately gated on evidence of a missing detailed readout.

### WATCH12: Running Tool And Verification Readout

Status: `later`

Scope clarification (2026-09-14): WATCH14 includes a short working/waiting/error
status while hiding tool calls and raw results from the conversation. That does
not promote this detailed tool/verification readout; it remains optional future
work and must not crowd the default wrist transcript.

Scope:
- Say what a turn is doing rather than only that it is streaming: the tool or
  command in flight, and whether the thread's `verificationGeneration` is
  behind its `mutationGeneration`.

Why this is `later` and not `next`:
- There is no general active-tool field to project. `activeToolName` lives on
  `ParticipantTurnRuntime` and is set only for participant turns, so this needs
  a new `ChatState` field, not a projection of an existing one.
- Nothing has shown that a wrist wants it. The evidence rule applies: build
  what a real session proves is missing, not what a status screen could
  plausibly hold.

Next action:
- None. Revisit if WATCH9 or WATCH11 usage shows the glance is
  under-informative.

### WATCH13: Desktop-Equivalent Authority On A Paired Phone

Status: `done`

A blocked desktop turn does not reach the phone, and WATCH10 proved the reason
is policy rather than plumbing: `_canResolveInteraction` requires
`origin == remote` with a matching owner, so an approval raised by a turn
started at the Mac is withheld from every paired device — including the phone
belonging to the same person sitting at that Mac.

That gate exists for a good reason. SEC4.5g stops paired device A from seeing
and resolving paired device B's turn. The question this milestone asks is
narrower and was never decided: may the *desktop's own* pending approval be
shown to a device that person has paired to it?

Why it is not obvious:
- The phone is not the principal that started the turn, so widening the gate
  weakens exactly the property SEC4.5g established.
- But WATCH1 already reasoned that the watch is a peripheral of the phone
  rather than a principal, and the same argument may or may not extend one hop
  further — from "the phone's own approvals on the phone's own watch" to "the
  desktop's own approvals on a phone the desktop's owner paired". Pairing is
  authenticated and revocable, which is an argument for; a stolen unlocked
  phone now resolves the desktop's shell commands, which is an argument
  against.
- Any widening also has to say what happens with two paired phones, and
  whether a *resolution* may come back from a device that did not start the
  turn even if a *view* may.

First decision, 2026-09-06, **withdrawn the same day**: SA-25 said a paired
device may see the desktop's own approval and may not resolve one. Its argument
was that the phone would gain authority iOS structurally cannot hold, since
file, shell, and git approvals are gated behind `isDesktopPlatform`.

That is true about iOS and beside the point, because the turn does not run on
the phone. `_handleSendMessage` hands the message to the **desktop's**
`ChatNotifier` with `origin: remote` and the phone's device id, and that turn
carries the desktop's whole tool catalogue. A phone can already make the Mac
run an arbitrary shell command: ask for it, then approve the request it
provokes. Pairing already confers the desktop's execution authority, so
answering a desktop-origin approval adds no new class of it — and is strictly
weaker than `sendMessage`, since the phone answers a question rather than
authoring the request.

Decision, settled 2026-09-06 as **SA-26** in
`docs/security_followup_review_2026-08-24.md`: **a paired device may hold
desktop-equivalent authority over threads that already exist**, granted per
device by the desktop owner, bound to what the phone displayed, and audited.
Project creation stays off the phone. Cross-device isolation is untouched:
paired device A still may not touch paired device B's turn.

The controls that make it safe act at the moment of consequence rather than on
device identity — device-local authentication against a stolen unlocked phone,
a displayed-body digest against blind approval, a per-kind grant against the
confused deputy, and an audit trail on the desktop.

Three slices, in this order:
1. **Carry every approval kind for turns the phone already owns.** Eleven
   kinds exist; four carry `origin` / `remoteDeviceId` and the wire enum knows
   three. A remote turn that raises an SSH, browser, BLE, serial, computer-use
   or participant-tool approval blocks the desktop with nothing on the phone
   and nobody able to answer. This is a live defect in the case SEC4.5g
   already permits and carries no policy question. Thread origin through the
   remaining pending types, and project through the existing
   `describePendingApproval` flattener instead of the bespoke three-kind
   switch in `_pendingRemoteApproval`.
2. **Make the decision surface carry the whole question.** Written first as a
   displayed-body digest; measurement retired that before it was built, since
   an approval id is a UUID over immutable fields and the desktop resolves by
   id, so a different body is already a different id. The half that was
   actually broken: the notification body is built from `title`, so a
   destructive shell command reached the lock screen and the wrist with
   Approve/Deny and no warning beside it. The summary now carries `warning`
   and the body states it. Prerequisite for slice 3, not a parallel nicety.
3. **Grant per device.** Shipped 2026-09-06 as
   `RemoteCodingPairedDevice.desktopOriginKinds`, empty by default and edited
   per device from Remote Coding settings. `_canResolveInteraction` now
   switches on origin and answers the two cases separately, so SEC4.5g's
   remote-origin rule is untouched. Per kind, not one switch: answering a
   question the Mac asked is not the act of approving a shell command it wants
   to run.

Device-local authentication and the desktop audit surface follow; neither
gates the three above.

Dependencies:
- None. WATCH10 supplies the notification path.

Also shipped 2026-09-06, SA-26's T4: the desktop records every decision a
paired device takes — device, kind, body, outcome, and whether the turn was one
that device started or one this desktop started under a grant — and lists them
in Remote Coding settings. Refusals are recorded with their reason, since a
misconfigured grant leaves no other trace. The log lives under its own
preferences key rather than in the settings the support packet is built from,
so command text cannot leave the machine with a diagnostics copy.

The same pass found that the snapshot's change listener still watched three
approval kinds of eleven, so a turn blocking on an SSH or browser approval
changed nothing a client could observe until something else broadcast.

Verified on hardware 2026-09-06. Part 1 of
`docs/watch_remote_coding_device_verification_2026-09-06.md` was walked end to
end: an ungranted desktop-origin approval was withheld while the Mac sat blocked
on it, and a granted one arrived, was answered from the phone, and closed the
desktop's own sheet. Read-only rendering, grant withdrawal, and revocation all
behaved as designed. Four defects surfaced on the way and were fixed — pairing
was camera-only so no simulator could reach any of this, a declined command
looked like a disconnection, sheets were never taken away when the interaction
stopped being pending, and the read-only sheet had no way out.

Closed 2026-09-06 after a second hardware session took the remaining two
observations. WATCH11's card was verified on the wrist for both origins: a
desktop-origin approval, granted, reached the watch labelled
`MacBook-Pro-3.local` and Approve from the wrist ran it on the Mac; with the
grant withdrawn, the same desktop-started turn reached neither the phone nor the
wrist. The grant is therefore what opens that path, and
`_canResolveInteraction`'s local-origin branch refuses on a device the way its
unit tests say it does.

That session also found two defects no test could have: every attention
indicator on the watch was unreachable whenever the phone had more than one
thread (four `ToolbarItem`s sharing `.topBarTrailing`, which watchOS renders one
of), and the compose bar was clipped by the display edge. Both are recorded in
`docs/watch_remote_coding_device_verification_2026-09-06.md`.

Open follow-up, tracked as SA-26's T1 rather than a WATCH13 slice:
device-local authentication before a mutating resolution. It is unstarted —
`local_auth` is not a dependency — and WATCH11 gave it a new question to answer
first. `WatchSessionNotifier._handleResolveApproval` calls
`RemoteCodingClientNotifier.resolveApproval` directly, so an authentication gate
placed on the phone's approval sheet would not be on the path a wrist tap takes.
Either the gate lives in the client notifier where both surfaces cross it, or
the watch is a documented exemption on the argument that watchOS wrist-detection
already authenticates it — which is only true when the user has set a watch
passcode.

Next action:
- Part 2 is down to one gate. `support_packet_review` and
  `multi_device_household` closed on 2026-09-06 with two paired simulators
  against the real host — the household gate checks server-side authorization,
  not hardware, and both of its interesting observations were taken with the
  two connected at once. `resilience_soak` genuinely needs real devices: it
  names iOS *and Android* thirty-minute LAN soaks, desktop sleep/wake, and an
  IP change. Evidence in `docs/evidence/`.
- SA-26's T1 remains a decision rather than a continuation: device-local
  authentication before a mutating resolution needs a `local_auth` dependency
  and an iOS usage description.

### WATCH14: Remote Projects And Voice Threads

Status: `current`

Goal and user-visible behavior (requested 2026-09-14):
- Browse the projects and existing threads of the host paired with the iPhone.
- Open a remote thread, read its recent conversation, and dictate instructions
  into that same thread using the Watch's existing system input control.
- Optimize the thread for the small screen. Navigation, conversation, and
  pending decisions each get an appropriate surface rather than copying the
  iPhone's entire Remote Coding page.

Pre-implementation baseline (local main `ae94a5da4`, 2026-09-14):
- `RemoteCodingClientState` already holds the paired host, `projects`, `threads`,
  `messages`, selected IDs, and loading state. The iPhone's remote drawer already
  groups threads by project.
- `WatchSessionNotifier.buildSnapshot` still takes its thread list from local
  `ConversationsState` and its transcript from local `ChatState`. Its remote
  listener reacts only to pending approval/question IDs. WATCH11 contributes
  those interactions, not remote navigation or conversation updates.
- Watch `selectConversation`, `sendMessage`, and `cancelStreaming` still target
  local notifiers. `ComposeBar` already accepts system Dictation through
  `TextFieldLink`; the missing work is remote routing and response projection.
- The remote client's `_sendCommand` returns after writing to the socket, and
  can return without sending when disconnected. The server's `sendMessage`
  currently uses the desktop's active conversation. Neither is sufficient
  evidence that a Watch instruction reached the thread displayed when composed.

Small-screen UI contract:

| Surface | Show | Omit or defer |
|---|---|---|
| Entry/navigation | An explicit choice between local chats and Remote Coding; the paired host's name and connection state | Pairing credentials or a separate Watch pairing flow |
| Projects | Project names in a vertical list; tap to browse that project's threads | Full filesystem paths and dashboard statistics |
| Threads | Thread title, selected state, and a compact activity/waiting indicator where available | Tool history, task trees, token usage, and verification counters |
| Conversation | One selected thread; user instructions and assistant reply text in bubbles; short working/waiting/error state | Tool-call cards, arguments, raw tool results, reasoning blocks, internal tool markup, and injected harness messages |
| Long content | Bounded recent history, compact text, and an explicit indication that more content is on iPhone | Full diffs, large code blocks, terminal output, or automatic LLM summarization |
| Input | A pinned system-input/Dictation control, visible destination context, send feedback, and Stop while that thread is running | A custom recorder or continuous hands-free/barge-in loop |
| Attention | One reachable approval/question affordance opening the existing decision screen, with host, request, warning, and required choices | Tool activity mixed into the transcript; hiding decision details needed to answer safely |

The visibility rule applies to the Watch projection and speech output. It does
not remove tool evidence from the desktop/iPhone history or change the model's
tool execution. Preserve an assistant's useful text when the same message also
contains a tool call; omit only the tool portion. A tool-only interval still
shows that work is running. Optional "Read replies" reuses the existing switch
and speaks visible assistant text, never tool traffic; dictation itself must not
depend on that switch.

Implementation slices, in order:

1. **Browse the paired host.** Add bounded project/thread projections and Swift
   models, source selection, and project-to-thread navigation. Reuse the
   iPhone's authenticated client and host identity. Offer paging or "More" for
   project/thread lists so the current eight-item Watch cap cannot make an
   existing remote thread unreachable. Browsing a project must not create a
   thread: the current remote `selectProject` calls `activateWorkspace` with
   `createIfMissing: true`, so it is not a read-only list-expansion primitive.
   Open an existing thread through the remote selection path and wait for the
   matching snapshot before showing its contents.
2. **Read a compact remote conversation.** Project the selected remote thread's
   messages and activity as they change, using the table above and the existing
   transcript layout. Carry only one transcript per frame. Keep source identity
   and snapshot ordering, preserve the 16 KB encoded payload limit in Japanese
   and emoji, and mark any trimmed history. Keep the compose bar and attention
   affordance inside the safe area, including while the reader scrolls back.
3. **Dictate into the selected remote thread.** Route selection, send, and Stop
   by explicit source and destination. Bind commands to the paired host/session,
   project, and conversation shown on the Watch. Check the target again at the
   desktop before applying send/Stop; add the necessary protocol fields and
   capability handling rather than relying on whichever desktop thread happens
   to be active. Return a correlated desktop acknowledgement or refusal to the
   Watch. Distinguish queued delivery from accepted input and completed work.
   On disconnect, reconnect to the same saved host and revalidate the target;
   a changed host, missing thread, unsupported peer, or uncertain send outcome
   must not cause a local fallback, a redirect, or an automatic duplicate send.
4. **Prove the complete wrist flow.** Use a signed iPhone/Watch pair and a real
   desktop host to browse projects, open an existing thread, dictate a prompt,
   see the reply, and answer an approval/question while tool traffic stays
   hidden. Repeat with the phone backgrounded and reconnecting. Record the
   device/build identities and observed results before marking WATCH14 done.

Affected components and reference patterns:
- `lib/features/watch/domain/{watch_snapshot,watch_command}.dart` and
  `lib/features/watch/presentation/watch_session_notifier.dart`: bounded local
  projection, WATCH3 destination binding, and WATCH8 ordering.
- `ios/CavernoWatch Watch App/`: `WatchModels`, `WatchSessionClient`,
  `ThreadPickerView`, `TranscriptView`, `ComposeBar`, and new project navigation.
- `lib/features/remote_coding/presentation/remote_coding_client_notifier.dart`,
  `remote_coding_server_notifier.dart`, and the protocol: target validation and
  correlated command outcomes. Use `remote_coding_page.dart` as the reference
  for existing project/thread data, not as the Watch layout.
- `test/features/watch/`, affected Remote Coding tests, and
  `tool/watch_wire_contract_smoke.*`: projection, routing, and Dart/Swift parity.
  Regenerate committed outputs if implementation changes a generated entity.

Acceptance criteria:
- All projects and existing threads exposed by the paired host are reachable
  from Watch navigation, including lists longer than one payload page. Empty,
  disconnected, and removed-project/thread states are distinguishable.
- Selecting a remote thread shows that thread's recent user/assistant exchange,
  never the iPhone's local conversation. Updates and speech follow only the
  selected thread; switching sources clears old deltas and playback.
- A dictated instruction appears once in the intended desktop thread and its
  reply returns to the Watch. Test a simultaneous desktop/iPhone thread switch
  and delayed Watch delivery; a mismatch produces a visible refusal. Stop uses
  the same destination binding. Local chat input continues to use its own path.
- Tool calls, arguments, results, reasoning, and internal envelopes appear in
  neither the transcript nor speech. Useful assistant prose survives mixed
  text/tool messages. Errors and required approvals/questions remain reachable.
- The layout remains readable with long titles, Japanese text, larger text
  settings, and VoiceOver on the smallest supported Watch layout. Users can
  scroll back without incoming text moving them, and reach input/attention
  controls without toolbar collisions or clipped controls.
- Frames stay within the encoded budget, late frames cannot restore an old
  destination, and unsupported phone/desktop versions cannot accept an
  unbound remote send. Authorization remains the phone's existing authority.

Dependencies and boundaries:
- Builds on WATCH3/7/8/11/13. WATCH5's push matrix and WATCH4's signed WidgetKit
  check remain separate open gates. They do not block implementing this UI;
  completing WATCH14 does not close either gate or the Remote Coding P1 gates.
- Project/thread creation, Watch-host pairing, remote goal confirmation,
  detailed tool/verification readouts (WATCH12), and full iPhone feature parity
  are outside this milestone. The requested flow uses existing remote threads.
- Keep local chat navigation available. The new source choice supersedes
  WATCH11's local-only transcript limit without merging both conversations.

Verification for subsequent slices (broader Remote Coding suites not run for slice 1):

```bash
tool/codex_verify.sh --test test/features/watch/ \
  --test test/features/remote_coding/presentation/remote_coding_client_state_test.dart \
  --test test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
tool/watch_wire_contract_smoke.sh
```

Add focused regressions for the new destination and transcript contracts, build
the Watch App and Widget extension with the installed Watch simulator SDK, and
complete slice 4 on signed hardware. Existing green tests and simulator builds
verify the shipped companion; they do not establish these new acceptance criteria.

Next action:
- Complete slice 4 on a signed iPhone/Watch pair and a real desktop host:
  browse a project, open an existing thread, dictate an instruction, observe
  accepted and queued feedback, read the reply, Stop a running turn, and answer
  an approval/question. Repeat with the phone backgrounded, reconnecting, and
  with the desktop switching threads before a delayed command arrives. Record
  device/build identities and confirm that tool traffic remains absent.

Slice 1 implementation (2026-09-15):
- Added explicit local/remote source selection, eight-item project/thread pages
  with Previous/More, host connection state, and removed/empty-list states.
  Project browsing only filters the phone's existing snapshot; it never calls
  the desktop's thread-creating `selectProject` command.
- `WatchRemoteNavigation` binds navigation to an opaque host ID and a
  phone-generated connection epoch, plus project/conversation IDs for thread
  selection. Disconnect, reconnect, or host identity changes retire the epoch.
  Selection remains pending until a newer remote snapshot names the requested
  project and conversation; timeout or changed selection is visible.
- `WatchSnapshot.remoteBrowser` carries labels and one page, with no paths or
  credentials. `transcriptSource` keeps the local and remote surfaces distinct.
  Remote selection currently shows a destination placeholder; local transcript
  text, speech chunks, voice sends, Stop, and goal commands cannot run through
  that surface. Existing approvals and questions remain reachable.
- Native Watch and Widget targets build with the installed watchOS 27 simulator
  SDK, unsigned Debug. The project still targets watchOS 10.0. Dart/Swift wire
  smoke passes for the remote page, selection identity, commands, and legacy
  frames. Signed hardware interaction and visual checks remain unperformed.
- Slice 1 gate: `tool/codex_verify.sh --no-codegen --test test/features/watch/`.
  Static analysis and 106 tests in five Watch suites pass, including Japanese
  and emoji payload budgets and source-switch speech isolation. All new models
  are plain value classes, so generated entities do not change in this slice.

Slice 2 implementation (2026-09-16):
- A confirmed remote selection now projects that client's bounded recent
  user/assistant exchange into the existing bubble layout. The projector is
  shared with local Watch transcripts so both sources omit system messages,
  synthesized prompts, reasoning, tool calls, raw tool results, and tool-only
  assistant intervals while preserving useful assistant prose from mixed
  messages. Empty streaming bubbles and the eight-message truncation marker
  retain the compact working/history behavior.
- Remote transcript identity remains the confirmed host connection epoch plus
  project and conversation. A disconnect, removed selection, or another-device
  thread change clears messages immediately instead of following the new
  desktop destination. Local messages never substitute for a missing remote
  transcript.
- The Watch renders remote loading and queue state without tool activity,
  offers a compact empty-thread state, and can read visible remote assistant
  replies through the existing opt-in speaker. The remote compose bar and Stop
  remain unavailable until slice 3 binds commands end to end.
- `tool/codex_verify.sh --no-codegen --test test/features/watch/` passed full
  workspace static analysis and all 111 tests in six Watch suites.
  `tool/watch_wire_contract_smoke.sh` passed, and the Watch App plus Widget
  extension built unsigned Debug with watchsimulator27.0. Signed-device speech,
  layout, and live-host behavior remain unverified.

Slice 3a implementation (2026-09-16):
- Added capability-gated `sendMessageToConversation` and
  `cancelConversationStreaming` commands rather than extending the legacy
  active-thread commands. An older desktop cannot silently ignore destination
  fields and redirect a Watch instruction because it never advertises or
  accepts these command names.
- The desktop validates that the requested coding project and conversation
  still exist and are still current immediately before applying send or Stop.
  Missing, removed, changed, and idle destinations return explicit correlated
  refusals. A matching send returns `accepted` or `queued`; a matching Stop
  returns `accepted`.
- The iPhone waits for the response ID and classifies accepted, queued,
  refused, timeout, connection change, and malformed acknowledgement outcomes.
  It does not retry an uncertain command. Destination refusals preserve the
  current remote loading state instead of making an active turn appear idle.
- Focused client and authenticated WebSocket server suites pass: 20 client
  tests and 18 server tests. The regression drives accepted, queued, changed
  destination, accepted Stop, and stale Stop paths through a pinned connection.
  Watch commands and native controls remain unchanged until slice 3b.

Slice 3b implementation (2026-09-16):
- `WatchRemoteBrowser` now advertises input support only from a desktop that
  exposes the slice 3a capability. The Watch shows its native `TextFieldLink`
  and Stop action only after that host, project, and conversation have a
  confirmed selection; legacy and unconfirmed destinations remain read-only.
- Remote send and Stop commands carry source, opaque host ID, the
  phone-generated connection epoch, project ID, and conversation ID. The
  iPhone compares every field with `WatchRemoteNavigation` immediately before
  invoking the destination-bound client API. A restarted phone, reconnect,
  local/remote source switch, removed thread, or another-device selection
  change produces a visible refusal and never reaches local chat.
- The Watch keeps the compose control on screen while the iPhone waits for the
  correlated desktop result. Accepted and queued outcomes produce notices;
  refusals show the desktop reason; unknown delivery explicitly tells the user
  to inspect the desktop before retrying. No uncertain command is retried.
- Full Watch analysis and 113 tests in six suites pass. The Dart/Swift wire
  smoke covers input capability plus host/session/project/conversation command
  binding. The Watch App and Widget extension build unsigned Debug with
  watchsimulator27.0. Signed-device Dictation, background delivery, reconnect,
  accessibility, and live-host behavior remain unverified and belong to slice
  4.
