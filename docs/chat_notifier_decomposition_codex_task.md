# ChatNotifier Library Decomposition Program (Phase 1, Tranche 2)

Status: Tranche 2 landed on `main` as 7e66f3d9 on 2026-08-01. Slice 1, Slices
2a1-2a3 and 2b1-2b7, corrective prerequisites P1a-P14, and the WS4 and WS6
sub-slices are complete: the integrated verification and exact-model live
canary those were waiting on both ran green on the merged tree — 4,905 tests
across chat, quality and core, analysis clean, and all four canary scenarios
passing against `qwen3.6-27b-vision`, the tranche's first end-to-end run.

Closing it required repairing eight production regressions the slices' own
acceptance could not see, and reconciling three ledgers — the manifest, the
size budgets, and the boundary test's frozen marker set — with 27 collaborator
files that had been created without entries in any of them. Read "Regression
gate" before starting Workstream 5, 7 or 8; the rule that allowed those
regressions has been changed.

Achieved: the notifier library is 19,978 lines across 37 declared parts, down
from 23,093 and 43, with 71 collaborators holding 18,107 lines. That is 27% of
the way to the 11,546-line half-baseline. Note the ratio: 5.8 lines of new
collaborator per line the library lost, because the owner-fencing work rewrote
what it extracted rather than moving it. Workstreams 5, 7 and 8 remain.

Slice 1 completed on 2026-07-28 with a 9,375-line primary file, 42 declared
parts, a 22,900-line same-library aggregate, and a 132-line independent
formatter with 100% direct line coverage. Later slices remain separately gated
by the execution rule below.

Slices 2b1-2b7 completed on 2026-07-28 after their deterministic implementation,
focused coverage, budget, and audit evidence passed the corrected four-scenario
live canary at `http://192.168.100.241:1234/v1` with the loaded
`qwen3.6-27b-vision` model. The run observed the exact expected exit counts:
plan `{alpha: 2, beta: 2}`, coding `{alpha: 1, beta: 1}`, queued `{alpha: 2}`,
and handback `{alpha: 1, beta: 0}`, with no busy conversation left behind.

P1a completed on 2026-07-28 with the composite `ChatTurnOwner`, immutable
owner-keyed snapshots, and exact active-response capture/update/dispose
adapters. The focused suite passed 30 tests with 100% line coverage across the
owner type, snapshot registry, and active-response registry. The completion
tree is 9,374 primary lines, 13,526 declared-part lines, and 22,900
same-library lines. The refreshed turn-scope baseline is 132 ambient reads and
118 turn-reachable reads. Its exact-model canary passed the same four scenarios
with one exit per expected turn and zero busy owners.

P1b completed on 2026-07-28 by adopting the registered owner snapshot across
prompt, Python attachment, planning, project dispatch, continuation, saved-task,
final-claim, and goal-log paths. Its audit removed 18 ambient reads and added
none, lowering the checked-in baseline to 114 ambient and 101 turn-reachable
reads. The 53-test owner poison matrix, the 314-test ordinary ChatNotifier
suite, the 111-test common gate, analysis, and the canonical audit passed. The
full coverage verifier reached 4,256 passing root tests and retained only the
two pre-existing unrelated M33 release-packaging failures. The exact-model
four-scenario canary also passed with one exit per expected generation and zero
busy owners.

P2 implementation finished on 2026-07-29. Completed, content, command, hidden
assistant, content-tool, runtime lifecycle, project-root, mutation-generation,
and persistence evidence now stay with an exact `ChatTurnOwner`. Public send
and queued handoff paths return the producing owner; terminal success,
verification progress, cancellation persistence, and final saves use its
conversation rather than the visible conversation.

The 79-test direct helper matrix passed. It covered the ledger at 66/66 lines,
content state at 82/82, hidden evidence at 47/47, tool dedupe at 22/22, fenced
blocks at 8/8, owner snapshots at 102/102, scoped generation at 16/16, runtime
events at 29/29, persistence at 57/57, and active responses at 135/138. The
77-test detached-owner suite, 55-test caller handoff, 313-test ordinary
ChatNotifier suite, 124-test common gate, full analysis, and canonical audit
passed. The audit is now 86 ambient reads and 76 turn-reachable reads, down
28 and 25 respectively from P1b, with no additions.

The final-tree external gates were reviewed on 2026-07-29. The fresh coverage
verifier ran generation, package analysis and tests, and root analysis, then
reached 4,354 passing root tests. Its only failures were the two
pre-existing M33 release-packaging checks whose static direct-S3 expectations
lag the repository's CloudFront migration. Focused reruns reproduced both
failures without any P2, P4, or P5a file in their inputs.

P4 implementation finished on 2026-07-29. `FileMutationEvidencePolicy` now
owns the exact four-tool classification, the notifier-specific success
contract, result and argument path extraction, and result-first path
precedence. Exact-name consumers share that policy while their intentionally
different success predicates remain separate.

The 12-test direct suite covered all 33 executable policy lines. The 97-test
adjacent-policy suite, 313-test ordinary ChatNotifier suite, 125-test common
gate, full analysis, and canonical audit passed. The audit retained 86 ambient
and 76 turn-reachable reads while removing four obsolete methods from both the
scanned and reachable call graphs. Lifecycle readiness was restored at
`http://192.168.100.241:1234/v1`: `qwen3.6-27b-vision` reached `loaded` and the
35B model reached `unloaded`. The fresh verifier result above and the
exact-model canary below complete P4 and unblock WS5-4.

P5a completed on 2026-07-29. `ToolApprovalCache` now uses an exact
`ChatTurnOwner` outer key and retains the exact tool name, normalized
arguments, and unchanged optional state fingerprint in its inner key. Dispatch
resolves the immutable owner
snapshot once and explicitly passes a revocable `OwnerToolApprovalCache`
capability through every cache-capable local file, process, test, Git, SSH,
Python, BLE, serial, and Computer Use handler. Browser and participant approval
paths remain cache-free.

Terminalization clears and revokes only the finishing owner before releasing
its snapshot. `clearMessages` and provider disposal clear all owners, while a
new or visible turn no longer clears an unrelated active owner. Full-access and
bypassed approvals remain uncached; cached approvals still re-execute the tool,
and cached denials replay the exact `McpToolResult`. The approval-gate signature
migration touched 14 production files: cache-capable handlers received the
owner capability, while browser and participant paths adapted explicitly as
cache-free. Splitting it would leave some handler families able to use a stale
global cache contract. It does not include the P5b/P5c pending-DTO work.

The 12-test direct cache suite covered all 60 executable lines. The 78-test
detached-turn suite includes the A-approve, B-fresh-prompt, A-reuse, B-deny
poison sequence. The 313-test ordinary ChatNotifier suite, 126-test common
gate, full analysis, and canonical audit passed. The audit retained 749
reachable methods, 86 ambient reads, and 76 turn-reachable reads while reducing
all scanned methods from 783 to 780 and manifest entrypoints from 454 to 451.

The same fresh exact-model canary completed P2, P4, and P5a against the loaded
`qwen3.6-27b-vision` model at
`http://192.168.100.241:1234/v1`. Exact completed-turn counts were plan
`{alpha: 2, beta: 2}`, coding `{alpha: 1, beta: 1}`, queued `{alpha: 2}`, and
handback `{alpha: 1, beta: 0}`. Every expected generation emitted exactly one
`turn_exit`, and every scenario ended with zero busy owners.

P5b completed on 2026-07-30. Command, process, file, rollback, Git, SSH,
Python, skill, and routine approval requests now carry an exact
`ChatTurnOwner`. A typed authoritative registry owns request completers,
validates owner and ID together, removes requests before completion, and
settles owner-local or global cancellation with safe denial values. Terminal
and Remote Coding adapters resolve through that registry instead of trusting
the visible pending projection.

Every approval and execution path revalidates ownership after asynchronous
policy, evidence, credential, connection, and persistence boundaries. A
terminal owner therefore cannot perform a late side effect or persist a
remembered command rule. SSH explicitly disconnects when the owner expires
during connection, and the shared approval gate records expiration even when
it occurs during an allowing audit. The 1,014-line production migration spans
16 existing files because DTO ownership, authoritative resolution, lifecycle
cleanup, and final execution guards must land as one stale-resolution
contract. It adds no independent production file, part marker, manifest
transition, or generated output.

The 10-test ownership suite covered all 53 executable registry lines and
includes a real approve-then-clear tool-loop poison case with zero permission
persistence and zero command execution. The shared gate covered all 33
`resolveGate` lines. The 395-test ordinary suites, 131-test common gate, final
153-test ownership/adapter/structure gate, analysis, and canonical audit
passed. The tree is 9,191 primary lines, 13,586 declared-part lines, and
22,777 same-library lines. Audit exposure remains 78 ambient and 68
turn-reachable reads while the checked-in graph reports 784 methods and 751
reachable methods.

The full coverage verifier reached 4,395 passing root tests and retained only
the two known M33 release-packaging checks whose direct-S3 expectations lag
the CloudFront migration. A focused rerun reproduced the same unrelated
blockers. The fresh exact-model canary then passed all four scenarios in
2 minutes 40 seconds at `http://192.168.100.241:1234/v1`, with each expected
generation emitting one `turn_exit` and every scenario ending with zero busy
owners.

