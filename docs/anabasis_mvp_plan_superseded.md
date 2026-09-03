# Anabasis MVP Implementation Plan

**Status: superseded 2026-09-02 by
[`ANABASIS_ORCHESTRATOR_ARCHITECTURE.md`](ANABASIS_ORCHESTRATOR_ARCHITECTURE.md).
Kept as the record of why.**

This plan is a good design for a greenfield application and the wrong design
for Caverno. Surveying the codebase before implementing it — the discipline the
successor document now enforces as a rule — showed that roughly nine tenths of
its proposed schema already existed under different names:

| Proposed here | Already existed as |
| --- | --- |
| `AnabasisState.goal` | `ConversationGoal` + `ConversationWorkflowSpec.goal` |
| `facts` with confidence | `MemoryEntry` (`fact` type, confidence, TTL) |
| `open_questions` | `openQuestions` + `ConversationOpenQuestionProgress` |
| `decisions` | the planning JSON's `kind:"decision"` path |
| §7 structured JSON output | the planning request's pinned JSON schema |
| §9 "previous state + conversation → updated state" | `savedSpec` / `openQuestionDelta` fed back into every planning request |
| snapshots | `ConversationPlanArtifact.revisions` |

§19 names the transformation `Previous State + Conversation → Updated State` as
"the most important early artifact… if this works reliably, the rest of the
product can grow around it." It already worked. It had been shipped as the
`/plan` re-planning path.

What the survey found genuinely missing was one field. The contract model
already carried `assumption` / `material` / `confirmed` provenance, and
`MaterialContractAssumptionGuard` already refused mutations while a material
assumption stayed unconfirmed — but no production code ever wrote
`assumption: true`, so the guard was armed but never fired. The fact/assumption
separation this plan proposes as its central differentiator was therefore not a
new subsystem; it was a missing producer on live machinery.

Two further problems, both structural:

- **A fourth authoritative conversation state.** `AnabasisState` would have
  added a second `goal` string, a second open-questions list and a second
  decisions list, directly reversing
  `docs/chat_notifier_concept_overlap_inventory.md`, which had concluded a
  month earlier that the user has three durable concepts and recommended
  *reducing* authored sources.
- **The out-of-scope list removed the differentiator.** §3 rules out web
  access, file inspection and tool execution, leaving conversation text as the
  only input — the least grounded source available — for a product whose entire
  pitch is leaving the cave. This objection was later answered properly: the
  successor keeps the MVP small but spends its smallness on the epistemic
  producer rather than on a state schema.

The vision sections (§20 in particular) survived intact and are the direct
ancestor of the orchestrator design. Read this document for the product
intuition; read the successor for what to build.

---

## 1. Goal

Build the first usable version of **Anabasis** as an orchestration layer inside Caverno.

The MVP should not attempt to become a fully autonomous coding agent.

Its first responsibility is to transform an ongoing conversation into a persistent, structured understanding of the user's goal, current assumptions, unresolved questions, and recommended next action.

The key product hypothesis is:

> **Anabasis becomes useful when it maintains project intent and uncertainty better than a normal chat session.**

---

## 2. MVP Product Definition

### User-facing invocation

Anabasis is initially invoked from the normal Caverno chat interface.

Example:

```text
@anabasis
```

Optional command variants can be added later, but the first version should work with a single invocation.

Example interaction:

```text
User:
We need to add offline sync to this Flutter application.

User:
@anabasis
```

Anabasis returns a structured project state:

```text
Goal

Current Understanding

Assumptions

Open Questions

Risks

Recommended Next Step
```

The result is not just generated text.

It should also update a persistent structured state associated with the conversation or project.

---

## 3. MVP Scope

### In scope

The MVP should:

- Detect `@anabasis` in chat.
- Gather relevant conversation context.
- Ask an LLM to analyze the context using a dedicated Anabasis system prompt.
- Produce a structured result.
- Parse the result into a typed internal state.
- Persist the latest Anabasis state.
- Display a human-readable summary in chat.
- Allow Anabasis to update an existing state rather than recreating it from scratch.
- Track uncertainty explicitly.
- Recommend one clear next action.
- Record decisions made by the user.
- Distinguish facts, assumptions, and open questions.

