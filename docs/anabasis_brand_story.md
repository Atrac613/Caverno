# Caverno Anabasis — Brand Story

**Status: current. Concept and naming reference.** This is the *why* behind
Anabasis — the metaphor, the name, and the design principle it produces. The
architecture that implements it is
[`ANABASIS_ORCHESTRATOR_ARCHITECTURE.md`](ANABASIS_ORCHESTRATOR_ARCHITECTURE.md);
read that one for anything mechanical.

Two notes where this document's ambitions and the implementation diverge, kept
here so the gap stays visible rather than being quietly forgotten:

- The "Initial MVP" section below describes a state-summarising command. That
  framing was superseded — see
  [`anabasis_mvp_plan_superseded.md`](anabasis_mvp_plan_superseded.md) for the
  full plan it belonged to and why it did not survive contact with the
  codebase. The design principle further down ("Anabasis should not pretend
  that the shadows are the world") did survive, and became
  `MaterialContractAssumptionGuard` policy rather than a UI section.
- On the name: the Platonic reading is sound (*Republic* 517b uses ἀνάβασις
  for the ascent out of the cave), but most English readers meet the word
  through Xenophon, where it means a march inland. The connection is
  discoverable, not obvious. The UI therefore pairs the name with a plain
  subtitle — "Anabasis · Project Understanding" — so nothing depends on the
  etymology landing.

## Overview

**Caverno Anabasis** is the working name for an agent layer within Caverno.

The concept is inspired by **Plato's Allegory of the Cave**. In the allegory, people confined inside a cave mistake shadows on a wall for reality. One person eventually turns around, leaves the cave, sees the world outside, and comes to understand that the shadows were only a limited representation of reality.

Caverno Anabasis applies that metaphor to modern AI systems.

A language model normally operates inside a limited context: the current conversation, its model knowledge, available files, and whatever tools it has been given. Anabasis is intended to recognize those limits, identify what is missing, seek better evidence, coordinate tools and specialized agents, and move the user from an incomplete view toward a more grounded understanding.

## Why "Caverno"

The name **Caverno** naturally evokes a cavern or cave.

This gives the project a useful philosophical frame:

- The **cave** represents the limited context currently visible to the AI.
- The **shadows** represent incomplete information, assumptions, generated answers, search snippets, or partial project knowledge.
- The **outside world** represents broader evidence, tools, source code, external systems, local knowledge bases, and real-world state.
- The **sun** represents a clearer and more grounded understanding.

Caverno is therefore not only the place where interaction happens. It is also the starting point from which an agent can move beyond the limits of its current view.

## Why "Anabasis"

**Anabasis** comes from the Ancient Greek **ἀνάβασις**, meaning an ascent, a going upward, or an advance.

The word is especially appropriate because Plato uses *anabasis* in the context of the cave allegory to describe the upward movement out of the cave.

For Caverno, the name represents a process:

> **From shadows to understanding.**

Anabasis is not simply "the AI that knows the answer."

It is the system that helps move from an incomplete state of knowledge toward a better one.

## Core Metaphor

The brand can be expressed as a simple progression:

```text
Shadows
   ↓
Questions
   ↓
Investigation
   ↓
Evidence
   ↓
Understanding
```

Or, in Caverno terms:

```text
Limited Context
      ↓
   Anabasis
      ↓
Search / Knowledge / Tools / Agents
      ↓
Grounded Understanding
```

This makes Anabasis fundamentally different from a conventional chatbot.

A chatbot primarily responds.

**Anabasis investigates, organizes, coordinates, and advances.**

## Product Role

Anabasis should be understood as an **orchestrating agent**, not merely another model persona.

Its role is to maintain an evolving understanding of what the user is trying to accomplish.

It should track things such as:

- Goals
- Current assumptions
- Known facts
- Decisions already made
- Open questions
- Knowledge gaps
- Risks
- Dependencies
- Current phase of work
- Candidate next actions

When necessary, it can delegate work to specialized systems such as:

- Research agents
- Coding agents
- Review agents
- Local LLMs
- External models
- RAG / knowledge systems
- Web search
- Files
- Development tools
- Sandboxed or local execution environments

Anabasis remains responsible for the overall direction and context.

## From Prompt-Driven AI to Goal-Driven AI

Most coding assistants today follow a simple interaction model:

```text
User → Prompt → LLM → Result
```

The user repeatedly decides what to ask next.

Anabasis introduces another layer:

```text
              ┌─ Research
              ├─ Coding
User → Anabasis ─ Review
              ├─ Tools
              └─ Knowledge
```

The user communicates the **goal and intent**.

Anabasis maintains the project state and determines what needs to happen next.

This shifts the interaction model from:

> "Tell the LLM exactly what to do."

toward:

> "Tell Anabasis what you are trying to achieve."

The agent can then help determine how to get there.

## Anabasis in Coding

In a coding workflow, Anabasis does not have to replace the coding agent.

Instead, it can sit one level above it.

A coding agent answers questions such as:

> "Implement this function."

Anabasis answers questions such as:

> "What should we implement next, why, what assumptions are we making, what does this change affect, and which agent or tool should handle it?"

A possible workflow is:

```text
Goal
 ↓
Understand
 ↓
Identify Unknowns
 ↓
Research
 ↓
Plan
 ↓
Delegate
 ↓
Implement
 ↓
Verify
 ↓
Update Project Knowledge
```

This makes Anabasis useful across the entire development lifecycle rather than only during code generation.

## UX Direction

Anabasis also suggests a different user experience from a traditional chat interface.

Today, many AI products are **prompt-centric**.

The primary UI is a text box.

Anabasis can gradually move Caverno toward a **goal-centric** or **project-centric** interface.

Instead of only showing conversation history, Caverno could expose persistent state such as:

```text
Project Goal

Current Understanding

Assumptions

Decisions

Open Questions

Active Tasks

Risks

Next Recommended Action
```

Chat remains important, but it becomes one interface into a larger persistent project state.

## Initial MVP

The first implementation should remain intentionally small.

Anabasis can initially be invoked inside normal Caverno chat:

```text
@anabasis
```

The first version does not need autonomous coding or tool execution.

Its initial responsibility can simply be to transform an ongoing conversation into structured project understanding.

For example:

```text
Goal

Current Understanding

Assumptions

Unresolved Questions

Recommended Next Step
```

This creates an immediate distinction between ordinary chat and Anabasis without requiring a major architectural rewrite.

## Evolution Path

Anabasis can grow incrementally.

### Phase 1 — Understand

Extract and maintain:

- Goal
- Context
- Assumptions
- Unknowns
- Open questions

### Phase 2 — Plan

Generate:

- Tasks
- Dependencies
- Decision points
- Verification criteria

### Phase 3 — Investigate

Use:

- Web research
- Local knowledge
- Project files
- Documentation
- External models

### Phase 4 — Delegate

Dispatch work to:

- Coding agents
- Research agents
- Review agents
- Specialized local models

### Phase 5 — Execute

Operate tools and environments with explicit permissions.

### Phase 6 — Learn

Update persistent project knowledge based on:

- New evidence
- Decisions
- Implementation results
- Failed approaches
- User feedback

At this point, Anabasis becomes less like a chatbot command and more like the coordinating intelligence of the Caverno workspace.

## Local-First Opportunity

Caverno has an opportunity to differentiate Anabasis through a **local-first execution model**.

Rather than assuming that all work happens in a remote hosted agent environment, Anabasis could coordinate resources available on the user's own machines.

Potential capabilities include:

- Local LLM inference
- Local source-code access
- Local knowledge bases
- User-managed tools
- Sandboxed execution
- Remote machines owned by the user
- Multiple local GPUs or compute nodes
- User-installable software and extensions

This creates an interesting inversion of the usual cloud-agent model.

The user's environment becomes the agent's world.

Anabasis becomes the entity capable of navigating it.

## Design Principle

A useful design principle is:

> **Anabasis should not pretend that the shadows are the world.**

When information is incomplete, it should recognize uncertainty.

When a claim can be checked, it should seek evidence.

When another tool or agent is better suited to the task, it should delegate.

When a decision belongs to the user, it should surface the decision clearly.

The goal is not maximum autonomy.

The goal is **better movement from uncertainty to understanding**.

## Possible Product Language

### Primary tagline

> **From shadows to understanding.**

### Alternatives

> **Beyond the shadows.**

> **The way out of the cave.**

> **Ascend beyond context.**

> **See beyond the model.**

> **From context to understanding.**

## Brand Architecture

A possible future naming hierarchy could be:

```text
Caverno
└── Anabasis
    ├── Research
    ├── Coding
    ├── Review
    ├── Knowledge
    └── Tools
```

In this model:

- **Caverno** is the platform.
- **Anabasis** is the coordinating agent.
- Specialized agents and tools perform individual forms of work.

Anabasis owns continuity of intent.

## Short Definition

> **Caverno Anabasis is an agent that recognizes the limits of its current context, identifies what is missing, coordinates the tools and intelligence needed to investigate it, and guides a project from incomplete information toward grounded understanding.**

## Brand Essence

**Caverno is the cave.**

**Anabasis is the ascent.**

**The goal is not merely to generate an answer, but to move beyond the shadows.**