P5c completed on 2026-07-30. Computer Use, browser, BLE, serial, and
participant approval requests now carry an exact `ChatTurnOwner` and share the
authoritative typed registry introduced by P5b. Owner, ID, and request type are
validated together before a request is consumed. Terminalization cancels only
the finishing owner, global clearing settles every request, and the terminal
adapter no longer trusts a visible pending projection. The current Remote
Coding wire protocol remains unchanged and does not transport these five
approval families.

Every handler revalidates the exact owner after asynchronous approval or
auto-review and immediately before a side effect. Browser and Computer Use
cannot start post-expiry follow-up work; BLE and serial compensate an
in-flight stale success with disconnect and close respectively; participant
tools remain cache-free and cannot execute after their parent turn expires. A
112-line independent coordinator serializes same-device BLE attempts and uses
owner plus attempt-token identity so an expired attempt preserves both
pre-existing and successor connections.

The eleven-test device ownership suite covers cross-conversation and
same-conversation poison cases, registry index cleanup, safe cancellation,
zero late browser execution, Computer Use cancellation before blocked-policy
audit, late Computer Use success without a follow-up observation, BLE
predecessor/successor ordering, and BLE/serial rollback. The
17-test terminal suite and 45-test focused approval/UI gate, 395-test ordinary
ChatNotifier suites, and 132-test common gate passed with analysis and the
canonical audit.

The P5c tree is 9,191 primary lines, 13,578 declared-part lines, and 22,769
same-library lines with matching ceilings. The historical manifest and
generated outputs are unchanged; the independent coordinator is budgeted at
112 lines. Audit exposure remains 78 ambient and 68
turn-reachable reads; the reviewed graph contains 787 methods and 755 reachable
methods. The fresh coverage verifier reached 4,412 passing root tests and
retained only the two known unrelated M33 CloudFront-migration mismatches.

The fresh exact `qwen3.6-27b-vision` canary passed all four scenarios in
2 minutes 53 seconds at `http://192.168.100.241:1234/v1`. Plan owners were
`4087205b-9dee-48e6-b50b-a4ab1320f2d8` at generations 2 and 6 and
`d3c4b89c-c6e2-44fb-a21d-a283658320bf` at generations 4 and 7. Concurrent
coding owners were `b865aba8-eacf-4ad8-98ba-71e8c4aca52c` at generation 2 and
`3b338bf1-c505-4b91-bc02-9f150a01516e` at generation 3. Queued work used
`384acfe1-df73-47b4-b5b0-c2b96d41fdf5` at generations 1 and 2. Handback used
`a2a3b861-9535-4d39-892a-24a15a0d028e` at generation 2 while
`41b29110-a9af-4cc7-a931-63dbd06708e6` emitted no turn. Every expected
generation emitted exactly one `turn_exit`, and every scenario ended with zero
busy owners.

P5c unblocks WS6-11a, WS6-11b, WS6-14, WS6-16, and the WS8-9 approval
adapter. At that checkpoint WS6-1 waited only for P11; P11 is now complete.

P6 completed on 2026-07-30. `FileRollbackCheckpointStore` now
keeps single-change history, active turn checkpoints, and completed checkpoint
stacks under an exact `ChatTurnOwner`. A conversation-level chronological index
stores the exact owners of non-empty completed turns so the conversation-scoped
preview can find the correct checkpoint without synthesizing an owner from the
current generation. The preview carries that exact owner and a monotonic
checkpoint token through confirmation, so neither a newer owner nor a newer
checkpoint from the same owner can replace the rollback target. Empty turns do
not replace the index; successful rollback reveals the preceding completed
owner, while failed rollback remains retryable under the same owner.

Chat file mutations use the new exact-owner `McpToolService.executeFileTool`
boundary. The ordinary `executeTool` path remains ownerless, allowing routine,
diagnostic, and Worktree Agent mutations to retain their existing execution
behavior without entering chat rollback history. ChatNotifier begins and ends
each checkpoint with the owner captured at `_sendWithTools` entry, including
detached completion in `finally`; approved write, edit, delete, and
single-file rollback calls use the owner already bound to their approval
cache. `CheckpointVerificationBestOfNRunner` now requires an owner and cannot
discard another turn's checkpoint.

The checkpoint store is provided independently of the settings-sensitive
`McpToolService`, so a service rebuild cannot split an active checkpoint.
Completed state is capped per conversation, all conversation deletion paths
retire their state, and owner/conversation tombstones reject late asynchronous
resurrection. Provider disposal clears all retained checkpoints.

The implementation changes 423 production lines across ten existing files
(323 additions and 100 deletions). The owner-keyed store is 442 lines and has a
new exact shrink-only budget. The filesystem handler shrank from 343 to 339
lines. The notifier remains 9,191 primary lines with 13,578 lines across 42
declared parts and a 22,769-line same-library aggregate. `McpToolService` is
1,191 primary lines and 1,283 lines with its declared part; both ceilings remain
below their pre-P6 counts. The provider and conversations notifier are newly
governed at 176 and 1,838 lines. No part directive, historical manifest record,
discovery marker, generated output, or serialization schema changed.

The 133-test focused data/provider suite passed and covered all 187 executable
store lines. The 551-test notifier, UI, Worktree Agent, deletion lifecycle,
provider-rebuild, and size suite and the 137-test common gate passed with
analysis and the canonical audit. The reviewed
audit remains at 787 methods, 445 manifest entrypoints, 755 reachable methods,
78 ambient reads, and 68 turn-reachable reads. The fresh full verifier reached
4,433 passing root tests and retained only the two known unrelated M33
release-packaging failures whose direct-S3 expectations lag the CloudFront
migration.

The exact `qwen3.6-27b-vision` canary passed all four scenarios in 2 minutes
27 seconds. Plan owners were `9468f205-8a7e-4d81-93a3-f18d1c545e3b` at
generations 2 and 6 and `b32c2e7d-4ad3-4f7a-8bcf-b5d190a832dc` at generations
4 and 7. Coding owners were `678d64b6-319a-4a23-a173-b3e815d1717d` at
generation 2 and `e1bb9d5d-f32b-4f77-bc71-9a74c6d7d6b9` at generation 3.
Queued work used `b1c02aa6-9cd8-4104-bfba-a09b4cc1b8dd` at generations 1 and
2. Handback used `c9208dad-e029-4718-a978-581ed4f744aa` at generation 2 while
`ca7e888a-471f-4fb7-b6c5-28681c77f80a` emitted no turn. Every expected
generation emitted exactly one `turn_exit`, every scenario ended with zero
busy owners, and P6 unblocks WS4-6 and WS6-4.

P12 completed on 2026-07-30. The former 715-line
`CodingCommandOutputGuardrailService` is now a 133-line compatibility facade
over a 298-line output issue detector and a 356-line preflight detector. The
facade preserves its constructor, constants, static entrypoints, exported issue
models, JSON feedback, issue ordering, three-issue cap, and recursive-feedback
suppression without duplicating detector logic.

The 30 direct P12 tests and 167-test facade/caller suite passed. Coverage
reached 35/35 executable facade lines, 107/107 output-detector lines, and
135/135 preflight-detector lines. All three files have exact shrink-only
budgets below 500 lines. P12 intentionally leaves the `command-guardrails`
manifest part at `remaining`; WS7-8 owns final notifier adoption and the
transition to `partial`.

P14 completed on 2026-07-30. The 21-line
`HiddenAssistantEvidenceScorer` exposes the pure evidence scoring matrix
without constructing `ToolTerminalResponsePolicy` or its callback bag. The
policy delegates to the scorer and shrank from 743 to 725 lines. Exact lexical
compatibility remains intact, including the historical `incomplete` substring
match and additive conflicting evidence.

The 19-test scorer and policy suite passed. Direct scorer coverage reached
12/12 executable lines, and its exact 21-line size budget passed. P14 adds no
part, marker, generated output, or manifest transition and unblocks WS5-3.

P3a completed on 2026-07-29. The 117-line
`TurnFinalizationStateRegistry` now owns turn-exit hints, ordered and
deduplicated transform IDs, accepted goal-completion claims, and shadow goal
outcomes under an exact `ChatTurnOwner`. Explicit begin/reset/take/dispose
lifecycle operations preserve visible-turn semantics and prevent detached
claims from leaking into another owner. P3b later added detached-owner claim
consumption and final completion evidence. Disposed-generation watermarks reject
late writes and prevent state resurrection.

The four direct registry tests covered all 50 executable lines. The 80-test
detached-owner suite includes transform/reset and cross-owner
goal-claim/shadow isolation cases; the 313-test ordinary ChatNotifier suite,
five read-only guard tests,
127-test common gate, full analysis, and canonical audit passed. Recognizing
`ChatTurnOwner` as a first-class audit identity and removing four ambient
message reads lowered the audit to 82 ambient and 72 turn-reachable reads.
The fresh full verifier reached 4,361 passing root tests and retained only the
two known M33 release-packaging checks whose direct-S3 assumptions lag the
CloudFront migration. The loaded `qwen3.6-27b-vision` canary passed all four
scenarios with one `turn_exit` per expected generation and zero busy owners.