### Out of scope

The MVP should **not** initially:

- Modify source code.
- Execute shell commands.
- Browse the web autonomously.
- Install software.
- Spawn multiple agents.
- Manage VMs.
- Run long-lived background tasks.
- Make irreversible decisions without user approval.
- Automatically start implementation work.
- Maintain a complex knowledge graph.

These capabilities can be added after the core state-management concept proves useful.

---

## 4. Core User Experience

### Basic flow

```text
Conversation
    ↓
@anabasis
    ↓
Collect Context
    ↓
Analyze
    ↓
Update Structured State
    ↓
Render Summary
    ↓
Recommend Next Step
```

### Example output

```markdown
## Goal

Add reliable offline synchronization to the Flutter application.

## Current Understanding

- The application currently stores data locally.
- A remote API already exists.
- Conflict resolution has not been designed.

## Assumptions

- Users may edit the same record from multiple devices.
- Synchronization does not need to be real-time.

## Open Questions

1. Which data types require synchronization?
2. What conflict resolution policy should be used?
3. Is background sync required on iOS and Android?

## Risks

- Incorrect conflict handling could overwrite user data.
- Platform background execution limits may affect synchronization.

## Recommended Next Step

Define the synchronization data model and conflict-resolution policy before implementation.
```

---

## 5. Core Data Model

The internal state should be structured and machine-readable.

A minimal model:

```json
{
  "goal": "string",
  "summary": "string",
  "facts": [
    {
      "text": "string",
      "source": "conversation",
      "confidence": 1.0
    }
  ],
  "assumptions": [
    {
      "text": "string",
      "confidence": 0.7
    }
  ],
  "decisions": [
    {
      "text": "string",
      "status": "accepted"
    }
  ],
  "open_questions": [
    {
      "question": "string",
      "priority": "high"
    }
  ],
  "risks": [
    {
      "text": "string",
      "severity": "medium"
    }
  ],
  "next_action": {
    "description": "string",
    "reason": "string"
  },
  "updated_at": "ISO-8601 timestamp"
}
```

### Recommended typed model

In Dart:

```dart
class AnabasisState {
  final String goal;
  final String summary;
  final List<AnabasisFact> facts;
  final List<AnabasisAssumption> assumptions;
  final List<AnabasisDecision> decisions;
  final List<AnabasisQuestion> openQuestions;
  final List<AnabasisRisk> risks;
  final AnabasisNextAction? nextAction;
  final DateTime updatedAt;
}
```

The first schema should remain intentionally small.

Avoid adding task graphs, agent graphs, embeddings, or workflow engines until the basic state proves valuable.

---

## 6. Anabasis System Prompt

The MVP should use a dedicated system prompt.

A starting point:

```text
You are Anabasis, an orchestration and project-understanding agent inside Caverno.

Your role is not to immediately solve or implement the user's request.

Your role is to maintain a clear model of:

- the user's goal,
- verified facts,
- assumptions,
- decisions,
- unresolved questions,
- risks,
- and the most useful next action.

Do not treat uncertain information as fact.

Explicitly identify knowledge gaps.

Prefer one high-value next action over a long list of generic suggestions.

Do not generate implementation code unless explicitly requested by another workflow.

When updating an existing Anabasis state:

- preserve valid previous decisions,
- remove information contradicted by newer evidence,
- distinguish new facts from assumptions,
- update unresolved questions,
- and explain meaningful changes.

Return output using the required structured schema.
```

This prompt should eventually become versioned.

Example:

```text
anabasis_prompt_v1
```

---

## 7. Structured LLM Output

Do not rely on free-form Markdown as the source of truth.

The model should return structured JSON matching a schema.

Example:

```json
{
  "goal": "...",
  "summary": "...",
  "facts": [],
  "assumptions": [],
  "decisions": [],
  "open_questions": [],
  "risks": [],
  "next_action": {
    "description": "...",
    "reason": "..."
  }
}
```

The UI can render Markdown from this state.

This separation is important:

```text
LLM Output
   ↓
Structured State
   ↓
UI Rendering
```

not:

```text
LLM Output
   ↓
Markdown
   ↓
Attempt to parse Markdown later
```

---

## 8. Context Selection

