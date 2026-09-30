# SEC4.4i OS-Enforced Write Containment (plan)

Status: 4i-a implemented 2026-09-24 (opt-in observe mode). The macOS foreground
`local_execute_command` containment route covers shell commands and command
chains (expanded from Python and Bash on 2026-09-30); general 4i-b onward
remains planned.

## Why

SEC4.4g asks a person to approve every native-shell command in a coding
project, because Caverno "cannot prove its write targets stay inside the open
project". That premise is true, and SEC4.4h only removes commands from the
shell path. It does not answer the premise. The SEC4.4g handoff already names
the only real answer: OS-enforced filesystem containment. Once the kernel
refuses a write outside the project, an approved or auto-reviewed shell command
can be called project-contained. SEC4.4g can then govern the commands that
cannot run contained, instead of every command.

What this buys, from the approval audit (17 days with prompts,
2026-08-26..09-23):
- 255 `opaque_host_write` prompts, 49% of all audited decisions.
- The bulk is ordinary project work: `grep`, `test`, `ls | tail`,
  `fvm dart`, `python3 -m unittest`, `git status` chains.
- The release script (`bash tool/release_ios_macos.sh`, 60 prompts)
  needs the keychain, `xcodebuild` and `notarytool`. It cannot run contained,
  and it should keep its fresh approval.

## Feasibility spike (2026-09-24, macOS 26, scratch directory)

`/usr/bin/sandbox-exec` with an allow-default profile that denies
`file-write*` except under the canonical project root, a per-command temp
directory, `/dev/null` and `/dev/fd/*`:

| Probe | Result |
| --- | --- |
| write inside the project | allowed |
| `../outside/x.txt` | denied (`Operation not permitted`) |
| write through `proj/link -> ../outside` | denied: the check is on the resolved vnode, which no lexical fence can do |
| `python3 -c` writing `/tmp/...` | denied |
| create `.git/hooks/pre-commit` under a `(deny ... .git/hooks)` rule | denied |
| `osascript` telling Finder to act, with `(deny appleevent-send)` | failed with -600. Probably the deny, but this still needs confirming |

Follow-up probes the same day:

- **Observe mode exists.** `(allow file-write* (require-not (subpath ROOT))
  (with report))` lets the write through and the kernel logs
  `Sandbox: bash(PID) allow file-write-create <path>`. Adding
  `(with message "<tag>")` puts a per-command tag in the log next to each
  report, and that includes reports from child processes (a `python3` spawned
  by the shell). Read with `/usr/bin/log show`. In zsh, `log` is a builtin and
  silently shadows the binary. A query over a one-minute window takes
  seconds, so collection has to be asynchronous and cannot sit on the tool
  result path.
- **Sandboxes do not nest.** Under any `sandbox-exec` profile, even pure
  observe, a child `sandbox-exec` fails with
  `sandbox_apply: Operation not permitted` (exit 71). SwiftPM evaluates
  `Package.swift` in a sandbox, so `xcodebuild`, `swift build`,
  `flutter build ios|macos` and `flutter run -d macos` can break when wrapped.
  61 of the 255 audited prompts invoke such a toolchain, mostly the release
  script, which needs the host anyway. Wrapping is therefore never blanket.
  Commands that reach one of these toolchains run unwrapped and keep SEC4.4g,
  and `containment: skipped_nested_toolchain` records that. That text trigger
  only ever removes containment, never an approval, so a miss costs
  observation and not safety.

The app does not carry `com.apple.security.app-sandbox`
(`macos/Runner/Release.entitlements`), so a child `sandbox-exec` is not nested
inside an app sandbox.

## Design

- **Launcher.** `_executeWithProcessHandle` and the `process_start` spawn
  wrap `sh -c` as `sandbox-exec -p <profile> sh -c <command>` on macOS. The
  profile is generated per call from the canonical project root and a fresh
  `TMPDIR`. Linux uses Landlock through a small helper when the kernel
  supports it. Windows has no equivalent, so it keeps SEC4.4g unchanged.
- **Write allowlist.** The project root and a per-command `TMPDIR` only. Tool
  caches (`~/.pub-cache`, `~/.dartServer`, `~/.gradle`, DerivedData, `~/fvm`)
  are denied by default. Adding one is an explicit, audited setting, because
  every cache directory is a place a contained command can plant code that an
  uncontained process runs later.
- **Read-only islands inside the project.** Two groups:
  - `.git/hooks`, `.git/config` and `.git/info` stay read-only. A contained
    command that can write a hook escapes the next time a person commits.
  - The executable-config set SEC4.2 already quarantines (`tool/safe-flutter`,
    `.envrc`, IDE task files) goes through the same test.