P3b completed on 2026-07-29. The 211-line
`TurnGoalCompletionEvidenceRegistry` and `TurnGoalCompletionFinalizer` replace
the flat completion-evidence value with exact-owner begin, combine, reconcile,
seed, and disposal operations. Finalization captures the matching P3a claim and
shadow outcome before persistence, targets the detached owner's conversation,
freezes the visible-path goal token delta before later detachment can overwrite
it, and passes the same immutable evidence to policy, logging, and any
explicitly seeded hidden successor. Detached-at-entry turns still contribute
zero. P10b has since replaced the shared raw-usage read with request-local
terminal metadata. The flat value and boolean preserve flag are removed.

Eleven direct tests covered all 59 executable lines. The 82-test detached suite
covered failed-evidence isolation, explicit-only successor seeding, and
exact-owner accepted-claim completion, including 11-versus-97 late-detachment
token-accounting poison; the 313-test ordinary suite, 40 compatibility tests,
128-test common gate, analysis, and canonical audit passed.
The audit fell to 78 ambient and 68 turn-reachable reads, with four removals and
no additions. The full verifier reached 4,375 passing root tests and retained
only the two known M33 CloudFront-migration mismatches. The exact
`qwen3.6-27b-vision` four-scenario canary passed with one `turn_exit` per
expected generation and zero busy owners.

P7, P8, P9, P10a, P10b, P11, and P13 completed focused acceptance on
2026-07-30. Background process state, SSH sessions, subagent tasks, response
metadata and timers, conversation taint, and participant stop/pause control are
now exact-owner state. P10a supplies the request-local streaming terminal
envelope consumed by P10b. The primary governed files measure 459/457 lines for
background tools/monitoring, 279 for `SshService`, 210 for
`SubagentTaskNotifier`, 27 for terminal metadata, 107 for response metadata, 82
for taint state, and 129 for participant control. Recorded executable coverage
is 195/203 and 175/181, 110/115, 76/76, 2/2, 47/47, 29/29 plus 4/4 for the
taint recorder, and 51/51 respectively. The P10b 92-test
registry/detached-turn suite and 157-test focused integration gate passed.

WS4-1 also completed focused acceptance on 2026-07-30. The independent
145-line `PythonAttachmentRepairPolicy` preserves the exact decision matrix and
repair prompts, while the 162-line notifier part adapts only the registered
owner's messages and attachment state. Its 15 focused tests cover 48/48 policy
and 43/43 adapter executable lines, including visible-thread versus registered
owner poison. The manifest now records `python-attachment-repair` as `partial`
with `python-attachment-repair-policy` as its exact collaborator.

WS4-2 completed its extraction on 2026-07-30. The independent 209-line
`DuplicateToolResultRecovery` preserves reverse-most-recent result reuse,
fallback filtering, payload compatibility, and final deduplication against an
explicit owning project root. Its direct tests cover result reuse, recursively
immutable argument snapshots, path identity under distinct roots, and
compatibility with the shared filesystem path resolver. The old 85-line part
and directive are absent, and the manifest now records `duplicate-recovery` as
`extracted`. Post-hardening revalidation passed all 13 direct tests with
85/85 executable lines covered. The exact committed tree also passed Flutter
analysis and the 159-test manifest, size, structural-boundary, and turn-scope
gate.

WS6-12 and WS6-13 completed their extractions on 2026-07-31. `save_skill` and
`create_routine` now execute through owner-scoped approval, persistence,
settlement, and compensation receipts. The old skill and routine handler parts
and directives are absent, and their manifest records are `extracted` with the
217-line `SaveSkillToolHandler` and 490-line `CreateRoutineToolHandler` as exact
collaborators. Direct coverage reached 92/92 and 166/169 executable lines.
The 153-test focused runtime suite, five ChatNotifier integration tests, and
targeted analysis passed. The exact committed tree also passed the 146-test
manifest, size, structural-boundary, and turn-scope gate.

WS6-10 completed focused acceptance on 2026-07-31. The independent 492-line
`PythonScriptToolHandler` receives the exact owner's immutable messages and
owns validation, eligible attachment selection, staging, approval, execution,
cache settlement, and cleanup fencing. Terminalization retires only the exact
owner's staging and execution authority. The old 126-line Python handler part
and directive are absent, and the manifest records `python-handlers` as
`extracted`. Forty-two direct tests cover 151/158 executable lines, including
visible-thread attachment poison, owner retirement at each pre-effect
boundary, duplicate allocation, cleanup settlement races, and uncertain
post-effect results. The 96-test runtime suite, three ChatNotifier integration
tests, targeted analysis, and the exact focused tree's 159-test manifest,
size, structural-boundary, and regenerated turn-scope gate passed.

WS6-1 completed focused acceptance on 2026-07-31. The independent 489-line
`TurnToolApprovalCoordinator` owns exact-owner allow and denial reuse,
deterministic execution identity, approval precedence, auto-review request
construction, warning variants, denial payloads, and best-effort audit
recording. Four narrow runtime ports keep notifier, provider, UI, and
persistence dependencies outside the collaborator. Thirty-two focused tests
cover remembered decisions, manual escalation, every automated gate branch,
audit and reviewer failures, immutable request boundaries, and cross-thread
and cross-generation poison cases. Target coverage reached 163/167 executable
lines (97.60%). The manifest records `approval-handlers` as `partial`; legacy
caller
adapters remain until their typed Workstream 6 handler slices adopt the shared
coordinator. The focused analyzer and structural quality gates passed.

WS6-2 completed focused acceptance on 2026-07-31. The independent 259-line
`LspGoToDefinitionToolHandler` receives an immutable exact-owner operation
identity and project root, validates one-based positions, resolves the path,
and maps ordered LSP locations without consulting visible state. Its 296-line
runtime adapter fences session acquisition and collection, conditionally
compensates only a session started by the expired operation, and returns an
uncertain receipt when ownership or settlement cannot be proven. Twenty-six
focused tests cover 93/94 handler lines (98.94%), all validation and URI
branches, unavailable/error payloads, peer-thread and successor-generation
poison, and session-effect settlement. The registry binding now requires an
exact owner; the historical local-file part falls from 1,191 to 1,041 lines,
declared parts fall from 11,225 to 11,123 lines, and the same-library aggregate
falls from 20,137 to 20,035. The manifest appends the exact collaborator to the
existing `partial` `local-file-handlers` record.

WS6-3 completed implementation and focused acceptance on 2026-07-31. The
434-line `FileMutationToolHandler` now owns write, edit, and delete validation,
approval, conflict checks, execution settlement, and rollback-record
coordination through immutable exact-owner requests. A receipt-backed
filesystem boundary serializes each resolved path, rejects symbolic-link
targets and stale fingerprints, and compensates owner expiry without allowing
a successor mutation to cross the rollback handoff. All three registry names
dispatch through the handler. Fifteen direct tests covered 105/105 executable
handler lines; the 108-test focused runtime and filesystem suite and four
ChatNotifier integration cases passed. The manifest records
`local-file-handlers` as `partial` with `file-mutation-tool-handler`, and the
focused tree measured 9,073 primary lines, 12,964 declared-part lines, and a
22,037-line same-library aggregate.

WS6-4 completed implementation and focused acceptance on 2026-07-31. The
225-line `FileRollbackToolHandler` now binds history lookup, approval, and
execution to one exact owner and immutable checkpoint token. The production
adapter rejects owner mismatch and successor checkpoints before restoration
and reports post-effect uncertainty conservatively. Thirty-three direct tests
covered 85/86 executable handler lines, and the 33-test runtime,
conditional-store, and transaction-fence suite passed. The
`local-file-handlers` manifest record remains `partial` with
`file-rollback-tool-handler` appended.

WS6-5 completed focused acceptance on 2026-07-31. The independent 404-line
`LocalCommandToolHandler` receives immutable exact-owner requests and narrow
approval, permission, and execution ports. It resolves all working directories
inside the owner's project boundary, preserves permission and manual-approval
behavior, and treats unproven post-dispatch effects as uncertain. The 653-line
runtime adapter freezes permission rules per invocation, compensates stale
remembered-rule writes, and binds execution to the exact owner, call, tool, and
argument digest. Forty-one handler tests cover 161/169 executable lines
(95.27%), and the 60-test handler/runtime suite plus stale-owner and approval
replay integrations pass. The local-file part falls from 1,041 to 1,029 lines;
the 8,912-line primary is unchanged and the same-library aggregate falls from
20,035 to 20,029. The manifest appends `local-command-tool-handler` to the
existing `partial` record.

WS4-6 completed focused acceptance on 2026-07-31. The independent 111-line
`FileTurnRollbackService` preserves unavailable-service behavior and isolates
preview and rollback behind a narrow callback checkpoint port. Its preview
copies path lists defensively, while rollback forwards the exact owner and
immutable checkpoint token without rewriting result fields. Nine direct tests
cover absent ports and previews, successful and failed rollback, complete
result propagation, cross-owner isolation, and callback-factory behavior. The
historical 22-line notifier part remains as a public-API delegate and its
manifest record is `partial`; moving it into the primary file would exceed the
current exact 9,073-line primary ratchet.

