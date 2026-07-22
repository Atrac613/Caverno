# Session d66c4261: the cadence is finally legible, and the skip was correct (2026-07-22)

Log: `~/.caverno/session_logs/coding/d66c4261-72e6-41dd-b0a8-c39747a7d658.jsonl`

## Provenance, checked first

`build.commit 11980f89`, `dirty: false`, built `08:39:28Z` = **17:39:28 JST**.
That is the LL36 structural-enforcement commit, so the binary contains every
fix from this session: the auto-continue cadence fix (`a2c1d0c5`), the cadence
logging, the validation stderr/exit-code fix (`52926cc3`), and the
`validationExitCode` removal (`05a05f54`). The session ran 17:40:57 – 17:46:14
JST, ninety seconds after the build.

## The session: CMVP-1 run 9, a clean pass

Nine tool results, five tools, ~5 minutes, no tool errors:

| # | Tool | Fact |
|---|---|---|
| 1 | `read_file` | `todo_app.md` (the spec) |
| 2 | `list_directory` | empty project |
| 3 | `write_file` | `pubspec.yaml` `created:true changed:true` |
| 4 | `write_file` | `bin/todo.dart` 3772 bytes `created:true` |
| 5 | `write_file` | `pubspec.yaml` again `created:false changed:true` |
| 6 | `local_execute_command` | `dart analyze` → **exit 0**, "No issues found!" |
| 7 | `local_execute_command` | the acceptance criteria, across separate processes → exit 0 |
| 8 | `local_execute_command` | `rm -f .todo.json` cleanup → exit 0 |
| 9 | `dart_test_verification_evidence` | `no_test_target` |

Step 7 is the `todo_app.md` completion definition actually being met — `help`,
`add`, `list`, `done` invoked as separate processes with the state file removed
first. This is the criterion session `2659093b` promised and skipped.

Step 5 is the pubspec flip-flop signature from the CMVP-1 notes (`publish_to`
and the SDK constraint rewritten). Self-corrected in one step; noted, not a
problem here.

## The instrumentation did its job

`cfaa8297` ended undiagnosable: the auto-continue record logged evidence but
not the cadence, so a wrong-looking skip could not be explained. The record now
states it:

```
decision: skip   reason: "no incomplete evidence"
verificationCadence: notDue   mutationGeneration: 5   verificationGeneration: 5
```

Verification had caught up with mutation, so `notDue` is right and the skip is
right. Compare `cfaa8297`: mut=5, **ver=-1**, cadence `required`, and it
skipped anyway. One field turned an argument into a reading.

## The cadence fix is still unexercised

Per-request snapshots (taking the **first** match per request — the live one,
not the replayed copy):

| time | mut | ver | cadence |
|---|--:|--:|---|
| 17:41:33 – 17:41:59 | 0 | -1 | notDue |
| 17:43:05 | 1 | -1 | **required** |
| 17:43:32 | 2 | -1 | **required** |
| 17:43:54 – 17:44:31 | 3 | -1 | **required** |
| 17:44:56 | 4 | -1 | **required** |
| 17:45:26 | 5 | -1 | **required** |
| 17:45:54 (final answer) | 5 | -1 | **required** |
| 17:45:54.628 (auto-continue) | 5 | **5** | **notDue** |

The cadence was `required` for the whole working phase, but the generation
caught up in the 440 ms between the final answer request and the auto-continue
decision. So the branch the fix added — continue when
`verificationCadence == required` — **still has not fired in production**. The
fix is correct by construction and by unit test; it remains unproven live.

### What advanced the generation

By elimination across the three callers of `recordCurrentVerificationGeneration()`:

- **Not** the coding-verification-feedback path: it only advances on
  `validationStatus == passed`, and its evidence payload here reads
  `validation_status: "unknown"`.
- **Not** the terminal-success path: nothing emitted `terminal_success` (see
  below).
- **Yes** `_recordSuccessfulVerificationGenerationIfNeeded`, gated on
  `hasSuccessfulExecutionVerification` — which `_hasAnyExecutionVerification`
  sets when a verification-classified tool result carrying an `exit_code`
  appears *after the last mutation*. `dart analyze` at exit 0 qualifies,
  deliberately.

That is the documented bridge between the two notions of "verified" working as
intended, not a leak.

## `dart_test_verification_evidence` verified nothing

```json
{"validation_status":"unknown","target_batches":[],"reason":"no_test_target",
 "counts":{"passed":0,"failed":0,"skipped":0},
 "telemetry":{"duration_ms":2,"command_attempt_count":0}}
```

Zero commands, 2 ms. The CMVP-1 fixture has no test target, so the mechanical
verification path is structurally inert for it — consistent with the coverage
note in `docs/validation_status_three_paths_2026-07-22.md` (path A runs its own
`dart test` over changed Dart files, and only that).

It is harmless here, but it does put a record *named* verification evidence
into the transcript while carrying none. Worth watching if a future consumer
starts treating the presence of that tool result as a signal.

## Found while tracing: an unaudited terminal-state path (did not fire here)

`_acceptTerminalSuccessForCurrentGeneration()`
(`chat_notifier_goal_auto_continue.dart:334`) gates
`_finishExplicitTerminalSuccess`, which breaks the tool loop and finalizes the
turn as success. It reads:

```dart
await notifier.recordCurrentVerificationGeneration();   // sets ver := mut
final conversation = …;
if (conversation == null ||
    conversation.verificationGeneration != conversation.mutationGeneration) {
  appLog('[Tool] Terminal success rejected because execution generations '
         'do not match');
  return false;
}
```

`recordCurrentVerificationGeneration()` assigns
`verificationGeneration = mutationGeneration`, so the check tests a condition
the line above just created. The rejection is reachable only if persistence
fails — never because verification genuinely lagged, which is what the log line
claims to be reporting.

Its trigger, `{"terminal_success": true}` in a tool result payload, has **no
first-party emitter**: `grep` over `lib/` finds only the policy that reads it.
Tests and canaries synthesize it. In production it can therefore only arrive
from an **MCP tool** — a third-party self-report that (a) declares the whole
conversation verified and (b) finalizes the turn, with no acknowledgement, no
shadow record, and no transform label, so it is invisible to the LL36 firing
audit.

**Not fixed here, deliberately.** It did not fire in this session, and every
speculative fix on this track has been reverted. What it needs first is a
firing record — the same delete-by-measurement discipline LL36 applies to the
guards. If a fix follows, the shape is to check the generations *before*
settling them, and to label the firing.

## Bottom line

The session is a clean pass and every decision in it is now explicable from the
log. The one open item from `cfaa8297` — "do not attempt a second fix before
the data exists" — is resolved: the data exists, and it says the first fix's
diagnosis was right and its branch simply has not been reached yet.
