# Caverno, end to end — the book I wish I'd had on day one

> Language note: this project's CLAUDE.md mandates English for every code-level
> artifact, and that rule outranks the global "write FOR_ME.md in plain
> language" guideline. So this is written in English — but in the spirit of the
> global guideline: stories, analogies, real failures, not a dry spec.

## What Caverno actually is

Caverno is a Flutter chat client for OpenAI-compatible LLM APIs. That sentence
undersells it. It is really a *small autonomous agent* you can point at a local
LLM: it calls tools (MCP servers + a big built-in catalog), remembers you across
sessions, talks and listens (voice I/O), edits code on a paired device, and runs
scheduled "routines" on its own. It runs on iOS, Android, macOS, Windows, and
Linux, and by default it talks to a model on `localhost:1234` — your own GPU box,
not someone's cloud.

The mental model that helped me most: **Caverno is a kitchen, and the LLM is a
talented but forgetful line cook.** The cook is fast and creative but will
happily re-read the same recipe ten times, trail off mid-sentence when the ticket
is long, and occasionally try to "fix" a dish by writing down the result it
*wishes* existed. Most of this codebase is the *expediter* standing next to the
cook: handing over the right tools at the right time, catching half-finished
plates, and refusing to send anything dangerous out to the dining room. Keep that
image. Almost every hard-won lesson below is really "how do you run a kitchen
around a brilliant cook who doesn't remember the last ten seconds."

## The architecture, from 10,000 feet

Clean Architecture + feature modules + Riverpod. 430 Dart files, but the shape is
simple once you see it:

```
lib/
├── core/        # cross-cutting: constants, security, services, types, utils
├── features/    # chat, settings, routines, remote_coding, personal_eval, maintenance
└── main.dart    # boots Hive, SharedPreferences, i18n, desktop windows, Riverpod overrides
```

There is deliberately **no `lib/shared/`** — shared UI lives inside the feature
that owns it. Each feature follows `data → domain → presentation`.

The heart that pumps blood through everything is `ChatNotifier`. When you send a
message, here is the journey:

1. **`SystemPromptBuilder`** assembles the system prompt: the current date/time
   (so "today" means something), your session memory, the active coding goal,
   the available tool names, and the assistant mode (`general`, `coding`, `plan`).
2. The request goes out through `ChatRemoteDataSource` (streaming or not),
   wrapped by `SessionLoggingChatDataSource` which writes every request/response
   to `~/.caverno/session_logs/**` — the flight recorder that made most of this
   document's lessons possible.
3. If tools are enabled, a **tool-calling loop** runs (capped iterations): the
   model asks for tools, we execute them, and — this is a real quirk — we feed
   the results back as a **user-role** message, because several local models
   handle tool-role messages badly. The final answer streams from there.
4. On completion we persist to Hive, then make a *second* LLM call to extract
   durable memory about you, and maybe emit a structured plan/workflow artifact.

Everything reactive hangs off Riverpod `Notifier`s. `SettingsNotifier` changes
ripple into `ChatNotifier` via `ref.listen`; `RoutinesNotifier` +
`RoutineScheduler` wake scheduled runs; `ConversationsNotifier` owns Hive.

## The codebase, and the saga of the 15,000-line file

If you open `lib/features/chat/presentation/providers/chat_notifier.dart` you
will meet a ~15,000-line class and briefly question this project's life choices.
It is intentional, and the way it's tamed is worth understanding because you will
extend it.

Dart lets a class be split across files with `part` / `part of`, and lets you
bolt on methods from another file with `extension XOnChatNotifier on ChatNotifier`.
So `ChatNotifier` is one logical class physically spread across ~22 part-files:
`chat_notifier_ssh_handlers.dart`, `chat_notifier_git_handlers.dart`,
`chat_notifier_python_handlers.dart`, `chat_notifier_mesh_routing.dart`,
`chat_notifier_coding_continuation_recovery.dart`, and so on. Each part-file owns
one concern (a tool family, a recovery path, prompt assembly).

