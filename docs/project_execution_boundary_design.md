# Project Execution Boundaries

Date: 2026-10-01

## Task

Make ordinary coding commands eligible for local-LLM review without treating
human approval as runtime isolation. Extend the same enforced authority to
foreground commands, managed background jobs and Farm verification. Keep
host authority explicit and retain the approval audit trail.

This implements a macOS containment foundation. It does not implement a VM,
dependency provisioning, project capability grants or a complete autonomous
build environment.

## Context And Audit Decision

[The audit reassessment](worklog/security_command_approval_reassessment_2026-10-01.md)
reproduces SA-01 and SA-19 against disposable fixtures. Arbitrary project code
can construct paths that no command scanner sees. Direct argv execution has
the same authority problem as a shell. The audited requirement admits enforced
workspace containment as an alternative to a fresh human approval.

Use the LLM for user intent and the OS for execution authority. Command review
should receive useful context rather than optimize for the smallest token
budget. Model text and tool output cannot grant additional capabilities.

## Implemented Foundation

- `LocalCommandExecutionPlan` derives an immutable execution route from the
  selected project. Model-supplied containment flags are overwritten.
- macOS eligible native commands use `LocalShellLaunchPlan` and
  `LocalCommandWorkspaceContainment`. Foreground execution, managed background
  execution and the default Farm verification runner use that boundary.
- Writes are restricted to the canonical project and private scratch. `.git`
  and `.caverno` writes are denied. Reads are restricted to the project,
  scratch and installed OS/toolchain dependency directories. The root directory
  itself is readable because dyld needs it during startup; its descendants are
  not thereby granted. Device access is limited to stream/null/random devices.
- Network, Apple events, Mach lookup, POSIX IPC and signals to other sandbox
  instances are denied. Process information is limited to the same sandbox.
- Contained processes receive a reduced environment, private HOME/TMP/XDG
  locations, no user Python site packages and no global Git configuration.
  Parent environment inheritance is disabled.
- Auto-review receives the enforced boundary and more conversation/preview
  context. Synthesized compatibility `user` messages are labeled
  `untrusted_context`, so tool results cannot impersonate human authorization.
- Contained native commands do not reuse positive saved command rules or
  approval-cache grants. Auto-review evaluates them afresh. Untrusted influence
  can be reviewed for a contained local command; host actions retain the taint
  policy. A missing reviewer still requires a person.
- Existing approval-mode settings are preserved. Full Access still requires
  fresh review for tainted contained commands. Uncontained commands in a
  coding project retain fresh manual approval, including when a model requests
  `execution_scope: host`. A failed sandbox is never retried with host rights.
- Background job reuse includes the containment root, preventing a host job
  from satisfying a contained launch request.
- Farm verification can execute a user-authorized test against generated code
  inside the sandbox. An unavailable boundary stops verification. Farm opt-in,
  exact command authorization, concurrency, daily limits and merge restrictions
  are unchanged; no existing policy is automatically enabled.
- Descriptor redirection such as `2>&1` no longer masquerades as background
  syntax. Native Bash and internal output pipelines preserve failed producer
  status. Both `tail -5` and `tail -n 5` are recognized for pytest evidence;
  predicate chains remain unknown because the runner may never have started.

## Recommended Strict Environment

A long-running Farm should own an execution environment for each project.
Its writable SDK and caches belong to that environment, rather than the user's
shared host installation. Use a container or VM backend where appropriate,
with a native macOS backend for workflows requiring that platform.

| Concern | Required boundary |
| --- | --- |
| Files | Mount only the worktree and project-owned output/cache directories |
| SDKs | Provision versioned toolchains into the environment; keep global host SDKs read-only |
| Credentials | No inherited secrets; release credentials handled by a narrow host broker |
| Network | Explicit project grants or a dependency proxy; no unrestricted default egress |
| Processes | Environment-owned process tree; destroy it at task settlement |
| Resources | CPU, memory, storage, process-count and wall-time limits |
| Control plane | No host container socket, privileged mode, broad host mount or parent tools |
| Review | Local-LLM review against human task intent and the frozen capability profile |
| Audit | Record profile identity, route, user authorization and observed outcome |

