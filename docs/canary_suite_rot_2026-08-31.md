# Live Coding Canary Rot (2026-08-31)

Six independent defects, found while trying to run one live coding canary to
verify a shipped harness change. Every one of them was silent: nothing in the
suite reported a problem, because **no live coding canary that runs a shell
command had been executed since 2026-08-24**, and several of the others produced
no evidence at all when they did run.

The order matters — each fix exposed the next.

## 1. Every shell command parked on an approval nobody could answer

SEC4.4g (`9626b025`, 2026-08-24) made any command reaching the native shell
require a *fresh* manual approval; `fullAccess` and remembered allow-rules no
longer bypass it. A canary has no UI, so
`ChatNotifier.requestLocalCommand` parked on a `Completer` forever. The session
log's last line is the tool's `started` lifecycle event, and nothing follows.

Measured on `coding_goal_live_edit`, same fixture, same model:

| | per-case durations |
|---|---|
| without responder | 480s / **600s** / **600s** / 72s / **600s** / 48s |
| with responder | 29s / 29s / 38s / 52s / 40s / 48s |

Fixed by `tool/canaries/support/live_canary_approval_responder.dart`, which
answers one command at a time and remembers no rule — a cached allow would
silence the gate the canary runs through. It prints each approval into the run
log so what a run was permitted to execute stays visible.

**The gate itself is correct and was not touched.**

## 2. Attaching the responder from the container builder broke the goal

`container.listen` initialises the provider it watches, so attaching in
`_buildContainer` built `ChatNotifier` before the canary created its
conversation and saved its goal. Every case then failed on a missing
`Active coding goal for this thread:` block. Attach at the send site instead,
where the notifier is read anyway, and make `attach` idempotent per container.

## 3. The system-prompt filter matched nothing

Three canaries selected the main system prompt with
`startsWith('Current local date and time')`. The prompt gained a safety
preamble above the temporal block, so the marker now sits at index **16658**:

```
STARTS WITH: 'Your training knowledge may predate the current date above...'
'Current local date and time' at index: 16658
```

The prefix match selected nothing, `firstSystemPrompt` returned `''`, and six
assertions failed against an empty string — which reads as *a missing coding
goal*, not as a broken filter. Session logs show the goal was in the prompt the
whole time (`Active coding goal for this thread` appears five times in the run).

Fixed by matching on content. The filter still separates the main loop from the
secondary memory-extraction call, which is excluded on a different path.

## 4. Seven runners wrote no session log

Two things are required and either alone is a no-op:

- the runner must set `CAVERNO_SESSION_LOG_DIR` — under `flutter test` the
  default store writes only when that is set, deliberately, so unrelated tests
  cannot append to the developer's real corpus; and
- the canary's settings notifier must set `enableLlmSessionLogs`, which
  defaults to `false`.

Three runs of `coding_goal_live_edit` earlier that day left zero evidence.

## 5. …and wiring both still produced *ungrounded* logs

`ChatNotifier._withChatSessionLogging` wraps a source only when it
`is ChatRemoteDataSource`. Five canaries' scripted sources
`implement ChatDataSource` directly, so they came back unwrapped: the run
emitted six files carrying a `turn_exit` each and **zero requests** — exactly
what the analysis tools discard as ungrounded.

Fixed by wrapping at the provider override rather than changing the base class.
Extending the live `ChatRemoteDataSource` is what previously let new methods
leak into scripted tests unnoticed
([[caverno-scripted-datasource-inherits-live-methods]]), and the wrapper already
forwards `FinishReasonAware` and `StreamingToolResultsChatDataSource` by probing
the delegate.

## 6. …and the grounded logs recorded no build

Seven runners passed no `CAVERNO_BUILD_*` dart-defines, so their logs recorded
commit `unknown`. `tool/check_fix_firings.py` then refused to credit a firing it
could not attribute:

```
[not yet observed] mutation_digest_section
    UNKNOWN BUILD: 6b3b4411 (build unknown not in this repo)
```

The digest *was* emitting its mutation section in those very prompts. **The
instrument was right and the runners were wrong** — worth stating plainly,
because the tempting reading is that the change had not fired.

## What this suite could not tell you

Beyond the six defects, two capability findings:

- **The fixtures have been outgrown by the model.** `qwen3.8-27b-vision`
  finishes `markdown_toc`, `minimal_prompt` and `todo_app_mvp` in 5–6 tool-loop
  steps. Older CMVP-1 evidence recorded 14 iterations and 717 s — on
  `qwen3.6-27b-vision`. Any measurement needing a long multi-round turn has no
  vehicle in this suite except `coding_goal_live_edit`, whose cases still reach
  5–17 steps.
- **`coding_goal_composer_live_smoke` is broken independently** and was not
  fixed: its widget finders no longer match the UI (`Found 0 widgets with type
  "Switch"`). Confirmed pre-existing by running the unmodified file.

## Method note

Every one of these was found by reading the harness *before* trusting a green,
or by refusing to accept a failure's surface reading. Two of today's diagnoses
were wrong on the first pass and were corrected by measurement:

- "the verifier hangs on stdin" — disproven by running the verifier by hand; it
  completes in seconds and prints `All acceptance criteria passed.`
- "the filter string is gone from the prompt" — an artifact of reading the
  *truncated* app log; the session log shows it present at index 16658.

Both corrections came from going to the authoritative artifact (the session log,
the real process) rather than the convenient one.