WS4-3 completed focused acceptance on 2026-07-31. The independent 75-line
`ReferencedSpecificationLoader` receives the project root already resolved
from the owning conversation and has no provider, Zone, or visible-project
fallback. It preserves first-reference selection, byte limits, compatible
filesystem failures, and inside-root enforcement while rejecting traversal and
absolute references. Twelve direct tests cover relative and Unicode paths,
missing files, directories, byte boundaries, malformed requests, operation
ordering, and read failures. The `prompt-context` manifest record is `partial`,
and its historical part shrinks from 286 to 260 lines.

WS4-4 completed focused acceptance on 2026-07-31. The independent 135-line
`SecondaryCompletionRouter` receives immutable provider, primary endpoint,
enabled endpoint, selected model, and fallback model facts. Workflow, task,
goal-suggestion, memory-extraction, and approval-review callers pass their
route explicitly, while planning attempts emit only narrow route metadata.
Fifteen direct tests cover assigned, empty, missing, unhealthy, fallback,
non-compatible, immutable, logging, and failure routes at 27/27 executable
lines. The legacy mesh-routing part is removed and its manifest record is
`extracted`.

WS4-5 completed focused acceptance on 2026-07-31. The independent 179-line
`ExecutionSnapshotObserver` freezes owner inputs, deduplicates by conversation
and snapshot, preserves redacted diagnostics, and emits only bounded shadow
fields through a narrow port. A 32-line data adapter maps those fields onto the
session log store without exposing it to the observer. Twelve direct tests
cover 63/63 executable lines, and the detached-plan poison test proves that a
first A snapshot logged while B is visible remains in A's session context.
The `prompt-context` record remains `partial` and its historical part shrinks
from 260 to 254 lines.

WS7-4 completed focused acceptance on 2026-07-31. The existing independent
`AnalysisOptionsLintEditGuard` now builds the final blocked tool result while
preserving its public detector semantics. The notifier wrapper is removed and
the tool-loop batch calls the guard directly. Seventeen direct tests cover
164/164 executable lines, including exact result fields, quoted YAML comments,
and owner-scoped process output. The `command-guardrails` record is `partial`
and its historical part shrinks from 1,027 to 1,001 lines.

WS7-8 completed focused acceptance on 2026-07-31. The existing split command
guardrail now builds the final preflight result in its 161-line facade while
its 298-line output and 356-line preflight detectors remain below 500 lines.
Project argument resolution stays at the owner-scoped tool-loop caller. Eight
direct tests cover 43/43 facade executable lines and exact result fields. The
notifier wrapper is removed and `command-guardrails` shrinks from 1,001 to 963
lines.

WS7-5 completed focused acceptance on 2026-07-31. The independent 151-line
`GitTagFormatInspectionGuard` receives immutable tool-call, owner-resolved
argument, and executed-result snapshots. Fourteen direct tests cover 58/58
executable lines across tag and inspection variants, shell controls, exact
payloads, nested immutability, and owner-repository poisoning. The primary
falls to 8,934 lines and `command-guardrails` shrinks from 963 to 859 lines.

WS7-6 completed focused acceptance on 2026-07-31. Both timeout-retry call sites
now pass immutable owner-turn snapshots to the independent 96-line
`TimedOutCommandRetryGuard`. Eighteen direct tests cover 30/30 executable lines
across command classification, normalized matching, timeout variants, recency,
exact payloads, nested immutability, and owner-turn poisoning. The primary
falls to 8,925 lines, `command-guardrails` shrinks from 859 to 812 lines, and
the same-library aggregate falls to 20,840 lines.

WS7-1 completed focused acceptance on 2026-07-31. The stateless 53-line
`GoalValidationProbeGuard` now owns validation-only effect classification,
exact blocked-result construction, and result detection. Four direct tests
cover 13/13 executable lines and all eleven command-effect classes, including
false mode, exact payloads, non-object JSON, and malformed JSON. The primary
remains at 8,925 lines and `command-guardrails` shrinks from 812 to 776 lines.

WS7-2 completed focused acceptance on 2026-07-31. The tool-loop batch now
resolves and freezes the owning workflow's blocking assumptions before calling
the independent 64-line `MaterialContractAssumptionGuard`; the guard never
reads the visible conversation. Eight direct tests cover 18/18 executable
lines, all eleven effects, question normalization and ordering, exact fields,
and owner/visible workflow poisoning. `command-guardrails` shrinks from 776 to
733 lines and the same-library aggregate falls to 20,778 lines.

WS7-3 completed focused acceptance on 2026-07-31. The independent 142-line
`CommandDiagnosticVerifierReplayGuard` receives owner focus, retry-qualified
command identity, effect, and frozen pending calls, reuses the established
policy, and returns typed log fields. Thirteen direct tests cover 43/43
executable lines across focus and identity gates, mutation ordering, exact
payload and logging facts, nested immutability, malformed input and results,
and owner/visible-turn poisoning. `command-guardrails` shrinks from 733 to 663
lines and the same-library aggregate falls to 20,722 lines.

WS7-9 completed focused acceptance on 2026-07-31. The independent 178-line
`SavedValidationCommandGuard` receives exact owner, saved command, and project
root facts. Fourteen direct tests cover 66/66 executable lines across command
equivalence, shell operators, path-resolved command shapes, exact result
fields, nested immutability, cross-conversation saved-command poisoning, and
owner-root poisoning. `command-guardrails` shrinks from 663 to 529 lines and
the same-library aggregate falls to 20,594 lines.

WS7-10 completed focused acceptance on 2026-07-31. The independent 135-line
`SavedTaskTargetScopeGuard` receives the owner task, owner project root, and
immutable tool call, while active-task selection remains at the owner-keyed
notifier boundary. Eighteen direct tests cover 48/48 executable lines across
the complete path matrix, validation executable expansion, exact fields,
nested immutability, visible-task poisoning, and visible-root poisoning. The
old notifier test seam is removed, the primary falls to 8,924 lines,
`command-guardrails` shrinks from 529 to 429 lines, `tool-loop-batch` grows
from 747 to 751 lines, and the same-library aggregate falls to 20,497 lines.

WS7-11 completed focused acceptance on 2026-07-31. The independent 115-line
`UnexecutedFileMutationBeforeCommandGuard` receives immutable owner identity,
command, pending calls, executed results, and assistant content snapshots.
Twelve direct tests cover 38/38 executable lines across command applicability,
pending and executed mutation evidence, claim detection and clipping, exact
fields, recursive immutability, cross-owner result poisoning, and cross-owner
claim poisoning. The primary falls to 8,923 lines, `command-guardrails`
shrinks from 429 to 376 lines, `tool-loop-batch` grows from 751 to 754 lines,
and the same-library aggregate falls to 20,446 lines.

WS7-12 completed focused acceptance on 2026-07-31. The independent 55-line
`ToolLoopExhaustionPolicy` receives seven named immutable loop and owner-turn
evidence facts while bounded recovery orchestration remains in the notifier.
Six direct tests cover 10/10 executable lines across the exact limit,
zero-budget behavior, every individual blocker, combined blockers, and the
allowing case. The primary falls from 8,923 to 8,922 lines,
`command-guardrails` shrinks from 376 to 365 lines, and the same-library
aggregate falls to 20,434 lines.

WS7-13 completed focused acceptance on 2026-07-31. The independent 93-line
`GitWriteConfirmationPolicy` receives the exact owner, immutable pending
calls, and current assistant content while the notifier keeps ask-and-wait
orchestration. Thirteen direct tests cover 32/32 executable lines across Git
classification, English and localized question matrices, mixed batches,
recursive immutability, non-JSON rejection, cross-owner question poisoning,
and cross-owner pending-call poisoning. The primary remains at 8,922 lines,
`command-guardrails` shrinks from 365 to 311 lines and remains `partial`, and
the same-library aggregate falls to 20,380 lines.

WS7-14 completed focused acceptance on 2026-07-31. The independent 71-line
`ModelSwitchSettingsPolicy` returns typed route identity, previous-model
preparation, and data-source rebuild decisions from previous and next settings.
Fourteen direct tests cover 30/30 executable lines across providers, demo
transitions, raw and trimmed credentials and URLs, models, reasoning effort,
session logs, unrelated fields, and exact route IDs. `context-surgery` becomes
`partial`; the primary remains at 8,922 lines, its part shrinks from 268 to 218
lines, and the same-library aggregate falls to 20,330 lines.

WS7-15 completed focused acceptance on 2026-07-31. The independent 89-line
`ModelSwitchHandoffRegistry` keys pending briefs by conversation and forced
prompt compaction by exact turn owner. Seventeen direct tests cover 26/26
executable lines, including wrong-owner poison cases, and the public-path
notifier integration test passes. The primary falls to 8,921 lines,
`context-surgery` falls to 160 lines, the notifier test root falls to 18,613
lines, and the same-library aggregate falls to 20,271 lines.

WS7-16 completed focused acceptance on 2026-07-31. Both compact-result call
sites pass the registered interaction owner's conversation to the independent
20-line `ContextSurgeryProtectedPathPolicy`. Ten direct tests cover 7/7
executable lines, and the three existing Slice 2b6 poison integrations pass in
both owner directions. The primary remains at 8,921 lines,
`context-surgery` falls to 147 lines, `final-answer-recovery` falls to 286
lines, and the same-library aggregate falls to 20,257 lines.

