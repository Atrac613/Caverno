# Watch And Remote Coding Device Verification (2026-09-06)

One session on real hardware that collects two things at once: the walkthrough
for the SA-26 authority work, and the three user-operated P1 gates that are all
that still stand between Remote Coding and product promotion.

They are combined because they need the same setup — a desktop running the
host, a paired iPhone, and a paired Apple Watch — and because the P1 soak is
half an hour of running time that the SA-26 steps can be performed inside.

## Why this exists

Everything below is unverified on hardware. The SA-26 slices, the per-device
grant, and the audit are covered by unit and socket tests only, and this
track's history is that the seams those cannot reach are where the defects
live: WATCH2 surfaced ten, and the WATCH10 notification path took seven
attempts before a banner appeared. A static sweep during the same work found
four more (three drifted approval-kind enumerations and an unserialised audit
write). None of that is evidence that the app works in someone's hand.

## Setup

Protocol version 2 requires **both ends rebuilt**. `RemoteCodingProtocolMessage`
requires an exact version match, so a phone on an older build is refused
outright — which is step 0, not a problem.

macOS builds are confined to the worktree holding `.macos-canonical`, so the
branch has to be on `main` first:

```bash
tool/safe-flutter run -d macos
```

Install the iOS app from the same commit, and pair the phone to the desktop
(Settings > Remote Coding Host > pairing QR).

**Part 1 runs on a simulator; Part 2 needs real devices.** Pairing was the one
step with no non-camera path, and a simulator cannot photograph the QR on the
Mac's screen, so the session used to end before its first check. Debug builds
now offer a typed alternative on both ends — see below. Part 2's soak still
needs real hardware: backgrounding, sleep/wake, and an IP change are not
simulable.

### Pairing a simulator (debug builds only)

`RemoteCodingDebugPairingPolicy` gates both halves, and it is false in release
*and* profile. Scanning a QR is a proof of proximity — it says the person
pairing can see the desktop's screen — and pairing confers the desktop's
execution authority (SA-26), so shipped builds keep the camera as the only way
in.

1. On the desktop, open the pairing dialog and press **Copy payload (debug)**.
2. Move it to the simulator's pasteboard:

   ```bash
   pbpaste | xcrun simctl pbcopy <device-udid> -
   ```

3. On the phone, **Pair with Desktop** → the paste icon in the app bar → the
   field is prefilled from the clipboard → **Use code**.

The typed string is the same one the QR encodes and rejoins the scan path at
the caller, so nothing downstream can tell the difference. The ticket is
single-use and expires in five minutes either way.

Walked on a simulator 2026-09-06, with two things worth knowing:

- **Deny the camera prompt.** `MobileScanner` asks on first open; the paste
  action sits in the app bar and works without it, which is the point.