The Docker documentation describes both namespaces/resource controls and the
risks of broad mounts and daemon access. A container name alone establishes
none of these restrictions: see [Docker Engine security](https://docs.docker.com/engine/security/).

A future project capability profile should be writable only through trusted
application settings. The model may request a change, but cannot approve it.
Approve a concrete expansion once, keep it versioned, and review ordinary
commands within that scope automatically. Publication and outbound messages
still follow the user's authorization. This replaces command-prefix whitelists
with a durable authority boundary.

## Compatibility And Remaining Work

- This foundation is a process sandbox, not a separate kernel or complete
  machine environment. Resource quotas and destruction of detached descendants
  are not established by the profile. File metadata visibility is not fully
  restricted. Project files and explicitly readable dependency caches remain
  accessible to project code.
- Dedicated Git execution and the embedded Python runtime remain separate
  authority-bearing routes. `GitTools` invokes native Git, whose hooks may run
  code; `PythonScriptRuntime` runs a long-lived serious_python worker inside
  the application process. They are not contained by this command-launch
  profile. A strict project environment must cover these routes too, or expose
  narrow broker operations instead of letting them inherit host authority.
- Visible shell background operators and known nested-sandbox/host toolchains
  retain the existing containment exclusions. Managed `background: true` and
  `process_start` jobs are supported. Unsupported scripts fail closed; never
  widen rights merely because a test cannot start.
- Read-only shared toolchains can require writes during startup. In the pinned
  Flutter SDK, `bin/internal/shared.sh` calls `update_engine_version.sh`, which
  writes `bin/cache/engine.stamp` and `engine.realm`. Strict automatic Flutter
  verification needs an environment-owned SDK/cache; this change does not grant
  write access to the shared SDK. Likewise, user-home tools and interactive
  signing/keychain flows need deliberate provisioning or a separate host route.
- Linux/Windows do not yet have an equivalent backend. Foreground/background
  commands keep the existing uncontained approval path; default Farm
  verification refuses to run without containment.
- A live local-LLM decision, full Watcher test run, unattended real-project
  Farm pass, device build and production signing/deployment remain unverified.

## Similar-Pattern Search And Verification

Inspected `Process.start` paths for local shell execution, background process
start and worktree verification; both the active ChatNotifier process-start
path and the extracted background handler use the shared execution plan.
Internal output trimming had the same masked-status defect as native pipelines
and was corrected. The review conversation builder had a synthesized-message
authority defect and was corrected.

Native disposable-fixture tests cover allowed project writes, computed and
symlink external reads/writes, network denial, private environment, unrelated
host-process signal denial, background/Farm routes and launch refusal. Gate
tests cover taint, fresh review despite cached grants, reviewer failure, user
intent labeling and the reported pytest command forms. Repository static
analysis and the relevant approval/command/Farm suites were run. The generated
Farm policy comments were regenerated with build_runner.

Verification results:

- `fvm flutter analyze --no-pub`: passed.
- Focused command, native containment, approval and Farm suites: 335 tests in
  13 suites passed.
- ChatNotifier, MCP/LSP, Farm runner and schema/teardown integration: 502 tests
  in 7 suites passed. The unchanged assistant-authored tool-result fallback
  failure was excluded after reproducing it independently against baseline
  `893e94560`.
- Affected file-size checks: 8 tests passed. Broader quality checks retain
  unrelated baseline size violations and a missing guardrail-manifest marker;
  this is not a clean full-suite result.
- Generated-source build, diff whitespace, translation JSON and document-link
  checks passed. Live/model/device verification remains as listed above.

Refactor boundaries: review-packet construction moved to
`tool_approval_review_packet.dart`; process launch policy moved to
`background_process_workspace_launch.dart` and `local_shell_launch_plan.dart`;
owner-root preparation moved to `local_command_request_preparation.dart`.
These moves keep the approval service, background manager and ChatNotifier
aggregate within their existing size budgets. Native route/gate tests cover
behavior preservation. Roll back the helper and its delegating call together
if route identity or environment behavior drifts.
