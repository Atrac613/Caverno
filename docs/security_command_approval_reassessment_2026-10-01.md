# Command Approval Security Reassessment

Date: 2026-10-01

Reviewed baseline source: `893e94560`. The observations below describe that
baseline and do not invalidate unrelated SEC findings. The subsequent local
implementation is documented in [Project Execution Boundaries](project_execution_boundary_design.md).

## Assessment

SA-01 and SA-19 describe real execution and filesystem-boundary defects.
They do not establish that every native-shell command must always require a
fresh human decision. SEC4.4g selected that restriction as a conservative
authorization control while host execution remained uncontained. It is not a
filesystem containment mechanism, and its implementation tests do not measure
whether repeated human review is necessary or effective for ordinary coding.

The earlier explanation that the audit reasons had a sound basis needs this
qualification: the demonstrated hazards and the chosen approval frequency are
separate conclusions.

## Evidence And Method

- Inspected the original audited source at
  `50c3fdd330cb3b0609fcbfe0d635e9a5d01aba96` and the SA-19 source at
  `a3d35fc9e592`, together with current launch and approval code.
- Reconstructed narrow probes from historical classifier methods and historical
  command guard/path-scanner source. Unused Git classification was excluded;
  current canonical-path utilities and package dependencies were reused.
  These are component probes, not a replay of the historical application.
- Created disposable project and sibling directories containing only dummy
  files. Executed harmless commands against those fixtures and removed them.
- Tested the current macOS sandbox profile with a real `sandbox-exec` launcher.
  The initial run inside the agent's own sandbox could not apply a nested
  sandbox. A permitted run outside that outer sandbox exercised the actual
  filesystem denial instead of treating launcher failure as protection.
- Did not read real credentials, run the Watcher test suite, or exercise the
  running Caverno application or a live LLM reviewer.

| Probe | Result | Supported conclusion |
| --- | --- | --- |
| `awk 'BEGIN { system("touch awk-marker") }'` | Historical classifier returned read-only; the command created the marker | SA-01's semantic execution bypass is real |
| `sed -n 'w sed-marker' input.txt` | Historical classifier returned read-only; the command created the marker | SA-01's write classification defect is real |
| `python3 probe.py`, with the target constructed inside the script | Historical cwd authorization allowed execution; write candidates and outside-path scan were empty; a sibling dummy file was written | SA-19's lexical fence does not enforce project containment |
| The same Python script launched directly with argv, without a shell | The sibling dummy file was written | Eliminating `sh -c` alone does not contain arbitrary code |
| The same write under the current OS sandbox profile | Exit 1 with an operation-not-permitted error; no sibling file was created | OS enforcement addresses this demonstrated write escape |
| A script reading a sibling dummy file under the current profile | Exit 0; dummy contents appeared on stdout | Current write containment is not read containment |
| `printf dummy 2>&1 \| tail -5` under the current profile | Exit 0 with the expected output, while eligibility returned false | This routing exclusion is broader than the demonstrated hazard |

## Findings Reassessed

### SA-01: Valid Defect, Narrower Implication

The original classifier admitted `awk` and `sed -n` while the executor lacked
internal implementations and sent them to a native shell. The two fixture
probes reproduce side effects under a read-only label. The intended approval
boundary was bypassed; fixing that boundary was justified.

This does not imply that arbitrary code can never run automatically. Code
execution authorized within an enforced environment is a different capability
from read-only inspection. Preserving the bounded inspection shortcut and
adding an explicitly authorized contained execution route are compatible.

