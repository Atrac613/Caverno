# Plan Mode Scenario Coverage

This document records the Plan Mode scenario classes used after MVP handoff.
It keeps smoke coverage small, gives canaries clear promotion rules, and
separates long-run confidence work from the release gate.

For cross-surface Live LLM coverage across chat, coding, and routines, see
[`live_llm_canary_coverage.md`](live_llm_canary_coverage.md). This document
only classifies Plan Mode and coding scenarios.

## Coverage Classes

| Class | Purpose | Default gate |
|-------|---------|--------------|
| Smoke | Fast live confidence for release readiness. These scenarios should cover core approval, decision, and recovery flows with no unexpected warnings. | PM5 live smoke phase |
| Canary | Targeted live probes for MVP-adjacent behavior. A canary can fail without redefining the smoke gate, but every failure must produce actionable artifacts. | Explicit scenario or PM5 canary phase |
| Long-run | Repeated or matrix-style validation for model variability, endpoint compatibility, and release candidate confidence. | PM12 release candidate gate |

## Current Live Scenario Classification

| Scenario | Class | Gate | Promotion status |
|----------|-------|------|------------------|
| `live_host_health_scaffold` | Smoke | `CAVERNO_PLAN_MODE_TAGS=smoke` | Keep in smoke |
| `live_cli_entrypoint_decision` | Smoke | `CAVERNO_PLAN_MODE_TAGS=smoke` | Keep in smoke |
| `live_clarify_recovery` | Smoke | `CAVERNO_PLAN_MODE_TAGS=smoke` | Keep in smoke |
| `live_ping_cli_completion` | Canary | PM5 ping CLI canary phase | Keep separate from smoke because it is longer and artifact-sensitive |
| `live_readme_first_canary` | Canary | Explicit scenario run | Not ready for smoke promotion |

`live_readme_first_canary` stays outside `smoke` because it intentionally
tracks artifact convergence and guarded tool-loop behavior. It is useful, but
still has allowed recovery warnings and a guarded convergence expectation that
should remain visible before it becomes release smoke.
It also asserts the `CANARY_CONTENT_FIT: README_ONLY` marker so README content
fit is checked automatically instead of relying only on path-based task drift.

## First MVP-Adjacent Candidate

The first MVP-adjacent candidate remains `live_readme_first_canary`.

Promotion target:
- Move from explicit canary to smoke only after repeated clean evidence.

Required canary evidence:
- `README.md` artifact expectation passes.
- Saved workflow expectation includes at least one task.
- First task targets `README.md`.
- Task drift is not detected.
- `warningSummary.unexpectedWarnings` is `0`.
- Report quality blockers are `0`.
- Allowed warnings are either removed or still have a documented recovery
  marker.
- The convergence path is one of:
  - guarded convergence with `planModeSavedValidationConvergenceGuardPattern`
  - natural stop after saved validation success

Do not promote it while the canary needs recurring fallback proposals,
duplicate write recovery, or unexplained content drift to pass.

## Promotion Rules

A canary can be proposed for smoke promotion only when all of these are true:

- The PM5 live gate has a recent clean pass.
- The canary has at least three consecutive clean live runs against the target
  release endpoint and model.
- The canary has explicit artifact expectations.
- The canary has saved workflow expectations for task count or target files.
- The canary has warning policy expectations and no recurring unexpected
  warnings.
- The canary has task drift checks through scenario reporting.
- The canary has a focused test that protects its classification and key
  expectations.
- The release checklist can explain why the scenario belongs in smoke rather
  than canary or long-run coverage.

## New Canary Requirements

Every new Plan Mode live canary must define:

- scenario name and coverage class
- target user workflow
- artifact expectations, including negative expectations when scope matters
- saved workflow expectations
- warning policy expectations
- task drift expectations through scenario reporting
- expected approval path behavior
- promotion criteria and rollback criteria

Start new coverage as `canary`. Promote only after the promotion rules above
are satisfied.

## Long-Run Candidates

Long-run coverage is reserved for PM12 and later release candidate validation.
Candidates include:

- repeated PM5 live gate pass-rate checks
- repeated `live_readme_first_canary` convergence checks
- selected canaries across more than one OpenAI-compatible endpoint
- selected canaries across more than one supported model

Long-run results should influence release confidence, but they should not
silently expand the default smoke surface.