WS7-17 completed focused acceptance on 2026-07-31. Prompt construction passes
an immutable MCP catalog snapshot and request facts to the independent
116-line `RequestToolObservationCollector`; it never passes a service or
mutates advertised names. Fifteen direct tests cover 37/37 executable lines,
including plan-drafting separation and sequential-owner poison cases. The
primary remains at 8,921 lines, `context-surgery` falls to 87 lines,
`prompt-context` becomes 268 lines, and the same-library aggregate falls to
20,211 lines.

WS7-18 completed focused acceptance on 2026-07-31. The independent 130-line
`ContextSurgeryObservationAccumulator` keys partial prompt, tool-result,
definition, and MCP-name observations by exact turn owner and routes changed
snapshots to that thread. Thirteen direct tests cover 49/49 executable lines,
and three detached-owner integrations pass. The primary falls to 8,914 lines,
`context-surgery` falls to 79 lines, 37 declared parts contain 11,295 lines,
and the same-library aggregate falls to 20,209 lines.

WS7-19 completed focused acceptance on 2026-07-31. Both edit-result paths pass
the exact turn owner and explicit normalized baseline to the independent
191-line `ModelEditApplyTelemetryRecorder`. Owner validation surrounds settings
persistence, and edit-failure sampler feedback cannot continue after the owner
is replaced. Thirteen recorder tests cover 28/28 executable lines, with four
store and three runtime adapter tests covering persistence order and delayed
owner poisoning. The primary falls to 8,913 lines,
`tool-result-telemetry` falls to 130 lines, 37 declared parts contain 11,281
lines, and the same-library aggregate falls to 20,194 lines.

WS7-20 completed focused acceptance on 2026-07-31. Five runtime sampler
feedback paths now construct immutable owner-and-baseline events for the
independent 245-line `RuntimeSamplerFeedbackRecorder`. Planning parsers receive
a typed event binding rather than a notifier callback, while tool-loop callers
send malformed and repetition events directly. Nineteen direct tests cover
49/49 executable lines (100%), including all assistant modes and request
classes, null updates, persistence errors, snapshot poisoning, and never-throw
behavior. The primary falls from 8,913 to 8,912 lines,
`tool-result-telemetry` falls to
76 lines, 37 declared parts contain 11,246 lines, and the same-library
aggregate falls to 20,158 lines.

WS7-21 completed focused acceptance on 2026-07-31. Both streamed content-tool
failure paths now use the independent 32-line `ContentToolFailureFormatter`.
Eight direct tests freeze null-only defaulting, trimming, case-insensitive
classification, overlap precedence, fallback behavior, tool names, escaping,
and exact JSON output at 11/11 executable lines (100%). The primary remains at
8,912 lines, `tool-result-telemetry` falls to 55 lines, 37 declared parts
contain 11,225 lines, and the same-library aggregate falls to 20,137 lines.

WS5-8 completed focused acceptance on 2026-07-31. The independent 73-line
`ProcessStartResultPolicy` receives one tool call, dispatch result, and exact
dispatch timestamp. It preserves the five-second tolerance, duplicate-job
exception, copied metadata, error text, and required action without a clock,
monitor, or notifier dependency. Eight direct tests cover non-process and
failed results, malformed payloads, timestamp validation, duplicates, the
exact boundary, fresh results, and compatible stale diagnostics. The
`tool-loop-batch` manifest record is `partial`, and its historical part shrinks
from 738 to 685 lines.

WS5-1 completed focused acceptance on 2026-07-31. The independent 423-line
`CodingContinuationRecoveryPolicy` owns recovery-code selection, supported-tool
detection, continuation-only and prose-only classification, recovery payloads,
partial-progress notices, prompts, and stable user-facing copy. The notifier
passes immutable tool definitions plus the registered owner's user text,
workspace mode, pending workflow, save-skill generation, terminal-blocker
decision, and bracketed request. Twenty-two direct tests cover every recovery
code and gate, English and CJK markers, structured deferral, partial command
progress, immutable inputs, and owner/visible-thread poisoning. The
`coding-continuation-recovery` record is `partial`, and its historical part
shrinks from 444 to 126 lines.

WS5-2 completed focused acceptance on 2026-07-31. The independent 268-line
`TurnFinalizationRecoveryPolicy` owns completed-answer, future-action,
streamed-answer compatibility, successful-evidence, candidate selection, and
prefix extraction decisions. The notifier supplies immutable tool results for
the exact owner plus explicit timeout, validation, unexecuted-action,
saved-validation, file-mutation, and command-execution evidence. Twenty direct
tests cover the full decision matrix, English and CJK markers, boundary
lengths, immutable snapshots, and owner/visible-generation poisoning. A
Notifier integration test proves streamed answers and evidence are selected
for the requested generation. The `turn-finalization-recovery` record is
`partial`, and its historical part shrinks from 373 to 304 lines.

WS5-4 completed focused acceptance on 2026-07-31. The independent 64-line
`CodingVerificationMutationSignature` freezes the exact owner's tool results,
reuses `FileMutationEvidencePolicy`, resolves Dart paths against the owning
project root, and preserves source order, duplicates, and compatible JSON
fields. Nine direct tests cover failed and already-applied mutations,
non-mutation and non-Dart evidence, result/argument path precedence,
relative/absolute paths, immutable inputs, ordering, duplicates, and distinct
owner roots. The `coding-verification-feedback` record remains `partial`, and
its historical part shrinks from 331 to 313 lines.

WS5-5 completed focused acceptance on 2026-07-31. The independent 281-line
`UnexecutedFinalAnswerToolRequestPolicy` freezes owner evidence, records
tag-embedded final-answer tool calls, preserves occurrence IDs and exact
diagnostic JSON, classifies structured and prose requests, and returns notice,
exit, and transform decisions without state mutation. The Notifier verifies
the exact generation owner both before analysis and before applying results,
exit metadata, transforms, or message content. Eighteen direct tests cover
empty, malformed, single, multiple, duplicate, pre-recorded, bracketed, fenced
JSON, plan, command, file-action, skip, idempotence, immutable-input, and
owner-poison cases. The `unexecuted-action-recovery` record is `partial`, its
historical part shrinks from 564 to 521 lines, and direct consumers now use the
independent request classifiers.

WS5-6 completed focused acceptance on 2026-07-31. The independent 136-line
`FinalAnswerClaimNoticeApplicator` freezes exact-owner tool and command
evidence, applies unwritten-file, narrated-transcript, and verification notices
in the established order, and returns immutable transform IDs without state
mutation. Finalization supplies the owning snapshot's workspace mode, project
root, allowed-tool capability, ledger results, and commands, then records the
returned transforms against that same owner. Twelve direct tests cover each
notice, combined ordering, idempotence, successful evidence, explicit roots,
unavailable command execution, immutable inputs, invalid JSON, and
owner/visible-turn poisoning. Direct detector consumers and regression tests
no longer depend on notifier delegates. The `unexecuted-action-recovery`
record remains `partial`, and its historical part shrinks from 521 to 240
lines.

WS5-7 completed focused acceptance on 2026-07-31. The independent 179-line
`NarratedTranscriptRepairPlanner` freezes owner evidence and attempted
signatures, classifies every no-plan reason, and returns an immutable
owner-bound signature, assessment, and feedback result. The Notifier resolves
workspace and planning facts from the exact owner snapshot, passes that
owner's command ledger explicitly, confirms exact ownership before mutating
the attempt set, and rechecks it after artifact persistence and before
removing the streaming think marker. Ten direct tests cover immutable inputs,
invalid JSON, all eligibility gates, successful command evidence, repeat and
attempt limits, exact payload and ID behavior, equal-generation owner
poisoning, and peer-evidence isolation. The three existing narrated-transcript
integration scenarios remain green.

The focused tree measures an 8,935-line primary file, 37 declared parts
containing 12,105 lines, and a 21,040-line same-library aggregate, all at
exact shrink-only ceilings. The manifest intentionally retains 43 historical
part records. The regenerated canonical baseline records 71 ambient and 62
turn-reachable reads.
Workstreams 4-6 are in progress; this does not claim the remaining slices.
P11 has implemented the final WS6-1 prerequisite, while
P10b, P11, and P13 have implemented the prerequisites for WS8-8 through
WS8-10. Those unblocks become complete only after integrated full verification
and the exact-model live canary, which remain pending and are not claimed here.
The authoritative execution inventory is
`docs/chat_notifier_decomposition_task_index.md`.

This is an umbrella plan, not one implementation task. It continues
`docs/large_file_refactor_plan.md` Phase 1 after Tranche 1
(`PlanningResearchCollector`, `WorkflowProposalParser`,
`ActiveResponseRegistry`, `ProjectScopedToolArgumentResolver`, and related
extractions).

## Execution Rule

- If a request says only "implement this document", execute **Slice 1 only**.
- Every later slice requires its own task specification based on
  `docs/codex_task_template.md`.
- Keep each slice within one focused review pass. The workstreams below are
  ordering constraints and risk groupings, not permission to combine them into
  one PR.