- **iOS asks for paste consent every time** ("Caverno would like to paste from
  CoreSimulatorBridge"), so the flow is one extra tap. It cannot be
  pre-answered from `simctl`.

A payload with the wrong `kind` is rejected by the same validation a bad scan
meets — "This QR code is not a Caverno Remote Coding pairing code" — and a
correctly shaped one reaches "Pairing with desktop…" against the host it names.
Both were observed, which is what says the typed path is the scan path and not
a second one.

## Part 1 — SA-26 authority

**0. The refusal.** With the phone still on an older build, connect. It must
fail to connect. An approval rendered with the wrong kind is what the version
bump exists to prevent; seeing one here means the bump did not take.

**1. A kind that could never cross.** From the phone, in a Remote Coding
thread, ask for something that provokes an SSH command. The phone must show an
**SSH commands** approval, and answering it must unblock the desktop. Before
SA-26 the desktop blocked and the phone showed nothing.

Then provoke an `ssh_connect`. The phone must show it **read-only** — "This
request needs input that only the desktop can collect" — with no buttons, and
dismissing the sheet must **not** deny it.

**2. The warning.** Background the phone, then provoke a destructive shell
command. The notification must carry two lines: what will run, and the warning
beneath it. Check the lock screen and the wrist. Approve/Deny must still be
there; the fix was to complete the question, not to remove the answer.

**3. The grant.** Start a turn **at the Mac** that needs a shell approval. The
phone must show nothing — no device is granted anything by default.

- Grant "Shell commands" to the device (Remote Coding settings, the shield icon
  on the device row). Repeat: the approval reaches the phone, and answering it
  there must also close the Mac's own sheet.
- With an approval showing on the phone, untick the kind at the Mac. It must
  disappear from the phone without a reconnect.
- Grant only "Questions": a shell approval must not reach the phone, and an
  `ask_user_question` must.

**4. The audit.** Remote Coding settings > Remote decisions. Newest first, the
granted ones marked "Answered this Mac's own request", and a Refused row for
the attempt made before the grant. Restart the desktop app: the list survives.
Copy Support Packet and confirm it carries **no command text** — that is the
structural claim, that the audit lives outside the settings the packet is built
from.

**5. Revocation.** Revoke a device that holds a grant. Its socket closes, and
the shield returns to "granted nothing". Re-pairing starts from an empty grant.

## What the 2026-09-06 session established

Run on the paired iPhone 17 Pro Max simulator against a macOS host at
`192.168.100.5:8767`, driving the phone from the harness and the desktop by
hand. Every line below was observed rather than inferred.

| | Observed |
|---|---|
| Typed pairing (debug) | Paired with the camera prompt denied, payload bridged by `simctl pbcopy` |
| Thread creation from the phone | Works, and already existed — the drawer's per-project `+`, reached through the app bar |
| A declined command is not a disconnection | The rejection rendered as a banner with the thread list intact; before today's fix it replaced the page with the pairing screen |
| An approval reaches the phone with its warning | "This command has host-wide filesystem access" and SEC4.4g's fresh-approval sentence, both on the sheet |
| Resolving from the phone runs the command | `uptime` returned `up 6 days, 18:50` into the thread |
| The audit records it | Device, kind label, timestamp, warning; a second entry from an earlier session survived a desktop restart |
| **Ungranted desktop-origin is withheld** | At 17:07 the Mac sat blocked on `Local Command Approval` while the phone showed no sheet, no banner, and no notification |
| **Granted desktop-origin arrives** | After ticking Shell commands on the device's shield, the same approval appeared on the phone with its warning |
| Answering it closes the desktop's own sheet | Confirmed at the Mac |
| The audit marks it as the widened authority | The entry carries "Answered this Mac's own request" |

Two frictions this cost time on, both now in the setup notes above: the
simulator's `text` action did not reach the Flutter composer, so prompts go in
through `simctl pbcopy` and a long-press paste; and building macOS outside the
canonical worktree produced a running app whose Dart code was a day old, because
the DevFS attach failed and debug builds ship their Dart over that channel.

A second pass the same evening closed the rest of Part 1:

| | Observed |
|---|---|
| Read-only rendering | An `ssh_connect` reached the phone as "SSH connection / atrac@192.168.100.241 / Credentials are required." with "This request needs input that only the desktop can collect" and no answer |
| A resolved interaction takes its sheet away | Cancelling the SSH dialog at the Mac closed the phone's sheet; before that evening's fix it stayed |
| Withdrawing a grant takes effect | With Shell commands unticked, the same Mac-side turn's approval no longer reached the phone while the Mac sat blocked on it |
| Revocation | "This mobile device was revoked on the desktop", the saved host cleared, and only Pair with Desktop left |

Two more defects surfaced by running it, both fixed the same evening: the page
opened approval and question sheets and never closed one, so answering at the
desktop or withdrawing a grant left the phone still asking; and the read-only
sheet had no way out, because the modal is deliberately not dismissible and
that kind offers no answer.

**A grant cannot be withdrawn while the desktop is blocked on its own
approval.** The desktop's approval dialog is modal, so settings are
unreachable until it is answered — which is the moment someone would most want
to narrow a device. Recorded as an observation, not a defect: the modality is
what stops a stray click from resolving a shell command. The sheet-dismissal
half of that behaviour is covered by
`remote_coding_page_notification_suppression_test.dart` instead, where the
withdrawal can be driven directly.

## Part 2 result: two of the three gates closed on simulators

Run 2026-09-06 with two paired iPhone simulators against the same macOS host.
Evidence files are kept in `docs/evidence/`.

| Gate | Result |
|---|---|
| `support_packet_review` | **ready** — packets copied from both sides, each verified for token material independently of its own privacy flags: no 64-hex hashes, no base64url tokens, only device-id UUIDs |
| `multi_device_household` | **ready** — all four observations |
| `resilience_soak` | **blocked**, and honestly so: it names iOS *and Android* thirty-minute LAN soaks, desktop sleep/wake, and an IP change. None of that is simulable |

Two simulators are legitimate evidence for the household gate because what it
checks is server-side authorization, not device hardware: each is a distinct
paired device with its own id and token. The two observations that matter were
taken with both connected at once:

- **18:24 — `approvalsReachOnlyRemoteOriginTurns`.** Device A started a turn
  that blocked on a shell approval. A showed the sheet; **B showed the same
  thread and the same tool call, and no sheet at all.** That is SEC4.5g's whole
  property, seen on two screens at one timestamp.
- **18:27 — `revokingOneDeviceKeepsOtherDeviceUsable`.** Revoking B left it with
  "This mobile device was revoked on the desktop" and only Pair with Desktop,
  while A stayed connected and could still send.

Three things this cost time on, all worth knowing before a real-device run:

- **The mobile support packet cannot be copied from a healthy session.** The
  connected header has no such action; it is reachable only from the connection
  view or an error banner. A packet was obtained by relaunching the app, which
  keeps the pairing. The P1 requirement says "from both sides of a paired
  session", so this is a gap against the wording rather than a defect in the
  packet.
- **`activeSessionCountUpdates` needs two live connections at the instant the
  evidence is copied** (`activeConnectionCount >= 2`), not merely two paired
  devices. Copying it after revoking one device reports false, correctly.
- **A second simulator starts at onboarding**, which requires a reachable LLM
  endpoint before it will finish. The desktop's own LAN endpoint works.

## Part 2 — P1 evidence, collected in the same session

The three remaining P1 gates are `resilience_soak`, `support_packet_review`,
and `multi_device_household`. `docs/remote_coding_p1_release_gate.md` owns the
commands; what follows is only the order that lets one session satisfy all
three.

1. Write the template, then pair a **second** device before starting the soak,
   so the household checks and the soak share one run.
2. Run the thirty-minute LAN soak on iOS and on Android. Inside it: background
   and resume the phone, sleep and wake the desktop, and change the desktop's
   IP. Part 1's steps can be performed during this window.
3. Copy the support packet from both sides and review the diagnostics for token
   material by eye — the gate merges the packet's checklist patch, but the
   review is the part it cannot do.
4. Copy the multi-device evidence from the desktop.
5. Run the gate with both packets and the evidence file. Every static gate is
   already ready, so a blocked result names exactly which observation is still
   missing.

## What a failure means

- **Part 1 step 3 disagrees with the grant** — the authorization gate is wrong,
  not the UI. Stop and treat it as a security defect.
- **Part 1 step 4 shows command text in the support packet** — the audit's
  separation from the server settings has been broken.
- **A soak failure** — resilience, not authority; it blocks promotion but not
  the SA-26 work.
