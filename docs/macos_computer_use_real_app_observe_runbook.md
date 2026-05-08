# macOS Computer Use Real App Observe Runbook

M12 moved from deterministic fixture evidence to real app screenshots while
remaining observe-only. M14 expands that path for Safari-style logged-in
workflows by asking the LLM to identify visible app context, candidate UI
targets, text fields, public-action boundaries, and confirmation requirements
without opening apps, clicking, typing, submitting, or posting.

## Scope

This runbook is for tasks such as:

- Inspect Safari with X visible.
- Identify address bars, compose fields, and submit or post controls.
- Classify public submit controls as `public_action`.
- Document confirmation requirements before any future text entry or public
  submit action.
- Verify that every future input or public action requires explicit user
  approval.

It is not for executing actions. TCC setup and real desktop operation remain user-operated.

## Run

First, manually prepare the screen and capture a screenshot. For example, open
Safari yourself, navigate to the target site yourself, and save a screenshot.

To generate the M14 handoff without calling the LLM or operating the desktop,
run:

```bash
bash tool/run_macos_computer_use_m14_real_app_handoff.sh \
  --screenshot <real-app-screenshot.png> \
  --target-app Safari \
  --target-intent "Observe Safari for a future X post task."
```

Then run:

```bash
bash tool/run_macos_computer_use_real_app_observe_canary.sh \
  --screenshot <real-app-screenshot.png> \
  --target-app Safari \
  --target-intent "Observe Safari for a future X post task."
```

For deterministic tests or prompt iteration, use a fixture response:

```bash
bash tool/run_macos_computer_use_real_app_observe_canary.sh \
  --fixture-response <real-app-observe-response.json> \
  --target-app Safari \
  --target-intent "Observe Safari for a future X post task."
```

The live LLM path uses the same environment contract as the coding-agent
canaries:

```bash
export CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1
export CAVERNO_LLM_API_KEY=no-key
export CAVERNO_LLM_MODEL=gemma4-26b-vision
```

The summary records the LLM mode, base URL, model, target app, target intent,
and screenshot path. It does not record the API key.

## Evidence

The canary writes:

- `canary_summary.json`
- `canary_summary.md`
- `run_01_response.txt`
- `run_01_decision.json`

The `m12EvidenceGate` remains for backward compatibility and is ready only
when:

- A real app window is visible.
- Candidate UI targets are identified.
- The plan remains observe-only.
- Future click, typing, submit, or post actions require explicit user approval.
- Posting or submit-like controls are classified as `public_action`.
- Blocked actions are documented.
- The LLM does not claim execution.

The `m14EvidenceGate` is ready only when:

- A Safari-style target context is visible.
- Text-entry targets are identified.
- Public submit or posting boundaries are classified.
- Confirmation requirements are documented.
- The canary remains observe-only with no mutation.

## M15 Action Proposal Handoff

After a ready M14 summary exists, generate the M15 handoff:

```bash
bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh \
  --m14-summary <macos_computer_use_real_app_observe_canary_summary.json> \
  --target-intent "Prepare an approval-bound plan for a future X post task."
```

The M15 handoff remains report-only. It reads M14 evidence and writes an
approval-bound checklist for observe refresh, exact text confirmation, target
confirmation, and separate public-action confirmation. It does not call the
LLM, grant TCC, open apps, operate System Settings, click, type, navigate,
submit, post, or purchase.

The handoff is ready only when `m15ActionProposalGate.status` is `ready`.
Blocked M14 evidence, missing text-entry targets, missing public-action targets,
missing confirmation requirements, or inherited mutating tools must block M15.
Review the generated `PR Review Summary` first; it separates ready review
evidence from `blockedReviewEvidence` before final MVP aggregation can continue.
Then review the generated `Review Targets` section before any future action
step: it should list exact text candidates, text-entry targets, and
public-action targets separately so the next approval can remain scoped and
explicit.

## Manual Boundary

The canary never grants TCC, opens Safari, navigates to X, moves the pointer,
clicks, types, submits, or posts. If a fresh screenshot or real app state is
needed, ask the user to prepare it manually before rerunning the canary.