- Target at most roughly 500 changed production lines per slice. Split sooner
  when one file contains more than one risk domain.
- A slice is complete when its own acceptance criteria pass **and the existing
  repository suite is still green**: `fvm flutter analyze lib packages test
  tool` clean, and `fvm flutter test test/features/chat test/quality test/core`
  with no failures. A slice's own tests cannot establish that it preserved
  behavior — see "Regression gate" below. The remaining program-wide criteria
  apply only after every approved slice is complete.
- Never leave the branch uncompilable or uncommitted between slices. Tranche 2
  accumulated 309 uncommitted files with no rollback point, and the SSH slice
  left the library referencing a production transport that was never written.
- Before starting a slice, remeasure its named files and compare the current
  call sites with this plan. If the baseline has drifted, update that slice's
  task and acceptance arithmetic before editing production code.
- Implement stop-condition corrections only through
  `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md`. Never hide a
  behavior fix inside a behavior-preserving extraction.

## Motivating Evidence

On 2026-07-25/27, roughly twenty defects were fixed on
`fix/cross-thread-tool-result-contamination`, squashed as `b0c19fdb`. They
shared one cause:

> `ChatNotifier` serves every thread from one object, while `ChatState` belongs
> to the thread on screen. Turn-scoped code that reads visible-thread state can
> therefore receive another turn's value without any type error.

A background turn quoted another thread's history, resolved relative tool paths
against the visible project, leased the wrong workspace, persisted its
transcript onto the visible conversation, lost queued work and plan state on a
switch, and stranded lifecycle resources after a plan question crossed threads.

The durable boundary is a library boundary:

> A file that is `part of 'chat_notifier.dart'` can reach `state`, `ref`, and
> every private field. An independently importable collaborator cannot.

The objective is to remove ambient capability, not merely move lines. Line
counts measure progress but do not prove the architecture.

A one-off call-graph review reported 45 turn-reachable methods that read visible
state without accepting turn identity. That number is historical evidence, not
an acceptance baseline: no checked-in tool currently reproduces it. Slices
2a1-2a3 must establish the canonical measurement and enforcement before later
extractions use it.

## Program Scope

- Goal: replace same-library helper and handler code with independently
  importable collaborators that receive explicit, immutable turn inputs.
- User-visible behavior: none. Every extraction is behavior-preserving.
- Expected architectural result:
  - the notifier remains the orchestration and lifecycle shell;
  - extracted code cannot import or receive the notifier or ambient UI state;
  - turn identity, project, messages, settings, and approval capabilities are
    explicit at each boundary;
  - each independently moved concern has direct tests and a shrink-only size
    budget.
- Non-goals:
  - opportunistic behavior fixes found during an extraction;
  - the per-thread notifier split described as stage 3 in
    `docs/multi_thread_architecture_study.md`;
  - provider renames, `ChatState` schema changes, or persistence migrations;
  - raising a ratchet budget;
  - forcing a whole current `part` file to become one collaborator.

## Measured Baseline

Measured on 2026-07-27 at `b0c19fdb`, using the same physical-line semantics as
`File.readAsLinesSync()` in `test/quality/file_size_ratchet_test.dart`:

| Boundary | Physical lines |
|---|---:|
| `chat_notifier.dart` orchestrator | 9,375 |
| 43 declared part files | 13,674 |
| **Same-library aggregate** | **23,049** |
| Aggregate ratchet budget | 23,030 |
| **Current ratchet debt** | **19** |
| Five lifecycle `keep` parts | 644 |
| Candidate part lines outside the `keep` set | 13,030 |
| Exact half-of-baseline reference point | 11,524.5 |

The aggregate ratchet is intentionally red at the start of Slice 1:
`23,049 > 23,030`. Do not change the budget to make the baseline green.

The previous inventory counted the trailing empty split result once per file,
inflating the aggregate by 44 lines. All program measurements must use the
ratchet's physical-line method.

### Planning Inventory

This table is an exposure and sequencing inventory. It is not an instruction to
move each listed file wholesale.

| Group | Part lines | Current files | Required treatment |
|---|---:|---|---|
| Lifecycle `keep` set | 644 | `execution_runtime`, `response_finalization`, `error_handling`, `turn_exit`, `cancellation` | Keep with the orchestrator |
| Slice 1 formatter | 149 | `content_tool_result_format` | Move to an independent chat-domain service |
| DTO- or callback-blocked proposal facades | 699 | `proposal_parsing`, `proposal_option_extraction`, `workflow_proposal_parser`, `task_proposal_quality`, `terminal_tool_response_policy`, `task_proposal_parser` | Defer until draft DTOs leave `ChatState` and JSON-repair or terminal-policy callbacks become explicit result values or narrow typed ports |
| Low-state but side-effecting or callback-driven | 712 | `prompt_context`, `python_attachment_repair`, `duplicate_recovery`, `mesh_routing`, `planning_research`, `turn_rollback_handlers` | Split by responsibility; require explicit turn inputs |
| Recovery and verification | 2,872 | `tool_loop_batch`, `unexecuted_action_recovery`, `coding_verification_feedback`, `coding_continuation_recovery`, `turn_finalization_recovery`, `final_answer_recovery` | Characterize each recovery route before extraction |
| Tool execution and approval | 4,892 | `local_file_handlers`, `computer_use_handlers`, `git_handlers`, `ssh_handlers`, `subagent_handlers`, `browser_handlers`, `routine_handlers`, `serial_handlers`, `skill_handlers`, `ble_handlers`, `python_handlers`, `approval_handlers`, `tool_handler_registry` | Separate execution from notifier-owned approval/UI ports before moving code |
| Guardrails and telemetry | 1,480 | `command_guardrails`, `context_surgery`, `tool_result_telemetry` | Add deterministic two-thread poison tests first |
| High-coupling orchestration | 2,226 | `goal_auto_continue`, `participant_turns`, `ask_user_question` | Narrow interfaces only; keep unextractable orchestration in place |
| **All declared parts** | **13,674** | **43 files** | |

Do not use raw `state`, `ref.`, or `_settings` occurrence counts as a coupling
classifier. They miss line-wrapped member access and ignore private fields,
private methods, callbacks, file I/O, persistence, and other side effects. For
example, `prompt_context` contains provider reads, persistence, file loading,
logging, project resolution, and an optional visible-conversation fallback. It
is not a pure helper.

## Safety Contract

### Collaborator boundary

Every extracted collaborator must satisfy all of these rules:

1. It is an independent library and does not use `part of`.
2. It does not import, extend, accept, store, or return `ChatNotifier`,
   `ChatState`, Riverpod `Ref`/`WidgetRef`, or `ProviderContainer`.
3. It does not read `TurnThread`, `TurnProjectRoot`, or another Zone-scoped
   value internally. The notifier resolves those values at the call site and
   passes plain immutable inputs.
4. It does not receive a broad closure that merely captures the notifier or
   visible-thread state. Side effects cross narrow typed ports whose methods
   include the owning turn identity.
5. It receives the smallest settings snapshot it needs. Passing all
   `AppSettings` requires an explicit justification in that slice's task.
6. Public notifier APIs may remain as thin delegates when external callers need
   them. A delegate must not reintroduce an ambient lookup.
7. Every program collaborator carries an exact discovery marker:
   `// ChatNotifier decomposition collaborator: <collaborator-id>`.
8. Every new production file is added to
   `test/quality/file_size_ratchet_test.dart`, or to an equivalent
   shrink-only package budget, at its achieved size.
9. Every collaborator with executable logic has a direct test. Overall
   repository coverage alone is not sufficient.

### Lifecycle `keep` set

Keep `_startRuntimeTurn`, `_completeRuntimeTurn`, `_failRuntimeTurn`,
`_finishStreaming` finalization, cancellation, error handling, and turn-exit
recording with the orchestrator. They release the active-response registration,
runtime handle, and workspace lease together. Splitting that ownership can
reopen the lifecycle leak this program is intended to prevent.

### Stop conditions

Stop the current slice and record a follow-up when any of these is true:

- extraction requires passing the notifier, `ChatState`, `Ref`, or a broad
  notifier-capturing callback;
- preserving behavior requires an ambient visible-conversation fallback on a
  turn-reachable path;
- the current file mixes execution with approval or UI state and no narrow port
  exists yet;
- an extraction needs a behavior fix, schema change, or provider rename;
- the destination would exceed an existing budget;
- the slice cannot remain one focused review pass or would move roughly 500
  production lines without a smaller cohesive boundary.

Do not hide a stop condition by widening the context object.

## Measurement and Regression Gates

Slices 2a1-2a3 must make the central safety claim reproducible before any
post-Slice-1 production extraction starts.

### Regression gate

Run the existing repository suite before calling a slice complete. This is the
only gate that has ever caught the failure mode this program actually produces.

Tranche 2 introduced eight production regressions. Every one passed its own
slice's focused acceptance, and most passed an exact-model live canary; the
integrated tree meanwhile did not compile and failed 101 chat tests. That is
not bad luck, it is structural: a new collaborator's tests are written against
the preconditions the extraction introduced — a coding project root, a
registered owner snapshot, telemetry wiring, settlement evidence, a synchronous
approval path — so they can confirm the new contract and never notice that the
paths without those preconditions stopped working. Local commands and file
mutations outside a coding project, plan drafting, proposal parsing, and
content tools requiring approval all broke this way.