- **Escape hatches through services.**
  - `(deny appleevent-send)`: Caverno holds the apple-events entitlement, and
    Finder writes anywhere.
  - A restricted `mach-lookup` allowlist. `launchctl`, `open -a` and XPC
    helpers act outside the child's sandbox. This is the main engineering
    cost: too tight breaks DNS, TLS and git credential helpers, and too loose
    reopens the escape.
- **Gate change, last.** A command that will run contained drops SEC4.4g's
  fresh host-write requirement and goes back to the ordinary gate:
  auto-review, Full Access and the approval cache. A command the model or the
  user marks as needing the host (the release script) keeps the fresh
  approval. If the launcher is unavailable (Windows, an old kernel, a
  `sandbox-exec` failure), the command is not contained, so it also keeps the
  fresh approval.

## Slices

### Foreground shell command route

Foreground `local_execute_command` commands can use the ordinary Coding approval
gate when a macOS `sandbox-exec` launcher and an active project root are available.
Eligibility does not depend on the first executable: leading `cd`, command chains,
pipelines, redirections, environment assignments, and multiline scripts all share
the same containment route. Their entire shell invocation and child processes run
with project and per-command temporary writes only; Git metadata, Apple Events,
Mach services, and network access are denied. A literal out-of-project path,
background execution, another platform, or an unavailable launcher retains
the fresh host-write approval. If containment setup fails after gate selection,
execution fails closed. This route does not relax approvals for the general
`run_tests` and `process_start` paths.

Bash script files, `bash -c`, heredocs, pipelines, and their child processes
share the enforced profile. Across the entire command, known release scripts and
commands mentioning a nested sandbox toolchain or single-ampersand syntax retain
fresh host-write approval. The single-ampersand check is conservative: it can also prompt for a
quoted literal ampersand or `&>` redirection, while `&&` remains eligible. This
exemption only removes containment; it never grants approval. Dependencies hidden in a
script remain sandboxed and may fail, without an automatic uncontained retry.
The execution plan selects the same `workspace_command_containment` route for
both the approval scope and launcher, and legacy runners refuse that route.

The contained route can break scripts that need host caches, network access, or
service helpers. Those commands require a separate, explicitly approved host
execution path. The broader OS containment plan below still requires its
service-escape and release-gate work before other command families are relaxed.

1. **4i-a Launcher, observe-only, no gate change.** Approved native-shell
   commands, except the nested-toolchain set, run under a reporting profile
   that allows every write. Behaviour is unchanged. After the command exits,
   an asynchronous collector reads the tagged reports and records which paths
   outside the project each command wrote. That is the evidence 4i-b needs,
   gathered without breaking a single command. Implemented as
   `ShellWriteObservation`, opt-in through `CAVERNO_SHELL_WRITE_OBSERVATION=1`
   and foreground `local_execute_command` only. Observations go to the session
   log as `shell_write_observation` entries, so no fourth sensitive sink is
   added. `process_start` and `background: true` are not observed yet.
2. **4i-b Measure.** From the logs of real sessions, find how often contained
   commands fail on a denial, and for which directories. That decides the
   cache allowlist from evidence instead of guesses. Verify with
   `tool/check_fix_firings.py` that the launcher fired in real sessions and
   not only in tests.
3. **4i-c Service escapes.** Confirm the Apple Events denial, build the
   `mach-lookup` allowlist, and add regression probes for Finder, `launchctl`,
   `open`, and git hook writes.
4. **4i-d Relax SEC4.4g for contained commands.** The payoff. Release-gate
   review, because it changes who decides a class of shell commands.
5. **4i-e Linux Landlock.**

## Decisions this plan needs from a person

- Whether 4i-d is wanted at all. It hands contained shell commands back to
  auto-review and Full Access, which is less friction but also less human
  review. 4i-a to 4i-c are worth having without it.
- The default cache allowlist: none (safest, and `flutter`/`dart` break until
  configured), or the Dart/Flutter caches (works out of the box, with a larger
  planting surface).
- Whether contained commands keep network access. Egress is SEC4.3's
  territory, and this plan leaves it unchanged.

## Risks

- `sandbox-exec` has been deprecated for years, but it still ships and the
  Codex CLI and Claude Code sandboxes depend on it. If Apple removes it, the
  fallback is today's behaviour, not an open door.
- A profile bug fails open only if the gate change (4i-d) has shipped. Keeping
  4i-d last, behind the evidence from 4i-b, bounds that risk.
