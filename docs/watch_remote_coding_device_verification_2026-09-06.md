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