Source: [SA-01](security_audit_2026-08-14.md#sa-01-approval-free-semantic-shell-execution).

### SA-19: Valid Containment Gap, Conditional Authorization Interpretation

The audited guard recognized only path candidates visible in command text.
The script probe passed those checks and wrote outside its project. The same
failure occurred with plain argv, so the important boundary is the authority
of the executed program and its children, not shell syntax itself.

Calling this an unauthorized action also requires a defined user grant. If
the user was promised project-only execution, the gap violates that promise.
If a distinct mode intentionally grants host execution, the possible host
write is an accepted capability rather than an approval bypass. Current
settings do not explain that distinction consistently: Full Access promises
execution without prompts, while SEC4.4g forces fresh prompts for uncontained
project commands.

Source: [SA-19](security_followup_review_2026-08-24.md#sa-19-opaque-shell-project-containment-bypass),
[mode contract](../packages/caverno_tool_contracts/lib/src/tool_approval_mode.dart),
and [settings description](../assets/translations/en.json).

### Fresh Approval: Authorization Control, Not Containment

A denial prevents process startup. That is a real benefit. Approval, however,
still launches with host authority and does not prevent the demonstrated
outside write. Looking at `python3 probe.py` also does not reveal the script's
computed effects, and stable command text does not mean stable project code.

The SEC4.4g closure tests establish that mandatory approval outranks saved
permissions, cache, Full Access, and auto-review. They establish the chosen
policy's enforcement, not the necessity of that policy or the effectiveness
of repeated human review. The handoff itself explicitly says native-shell
approval is not an OS containment guarantee. The audit's release criterion
also explicitly accepts an enforced project sandbox as an alternative.

Sources: [SEC4.4g handoff](sec4_4g_opaque_local_command_authority_task.md#handoff-notes),
[release criterion](security_audit_2026-08-14.md#remediation-map),
and [approval regression](../test/features/chat/domain/services/tool_approval_auto_review_service_test.dart).

### SA-07 And LLM Review: Valid Ordering Concern, Limited Generalization

The original gate returned cached or Full Access permission without enforcing
the untrusted-influence policy. Its ordering supported the audit finding.
Enforcing a defined authority boundary before shortcuts is justified.

Current taint tracking conservatively treats any untrusted evidence recorded
for a turn owner as possible influence; it does not prove that a particular
action was instructed by an attacker. The shell capability classifier also
does not distinguish the enforced execution profile when assessing taint.
These choices can restrict legitimate automated work and need to be assessed
against an explicit project grant.

The code documents one incident in which auto-review described a host read as
project-contained. Its original `db878d3a` session file was not found in the
current coding-log directory. This review does not independently verify that
incident or measure reviewer accuracy. It does not establish either that LLM
review alone is sufficient or that humans must review every contained action.

Sources: [SA-07](security_audit_2026-08-14.md#sa-07-advisory-taint-policy-before-trusted-execution),
[taint propagation](../lib/core/security/conversation_taint_state.dart),
and [approval gate](../lib/features/chat/domain/services/tool_approval_auto_review_service.dart).

## Current Limitations Relevant To Autonomous Coding

The current profile enforces writes, denies network access and service
channels, and protects Git metadata. Its allow-default policy does not restrict
host reads. A dynamically constructed outside read reached stdout in the
dummy probe. A network denial alone therefore does not establish a data
boundary for results returned to the parent application. Read access and
environment inheritance require their own policy before claiming full project
isolation.

The single-ampersand eligibility test also rejects `2>&1`. The sandbox probe
shows that this redirection can operate inside the existing profile. This
restriction is a conservative routing choice; the audit does not demonstrate
that redirection itself needs host authority or fresh human review.

FARM5's exclusion of tests is another policy choice: tests execute code the
agent changed. Such execution is expected in autonomous development. The
relevant question is whether the user authorized that execution and its effects
are bounded, rather than whether the code was written by a model.

Sources: [current profile](../lib/features/chat/data/datasources/local_command_workspace_containment.dart),
[environment inheritance](../lib/features/chat/data/datasources/local_shell_process_runner.dart),
and [farm policy](../lib/features/project_farm/domain/entities/project_farm_policy.dart).

## Direction For A Replacement Policy

Retain the demonstrated security requirements: no hidden read-only execution,
no undeclared authority escalation, no host side effects outside a scoped grant,
and no automatic uncontained retry after containment failure.

Replace command-by-command host approval as the default coding mechanism with
a user-declared project execution grant enforced by one common runner. The
grant should define reads, writes, network destinations, caches, environment,
process lifetime, and allowed host services. Authorized edits and test/build
execution can then proceed continuously inside that grant. Ask when additional
authority is needed or when an action falls outside the approved task.

Reassess taint handling against that actual grant and execution profile. Keep
untrusted text from granting privileges while allowing evidence needed for the
authorized task to be processed within enforced bounds. Review deployment,
publication, and host capabilities separately according to user authorization.

Validate both sides of the replacement: generated tests run without repeated
prompts inside the grant, while computed paths, symlinks, outside reads,
disallowed egress, and surviving children cannot escape it. Measure legitimate
work blocked and unnecessary prompts as well as adversarial denials.