The MVP should avoid blindly sending the entire conversation if it becomes large.

Start with a simple strategy:

### Phase A

Send:

- current user message,
- previous N messages,
- current Anabasis state.

For example:

```text
last 20 messages
+
current AnabasisState
```

### Phase B

Later introduce context selection based on:

- semantic relevance,
- decisions,
- project files,
- prior Anabasis snapshots.

The state should eventually become more important than raw conversation history.

---

## 9. State Update Strategy

Anabasis should behave as a state updater.

Conceptually:

```text
Previous State
      +
Recent Conversation
      ↓
   Anabasis
      ↓
Updated State
```

The model should not regenerate the project interpretation from zero every time.

This enables continuity and makes Anabasis different from ordinary chat.

---

## 10. UI Design for MVP

Do not redesign the entire Caverno interface initially.

Add Anabasis as a lightweight extension to the existing chat.

### First version

Support:

```text
@anabasis
```

When invoked:

1. Show an "Analyzing project state..." indicator.
2. Run Anabasis.
3. Insert the rendered result into chat.
4. Store the structured state.

### Optional side panel

A small persistent panel can show:

```text
ANABASIS

Goal
...

Open Questions
3

Risks
2

Next
Define sync conflict policy
```

This can be added after the command flow is working.

---

## 11. Suggested Internal Architecture

```text
Chat UI
  │
  ├── Normal message
  │      └── Existing LLM flow
  │
  └── @anabasis
         │
         ▼
   AnabasisController
         │
         ├── ContextBuilder
         ├── StateRepository
         └── AnabasisService
                 │
                 ▼
             LLM Provider
                 │
                 ▼
          Structured Response
                 │
                 ▼
           State Validator
                 │
                 ▼
          AnabasisState
                 │
          ┌──────┴──────┐
          ▼             ▼
      Persistence    UI Renderer
```

### Suggested components

```text
AnabasisController
AnabasisService
AnabasisContextBuilder
AnabasisStateRepository
AnabasisPromptBuilder
AnabasisResponseParser
AnabasisStateValidator
AnabasisRenderer
```

Keep provider-specific LLM logic outside the Anabasis domain layer.

---

## 12. Storage

For the MVP, persist one active Anabasis state per conversation.

Example relationship:

```text
Conversation
    └── AnabasisState
```

Possible storage:

```text
conversation_id
state_json
prompt_version
model
created_at
updated_at
```

Optionally retain historical snapshots:

```text
AnabasisSnapshot
```

but this is not mandatory for v1.

---

## 13. Model Independence

Anabasis should not depend on one specific model.

It should work through Caverno's existing OpenAI-compatible abstraction.

Important requirement:

> The orchestration behavior belongs to Caverno, not to the model.

Different models can therefore be evaluated against the same Anabasis benchmark.

---

## 14. Error Handling

The MVP must handle:

### Invalid JSON

Retry once with:

```text
Return only valid JSON matching the schema.
```

### Missing required fields

Run schema repair or reject the response.

### Model failure

Do not overwrite the previous valid Anabasis state.

### Low confidence

Expose uncertainty rather than inventing information.

### Excessive context

Reduce recent conversation history before failing.

---

## 15. Evaluation

The MVP should be evaluated differently from a normal chatbot.

### Primary metrics

#### 1. Goal accuracy

Does Anabasis correctly identify what the user is trying to achieve?

#### 2. Fact / assumption separation

Does it avoid presenting assumptions as facts?

#### 3. Open-question quality

Does it identify the important missing information?

#### 4. Next-action usefulness

Does the recommended next action meaningfully reduce uncertainty or move the project forward?

#### 5. Continuity

Does Anabasis preserve important decisions across multiple invocations?

#### 6. Update quality

Does it correctly revise the state when new information contradicts old assumptions?

---

## 16. MVP Test Scenarios

Create a small evaluation set before implementation is complete.

### Scenario 1 — Simple feature request

Conversation:

```text
I want to add dark mode to the app.
```

Expected:

- Correct goal.
- Minimal unknowns.
- Clear next step.

### Scenario 2 — Ambiguous feature request

```text
Make synchronization better.
```

Expected:

- Does not invent requirements.
- Identifies ambiguity.
- Asks useful questions.