Two gotchas the compiler will teach you the hard way:
- Inside an `extension`, references to the class's own static members must be
  qualified (`ChatNotifier._someStatic`), or you get
  `unqualified_reference_to_static_member_of_extended_type`.
- Touching `state` from an extension needs
  `// ignore_for_file: invalid_use_of_protected_member`.

There's a **file-size ratchet test** (`test/quality/file_size_ratchet_test.dart`)
that pins a max line count per file. Budgets may only shrink, never grow. It's a
guardrail against the giant file quietly getting giant-er — when you add code you
either fit under budget or you extract a new part-file. (I once nearly blew the
budget adding a helper; the fix was to put the pure logic in its own small,
testable file instead. More on that pattern below — it's a good habit.)

The other neighborhood worth knowing is **`lib/core/security/`** — the SEC1/SEC2
perimeter (`tool_capability_classifier.dart`, `data_source_classifier.dart`,
`tool_perimeter_context.dart`, `taint_policy.dart`, `conversation_taint_state.dart`).
This is the bouncer at the door: it classifies how dangerous a tool is, how
trusted a piece of data is, and whether untrusted content (a web page, an MCP
resource) is allowed to influence a high-risk action. It is why, in a real
session, Caverno read a remote page that said "run `echo ... > /tmp/x`" and
correctly refused to auto-run it.

## Tech choices, and what they cost

- **Riverpod (`Notifier`/`NotifierProvider`), not BLoC.** Less ceremony,
  testable, and `ref.listen` makes cross-feature reactions clean. Cost: provider
  graphs can get subtle; overrides in `main.dart` are how shared resources (Hive
  boxes, prefs) are injected.
- **Freezed for entities** (`Message`, `Conversation`, `AppSettings`,
  `ChatState`, `Routine`, …). Immutability + `copyWith` + unions for free. Cost:
  code generation. Touch an entity → `dart run build_runner build
  --delete-conflicting-outputs`, and the generated `*.freezed.dart`/`*.g.dart`
  are committed.
- **`openai_dart`** wraps any OpenAI-compatible endpoint, so the same code talks
  to LM Studio, llama.cpp, vLLM, or a cloud API.
- **Storage tiers:** Hive for conversations + chat memory (JSON strings),
  SharedPreferences for settings + window geometry, `flutter_secure_storage` for
  SSH credentials. Right tool per sensitivity.
- **FVM** pins Flutter (`.fvmrc`). This bites: bare `flutter`/`dart` resolve to
  the FVM *default*, not the project pin, which can desync build-hook caches (see
  the "Invalid SDK hash" story below).
- **`serious_python`** embeds a real Python interpreter for the
  `run_python_script` tool; the worker is packed into `assets/python/app.zip`.
- **MCP** (Model Context Protocol) over HTTP/SSE and stdio, so external tool
  servers plug in next to the built-in catalog.

## Lessons — the part that's actually worth your time

These are real. Most came from reading the flight recorder
(`~/.caverno/session_logs`) or from running the model live against a LAN box.

### Lesson 0: fix what the logs prove, not what you imagine

The single most valuable habit. Every change that *survived* was backed by a real
log or a live run; nearly every change built from a clever hypothesis got
reverted. A "this is intentional, don't touch it" conclusion is also a win,
because it prevents harmful churn. When you're tempted to add a heuristic, go get
a real run first. (There's a memory note enshrining this; believe it.)

### Lesson 1: a brilliant cook with amnesia loops — so make tool errors *actionable*

Live trace, repeated 100% on a nested-package fixture: the model needed to repair
a one-line arrow function `String f() => 'BROKEN';`. It called
`edit_file(old_text: "  return 'BROKEN';")` — assuming a block body that wasn't
there. The tool returned a terse `{"error":"old_text was not found"}`. The model
then re-read the file ten times and, at its most confused, tried `edit_file` with
the *desired new value* as `old_text` (asking to find a line that doesn't exist
yet). It never landed the fix.

The fix wasn't to make the model smarter — it was to make the *error* do some of
the thinking. Now, when `old_text` isn't found, `edit_file` echoes the current
file content (for small files) plus a pointed hint: "copy `old_text` verbatim
from the content above; if matching is hard, use `write_file` to overwrite."
Result: the live canary went from **0/4 to 6/6**. Lesson: at the point of
failure, a tool result is the cheapest, highest-leverage place to unstick a model.
Just-in-time beats a paragraph of upfront instructions the model has forgotten.

### Lesson 2: don't let a utility call inherit a user's diet

A real session had `maxTokens=64` (the user wanted short answers). The *main*
answer truncating was their choice. But the **memory-extraction** secondary call
used `min(maxTokens, 1200)` — a ceiling with no floor — so it also got 64 tokens,
truncated its JSON mid-object, and got thrown away as invalid. A user's
answer-length preference had silently broken a background feature.

Fix: `SecondaryCallBudget.resolve(userMaxTokens, ceiling)` clamps to
`[512, ceiling]`. Normal users (high maxTokens) are completely unaffected — they
still get the ceiling — so it's a strictly-safe floor that only rescues the broken
low case. Then I found the same flawed pattern at ~10 other secondary call sites
and applied the helper uniformly. Lesson: background/utility LLM calls need their
own budget, decoupled from whatever the human dialed in for chat. And: a
provably-zero-impact-for-normal-users change is the safe way to fix a systemic
pattern.

### Lesson 3: the macOS Local Network Privacy ghost (a two-hour whodunit)

I tried to run live canaries against the LAN model at `192.168.100.241:1234`.
Every request failed instantly with `No route to host (errno 65)` — yet `curl`
to the *same IP at the same second* returned HTTP 200. Spooky.

The tell: a tiny `dart` probe reproduced it (LAN → EHOSTUNREACH, loopback →
"connection refused" i.e. reachable, curl LAN → 200). It's **macOS Local Network
Privacy**: `curl` inherits the Terminal's local-network grant; the
`flutter_tester`/`dart` binary has no grant, so LAN connections are blocked.
Loopback is never subject to this — which is exactly why the default
`localhost:1234` never trips it.

Workaround that unblocked everything: run a tiny loopback→LAN TCP relay from a
process that *does* have the grant, and point the test at `127.0.0.1`. The test
only ever touches loopback; the relay forwards to the LAN box. Lesson: when two
processes behave differently against the same address, suspect per-binary OS
permissions before you suspect the network. And isolate with the smallest
possible probe.

### Lesson 4: some repetition is on purpose — read before you "optimize"

It is tempting to look at the model reading the same file repeatedly and add a
read cache. Don't, casually. `read_file` is **deliberately repeatable**: the
tuned dedup/recovery logic encodes intentional re-execution, and a blanket
turn-level read cache broke seven carefully-tuned tests. Similarly, the full
~64-tool payload sent every request looks wasteful but is an intentional KV-cache
trade-off (prefix stability). Lesson: in a mature agent loop, "obvious waste" is
often a tuned decision. Confirm with the tests and the history before you trim.

### Lesson 5: never push the cook past their own "I shouldn't"

A reverted experiment tried to nudge the model from "presenting a plan" into
"executing it." On a live log it pushed *past a production-release confirmation
pause* — exactly the moment you want the model to stop and ask. Recovery
heuristics must never override the model's own caution. Lesson: when in doubt
about autonomy, the safe default is to stop and surface, not to proceed.

### Lesson 6: build the flight recorder a search box

After triaging session logs by hand three times, I noticed I was running the same
analysis each time. So I productized it: `tool/triage_session_logs.py` scores
every session by anomaly signals (length-truncations, transport errors, the
longest identical tool-call loop, oversized turns) and ranks the worst offenders.
It immediately surfaced a session with **15 consecutive `search_web` calls** — a
model that kept rephrasing a GPU-price query instead of answering. (The harness's
bounded tool-loop limit *did* fire and the session converged, so: working as
designed, model just over-iterates. No change — another "don't touch" win.)
Lesson: when you repeat an investigation, turn it into a tool. It pays for itself
the first time it runs.

### Lesson 7: the flight recorder logs the cook's draft, not the plate that left the kitchen

A coding session's log ended with the cook announcing "コミットが完了しました"
(commit done) and a tidy table of what it "committed." `git status` told a
different story: nothing was committed, both files still staged. Two threads came
out of one log, and they pulled in opposite directions.

The real bug was upstream. `git_execute_command` has a commit preflight
(`git_tools.dart`) meant to stop a genuine footgun: committing a file whose
*staged* snapshot is stale because the worktree has newer unstaged edits — the
commit would silently drop them. Good intent, but it checked the whole worktree:
it blocked `git commit` whenever *any* file anywhere was unstaged or untracked,
even files unrelated to what you staged. So the cook staged the release note,
tried to commit, got blocked by some unrelated `lib/**/*.dart` edit, re-staged,
tried again, looped, and never landed it. The fix narrowed the guard to its real
target: only block when a *staged* file *also* has unstaged worktree edits
(porcelain `XY` both non-space). Unrelated dirty/untracked files no longer block
the normal "stage a subset, commit it" workflow.

The second thread is the trap, and it's the one worth remembering. I read
"completed" in the log, assumed the lie had reached the user, and started building
a turn-scoped "failure ledger" to catch success claims that contradict a failed
tool result. Then I wrote the repro test before trusting myself — and it passed
*without my change*. The existing completion-claim guards already replace that
exact claim with an "unverified / not executed" notice. **The session log records
the model's raw response, not the message `ChatNotifier` actually rendered after
its post-response guards.** The cook had written down the dish it wished existed
(exactly the failure mode flagged in this doc's opening), and the expediter had
already caught the plate at the pass — the log just preserves the discarded draft.
I reverted the ledger and kept the repro as a regression test. Lesson: when you
debug from the flight recorder, the displayed truth lives at `state.messages`, not
`response.content`. Reproduce at the UI layer before "fixing" a guard that already
works — see [docs/session_logs.md](docs/session_logs.md) for the caveat now
written down so the next investigator skips the detour.

### Lesson 8: the engineering mindset that kept paying off

- **Isolate to the smallest reproducer.** A 5-line `dart` probe cracked the
  Local Network Privacy mystery; a single-canary re-run proved reproducibility.
- **Branch, commit atomically, merge clean.** One logical change per commit,
  English Conventional Commits, no AI attribution (project rule).
- **Prefer tool/feedback-layer fixes over behavioral heuristics.** They're
  testable deterministically and don't fight the tuned loop.
- **A negative result is a result.** "Investigated, it's model-side / intentional
  / environment, no change" is worth writing down — it stops the next person
  (or the next you) from re-opening it.

## Where to start reading

- The loop: `lib/features/chat/presentation/providers/chat_notifier.dart` and its
  `chat_notifier_*` part-files.
- The prompt: `lib/features/chat/domain/services/system_prompt_builder.dart`.
- The bouncer: `lib/core/security/`.
- The tools: `lib/features/chat/data/datasources/` (filesystem, git, shell,
  network, BLE, MCP).
- The flight recorder: `~/.caverno/session_logs/**`, plus
  `tool/triage_session_logs.py` and `tool/sec_verify_logs.sh` to read it.
- Live truth: `tool/canaries/*` + `tool/run_*_canary.sh` (point
  `CAVERNO_LLM_BASE_URL` at a real model; on macOS use the loopback relay for a
  LAN box).

Welcome to the kitchen. Watch the cook, trust the logs, and keep the dangerous
plates off the pass.