Two corollaries worth stating, because both cost real time:

- A test double that models something the real system cannot produce is the
  test's defect, not the code's. Four failures were doubles reporting a
  mutation without performing it, a completion without settlement evidence, or
  a hand-built snapshot missing the resolved path key production always sets.
- A symptom that looks exactly like a production bug still needs its inputs
  checked. A discarded best-of-N candidate left on disk looked like a rollback
  defect, and the resolved-versus-lexical path key mismatch behind it was real;
  the fault was one step further back, in the test's snapshot.

### Static audit

Add a checked-in audit, tentatively
`tool/audit_chat_notifier_turn_scope.dart`, that:

- reads a checked-in `tool/chat_notifier_decomposition_manifest.json` shared by
  the audit and structural tests;
- preserves one entry per original part with stable `id`, `partPath`,
  `entrypoints`, `status`, and `collaborators` fields; every collaborator record
  has its own stable `id`, `path`, and `sizeBudgetKey`;
- reconstructs the original 43-part inventory and entrypoints from `b0c19fdb`;
  because Slice 1 runs first, its formatter entry starts as `extracted` with the
  Slice 1 collaborator record, while the other current parts start as
  `remaining`, `keep`, or a justified `deferred`;
- uses only `remaining`, `partial`, `extracted`, `keep`, or `deferred` as status
  values; extraction transitions the status and appends collaborator records
  but never deletes the historical part entry;
- records the exact files, entrypoints, and call-graph assumptions it scans;
- parses complete method signatures rather than a fixed number of lines;
- reports each ambient read independently instead of skipping a whole method
  after finding one turn-scoped accessor;
- scans every currently declared `partPath` whose status is `remaining`,
  `partial`, `keep`, or `deferred`, plus every collaborator record attached to
  a `partial` or `extracted` entry;
- emits a deterministic method/read inventory suitable for review;
- establishes a canonical baseline committed with the tool.

The historical count of 45 must not be copied into a ratchet until this audit
reproduces and explains it.

### Structural test

Add `test/quality/chat_notifier_collaborator_boundary_test.dart` to:

- freeze all original `partPath` values, reject any new notifier part, and
  require the currently declared parts to equal the entries whose status is
  `remaining`, `partial`, `keep`, or `deferred`;
- require an `extracted` entry's old part to be absent, a `partial` entry's old
  part to remain, and every declared collaborator path and size-budget key to
  exist;
- scan Dart files under `lib/features/chat` for the discovery marker
  independently of the manifest and require a one-to-one marker ID/path match;
- use syntax-aware whole-file checks on every collaborator record attached to
  a `partial` or `extracted` entry to reject `part of`, forbidden imports or
  references to `ChatNotifier`, `ChatState`, Riverpod reference types, and
  direct turn Zone reads;
- separately reject forbidden types in public collaborator signatures;
- ensure every new collaborator is size-budgeted;
- fail when a completed slice silently adds another notifier part.

### Existing thread-scope ratchet

Strengthen `test/quality/thread_scoped_state_ratchet_test.dart`. Its current
implementation inspects only the first six signature lines and skips the entire
method when any turn-scoped accessor appears. Both behaviors can hide another
ambient read in the same method.

When the stronger implementation surfaces a pre-existing read, reconcile it
exactly with the reviewed Slice 2a1 audit and label the ratchet change as a
baseline migration. After Slice 2a3 establishes that migrated baseline, forbid
new production reads; do not require an out-of-scope behavior fix merely to keep
the old blind baseline numerically unchanged.

### Deterministic two-thread coverage

Slices 2b2-2b7 must add or extend tests that poison the visible thread with
different project, task, approval, queue, question, and protected-path values.
The owning turn must continue to use only its own values.

At minimum, cover:

- production-release approval cannot cross threads;
- approval from an earlier interaction generation cannot authorize a later
  generation;
- saved validation and target scope come from the owning turn;
- pending approvals, questions, and queued work block only their owning turn;
- compact-result protected paths come from the owning turn;
- participant turns retain their messages, approval, handoff, and lifecycle
  while another thread is visible.

### Live canary

Before using the live canary as a program gate, Slice 2b1 must make all four
scenarios assert both:

- no thread remains in `busyConversationIds`;
- every completed turn records a `turn_exit` entry.

The current shared lifecycle helper checks only busy registrations, and the
queued-turn and handback scenarios do not independently assert an exit entry.
Each scenario must define its expected completed turns and assert exactly one
exit per conversation and interaction generation; a non-empty exit list is not
sufficient.

Run the corrected live canary after any slice that touches prompt context,
recovery, tool execution, approval, guardrails, telemetry, participant turns,
questions, or goal continuation.

Record the exact model and reachable base URL used for each run. Verify the
model endpoint before starting; on macOS, use a loopback relay when the Flutter
test process cannot reach the LAN endpoint.

Example command shape (replace the endpoint and model with the warmed target):

```bash
curl -fsS http://127.0.0.1:11434/v1/models
CAVERNO_MULTI_THREAD_LIVE_CANARY=1 \
CAVERNO_LLM_BASE_URL=http://127.0.0.1:11434/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart -d flutter-tester
```

## Ordered Work Plan

Slices 1, 2a1-2a3, and 2b1-2b7 each require one task specification and PR.
Workstreams 4-8 require further sub-slice task documents; a workstream row is
never one PR. Deferred-boundary rows are not approved implementation slices.

| Slice or workstream | Scope | Review boundary | Live canary |
|---|---|---|---|
| **1** | Extract `content_tool_result_format` | One pure formatter and direct domain-service tests | Not required |
| **2a1** | Reproducible turn-scope audit and shared decomposition manifest | One audit tool and named baseline | Not required |
| **2a2** | Collaborator structural boundary test | One manifest-backed architecture gate | Not required |
| **2a3** | Repair the existing thread-scope ratchet | Complete-signature and per-read detection only | Not required |
| **2b1** | Complete live-canary exit accounting | Exact expected exits per conversation/generation | Passed on exact model |
| **2b2** | Approval isolation tests | Cross-thread and cross-generation approval only | Passed after production guardrail change |
| **2b3** | Pending-question isolation tests | Question ownership and clearing only | Passed after production question-lifecycle change |
| **2b4** | Queued-work isolation tests | Queue blocking and resumption only | Passed on exact model |
| **2b5** | Saved-validation and target-scope isolation tests | Validation and target ownership only | Passed on exact model |
| **2b6** | Compact-result protected-path isolation tests | Protected-path ownership only | Passed on exact model |
| **2b7** | Participant-turn isolation tests | Participant messages, approval, handoff, and lifecycle only | Passed on exact model |
| **P1a-P14** | 18 corrective ownership, completion, policy, and size areas split into 19 review slices | One stop-condition correction per task in the prerequisite catalog | Required after every production prerequisite |
| **Deferred boundary** | Proposal parsing, option, workflow, task-parser, and quality facades | Blocked because draft DTOs are declared in `ChatState` and JSON-repair uses notifier-bound callbacks; both prerequisites are outside this tranche | Not applicable |
| **Deferred boundary** | Terminal tool-response facade | Blocked until its notifier-capturing callback bag becomes a narrow explicit-input API | Not applicable |
| **Workstream 4** | Low-state and prompt-context concerns; WS4-1 and WS4-2 focused acceptance complete | Extract one independent concern per sub-slice; leave unrelated code in its existing part | Required for prompt, planning, mesh, Python repair, or rollback paths |
| **Workstream 5** | Recovery and verification services | One recovery route or tightly coupled pair per sub-slice | Required |
| **Workstream 6** | Tool handlers; WS6-1, WS6-2, WS6-5, WS6-12, and WS6-13 focused acceptance complete | Separate execution from approval/UI; split local-file and Computer Use into sub-500-line concern tasks; registry moves last | Required |
| **Workstream 7** | Guardrails, context surgery, and telemetry | One concern per sub-slice after poison tests exist | Required |
| **Workstream 8** | Goal continuation, participant turns, and user questions | Narrow interface extraction only; leave justified orchestration in place | Required |

Do not begin any Workstream 4-8 sub-slice until Slices 2a1-2a3 and 2b1-2b7 are
green. After that gate, satisfy every prerequisite named by an extraction
before editing the extraction itself.

## Slice 1 Codex Task: Extract ContentToolResultFormatter

### Task

- Goal: move the compact `<tool_result>` payload and tag formatting logic out of
  the `ChatNotifier` library into an independent chat-domain service.
- User-visible behavior: none. Output strings and JSON payloads remain exactly
  compatible for the same inputs.
- Non-goals:
  - changing summary wording, truncation limits, JSON keys, or tag syntax;
  - refactoring other proposal, prompt, recovery, or tool-loop code;
  - adding the Slice 2 audit and structural gates;
  - changing the content parser.

### Context

- Source:
  `lib/features/chat/presentation/providers/chat_notifier_content_tool_result_format.dart`
  (149 physical lines).
- Current callers: three `_buildContentToolResultTag` calls in
  `lib/features/chat/presentation/providers/chat_notifier.dart`.