### Scenario 3 — Contradiction

Earlier:

```text
We will only support Android.
```

Later:

```text
We also need iOS support.
```

Expected:

- Updates scope.
- Removes obsolete assumption.
- Identifies new platform risk.

### Scenario 4 — Decision preservation

```text
We decided to use SQLite.
```

Later conversations discuss storage.

Expected:

- SQLite remains recorded as a decision unless explicitly changed.

### Scenario 5 — Large conversation

Expected:

- Important goal and decisions survive even when old messages leave the immediate context window.

---

## 17. MVP Acceptance Criteria

The MVP is successful if all of the following are true:

- `@anabasis` can be invoked from Caverno chat.
- Anabasis returns valid structured state.
- State persists between invocations.
- The UI renders the state clearly.
- Facts and assumptions are separated.
- Existing decisions are preserved.
- Open questions are updated over time.
- One recommended next action is generated.
- New information can revise previous assumptions.
- Invalid model responses do not destroy the previous state.
- The implementation works with more than one LLM provider.

---

## 18. Implementation Phases

### Phase 0 — Prototype

Goal:

Validate the prompt and state schema before integrating deeply into Caverno.

Tasks:

- Define `AnabasisState`.
- Define JSON schema.
- Write `anabasis_prompt_v1`.
- Test manually with 10–20 conversations.
- Compare at least two models.

Deliverable:

```text
Conversation + Previous State → JSON State
```

---

### Phase 1 — Chat Integration

Tasks:

- Detect `@anabasis`.
- Add `AnabasisService`.
- Build recent-message context.
- Call existing LLM provider abstraction.
- Parse structured output.
- Render result in chat.

Deliverable:

Working Anabasis command inside Caverno.

---

### Phase 2 — Persistence

Tasks:

- Store state per conversation.
- Include previous state in future runs.
- Preserve decisions.
- Support state updates.

Deliverable:

Anabasis maintains continuity across a conversation.

---

### Phase 3 — UX Improvement

Tasks:

- Add a compact Anabasis state panel.
- Show goal.
- Show unresolved question count.
- Show next action.
- Add manual "Refresh Anabasis" action.

Deliverable:

Project state becomes visible independently from chat history.

---

### Phase 4 — Planning

After the MVP proves useful, add a second capability:

```text
@anabasis plan
```

Possible state:

```text
Goal
 ↓
Milestones
 ↓
Tasks
 ↓
Dependencies
 ↓
Verification
```

Do not add this before the understanding/state MVP is stable.

---

## 19. Recommended First Development Tasks

Start in this order:

1. Define the `AnabasisState` schema.
2. Write `anabasis_prompt_v1`.
3. Create 10 representative test conversations.
4. Run the prompt manually against multiple models.
5. Refine the schema until outputs are stable.
6. Implement `AnabasisService`.
7. Add `@anabasis` command detection.
8. Render the structured result in chat.
9. Persist one state per conversation.
10. Add regression tests for state updates.

The most important early artifact is **not the UI**.

It is:

```text
Previous Anabasis State
+
Conversation
→
Correct Updated Anabasis State
```

If this transformation works reliably, the rest of the product can grow around it.

---

## 20. Future Direction

Once the MVP is proven, Anabasis can evolve from a passive state analyzer into an active orchestrator.

Possible progression:

```text
Understand
    ↓
Plan
    ↓
Investigate
    ↓
Delegate
    ↓
Execute
    ↓
Verify
    ↓
Learn
```

Later capabilities may include:

- `@anabasis research`
- `@anabasis plan`
- `@anabasis review`
- Delegation to coding agents
- Delegation to local models
- Web research
- Project-file inspection
- Tool execution
- Sandboxed environments
- Persistent project knowledge
- Multi-agent workflows
- Automatic verification
- Local-first execution across user-owned machines

However, these capabilities should be built on top of a reliable project-state model.

---

## 21. MVP Principle

The MVP should answer one question extremely well:

> **Given everything discussed so far, what are we actually trying to achieve, what do we know, what are we assuming, what is still unclear, and what should we decide or investigate next?**

If Anabasis can answer that consistently and maintain the answer over time, it already provides a fundamentally different experience from ordinary LLM chat.