- Destination:
  `lib/features/chat/domain/services/content_tool_result_formatter.dart`.
- Direct tests:
  `test/features/chat/domain/services/content_tool_result_formatter_test.dart`.
- Quality budget:
  `test/quality/file_size_ratchet_test.dart`.
- Related plan:
  `docs/large_file_refactor_plan.md`.
- Reference boundary:
  `lib/features/chat/domain/services/goal_completion_elicitation_prompt.dart`
  and
  `test/features/chat/domain/services/goal_completion_elicitation_prompt_test.dart`.

### Implementation Notes

- Add an `abstract final class ContentToolResultFormatter` with exactly one
  public member:
  `static String format(String toolName, String result)`.
  Keep payload construction, map summarization, value compaction, and
  truncation private to that service.
- Add
  `// ChatNotifier decomposition collaborator: content-tool-result-formatter`
  as the exact discovery marker for the later structural gate.
- Import the service directly from `chat_notifier.dart`; do not add a package,
  barrel export, provider, notifier field, or dependency-injection binding.
- Preserve the existing behavior for:
  - entry maps with implicit or explicit counts;
  - match maps with query, pattern, or neither and implicit or explicit counts;
  - content maps, byte-write maps including `created`, and replacement maps
    including `replace_all`;
  - generic JSON maps;
  - JSON lists;
  - valid JSON scalar values;
  - plain-text and malformed JSON results;
  - empty results;
  - whitespace normalization and truncation;
  - final `<tool_result>{json}</tool_result>` construction.
- Replace the three notifier call sites with the public formatter API.
- Remove the old part directive and part file after all callers move.
- Add the new domain-service source file to a shrink-only size budget at its
  physical line count.
- Never increase either ChatNotifier size budget. Lower the aggregate budget to
  its achieved count. Lower the primary-file budget only if the primary file's
  measured physical count decreases.
- Keep each direct replacement call on one physical line. The intended edit
  swaps one part directive for one import and preserves the three call-site line
  counts, producing a zero notifier line delta and an expected aggregate of
  22,900 before measurement.
- Calculate the expected aggregate as
  `23,049 - 149 + notifier physical-line delta`, where the notifier delta is
  its achieved count minus 9,375 and includes the removed part directive, new
  import, and call-site rewrites. Record the achieved count rather than
  assuming the delta.
- Refresh the ChatNotifier counts and Slice 1 status in
  `docs/large_file_refactor_plan.md`.
- No generated files or data migrations are required.

### Similar-Pattern Search

Before finishing, search for:

```text
_buildContentToolResultTag
_buildContentToolResultPayload
<tool_result>
```

Inspect all matches, but do not widen the slice. Record non-equivalent formatters
or protocol follow-ups in the handoff.

### Acceptance Criteria

1. The old formatter part is no longer declared or present, and the declared
   part count falls from 43 to 42.
2. The three notifier callers use
   `ContentToolResultFormatter.format(toolName, result)` directly.
3. Direct tests cover every existing formatter branch and exact tag output.
4. The new collaborator has no dependency on `ChatNotifier`, `ChatState`,
   Riverpod, providers, turn Zones, settings, persistence, or file I/O.
5. The ChatNotifier primary and aggregate size tests pass; neither budget
   increases, the aggregate budget is lowered to its achieved count, and the
   primary budget is lowered only when its measured count decreases.
6. The new domain-service source file has a shrink-only size budget.
7. The new source file has the exact decomposition discovery marker.
8. The thread-scope ratchet still passes with no allowlist growth.
9. `docs/large_file_refactor_plan.md` records the achieved physical counts.
10. No unrelated production behavior or files enter the change.

### Verification

Run focused checks:

```bash
fvm dart format \
  lib/features/chat/domain/services/content_tool_result_formatter.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/content_tool_result_formatter_test.dart \
  test/quality/file_size_ratchet_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test \
  test/features/chat/domain/services/content_tool_result_formatter_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart test/quality/thread_scoped_state_ratchet_test.dart
```

Run the repository gate:

```bash
tool/codex_verify.sh --coverage
git diff --check
```

The live multi-thread canary is not required for this pure formatter move.

### Handoff Notes

Record:

- old and new primary, part, and aggregate physical line counts;
- old and new ratchet budgets;
- direct formatter branch cases and the target file's hit/line counts from
  `coverage/lcov.info`;
- the final declared-part count;
- searches performed and any deferred follow-up.

Use one focused Conventional Commit, for example:

```text
refactor: Extract content tool result formatter
```

## Requirements for Later Slice Specifications

Every later concrete slice or workstream sub-slice task document must state:

- one concrete concern and destination API;
- exact source methods and call sites, not only a current part filename;
- explicit immutable inputs and typed side-effect ports;
- expected part-count and aggregate-line deltas;
- manifest status, collaborator records, and discovery markers;
- direct test file and a target-file coverage expectation with a checked
  verification command;
- deterministic two-thread cases when turn ownership is relevant;
- whether the corrected live canary is required;
- stop conditions and deferred adjacent findings;
- focused verification plus `tool/codex_verify.sh --coverage`.

`tool/codex_verify.sh --coverage` generates a report and lists files below the
display threshold; it does not fail on that threshold. Do not describe it as a
numerical coverage gate. If a slice requires a minimum percentage, its task
must provide and check an explicit target-file command.

Within a slice, use one commit per independently reviewable concern. Never mix
an extraction with a behavior fix.

## Program Completion Criteria

The program is complete only when:

1. Every remaining part belongs to the five-file lifecycle set or is an
   explicitly justified high-coupling deferral covered by the structural
   boundary test. Report the final count. The currently scoped floor is 11
   parts: five lifecycle parts plus six proposal/callback deferrals. Lowering
   that floor requires separately approved prerequisite work.
2. No completed slice leaves an undocumented notifier part or collaborator
   boundary exception.
3. The canonical turn-scope audit reports no unreviewed ambient reads in
   extracted collaborators and no increase in remaining notifier exposure.
4. The repaired thread-scope ratchet exactly reconciles any newly detected
   pre-existing reads with the Slice 2a1 audit, then has no production-read
   baseline growth after Slice 2a3.
5. Every extracted production file has a shrink-only size budget and direct
   tests.
6. The ChatNotifier primary and aggregate budgets never increase. After each
   production extraction, every measured boundary that actually shrinks has
   its budget lowered to the achieved count; test-only gate slices do not
   invent a reduction.
7. The final aggregate is reported against the exact 11,524.5 half-baseline
   reference. Halving is directional, not permission to force unsafe
   extraction.
8. The corrected four-scenario live canary passes after every applicable slice,
   with no busy thread and exactly one `turn_exit` entry for each expected
   completed conversation and interaction generation.
9. `tool/codex_verify.sh --coverage` completes for every slice, and the handoff
   records target-file coverage for each new collaborator. Any numerical
   threshold is enforced by an explicit checked command in that slice.
10. `docs/large_file_refactor_plan.md` records the final counts, exceptions, and
    Tranche 2 status, and agrees with the task index and manifest.
11. Every corrective prerequisite in
    `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` is complete,
    or the dependent extraction is explicitly deferred rather than bypassing
    its stop condition.

## Reference and Warning Notes

- Read `docs/multi_thread_architecture_study.md` before any turn-context or
  high-coupling slice.
- For the pure Slice 1 API shape, use the directly tested
  `GoalCompletionElicitationPrompt` or `WorkflowTaskTurnRoutePolicy` as a
  reference: both are stateless `abstract final` classes with static methods.
- Other directly tested boundaries demonstrate only individual techniques.
  `ProjectScopedToolArgumentResolver` shows a narrow lazy input and
  `PlanningResearchCollector` shows a typed side-effect callback, but their
  callers still require ownership review.
- `ActiveResponseRegistry`, `WorkflowProposalParser`, and
  `PlanningDecisionPromotion` import `chat_state.dart`; they do not satisfy this
  program's strict collaborator contract as written.
- `TurnToolResultLedger` is keyed by `ChatTurnOwner`; use its explicit owner
  read/write/publish/take/dispose lifecycle for consumable tool evidence, but
  do not reuse it for finalization, approval, or mutable orchestration state.
- P3a also keys turn-exit, transform, goal-claim, and shadow state by exact
  owner. `TurnGoalCompletionEvidenceRegistry` now supplies exact-owner
  completion snapshots, and `initialGoalCompletionEvidence` is the only
  supported successor handoff. Do not reintroduce a conversation-global latest
  fallback.
- Do not call `TurnCodingProjectResolver.effective` from turn-scoped code; it
  intentionally retains a visible-conversation fallback for UI-scoped callers.
- Do not preserve `prompt_context`'s optional visible-conversation fallback on a
  turn-reachable path merely to keep an extraction mechanical. Characterize the
  callers and stop for a separate behavior fix if explicit ownership would
  change behavior.
- Do not fix adjacent findings inside an extraction. Record them and create a
  follow-up task.
- Never use whole-file checkout or another destructive rollback to undo a
  partial edit in a dirty file.
- All code, comments, docs, commit messages, and PR text must be English.
  Commits and PR titles use Conventional Commits, imperative subjects no longer
  than 72 characters, no trailing period, and no AI attribution.
