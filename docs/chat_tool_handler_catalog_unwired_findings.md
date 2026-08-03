# Why ChatToolHandlerCatalog Is Not Wired Into Production

Read-only investigation, 2026-08-03, at `129b7d5a`. The architecture plan
assigns this question to Phase 1: "Learning **why it remains unwired** may reveal
an obstacle that also blocks the renewal."

It does. The catalogue and `TurnRuntime` are blocked on the same boundary.

This report answers the "why" question only. It does not produce the full I2
prerequisite matrix for the owner, UI, approval, result-store, Browser, Computer
Use and fallback ports, and it authorizes no wiring.

## Answer

`ChatToolHandlerCatalog` takes the turn owner as a **dispatch argument**.
Production takes it as a **closure capture**. Converting production to the
catalogue's shape is not a registry swap; it requires giving every handler its
dependencies explicitly, because the handlers are `ChatNotifier` methods and
binding them into the catalogue would capture the notifier — the exact thing
WS6-19's stop condition forbids.

That explicit-dependency step is port extraction, which is also what a
`TurnRuntime` prototype must do. The catalogue is therefore a **consumer** of the
renewal boundary rather than a shortcut around it.

## Two hypotheses the evidence rejects

**It is not coverage drift.** The catalogue and the production registry cover
exactly the same 32 tool names. The only difference is placement:
`lsp_go_to_definition` sits in the project-scoped group in the catalogue and in
the owner-scoped group in production.

```bash
# compare the tool-name literals in each module class
python3 - <<'PY'
import re
def names(path, classes):
    src = open(path).read()
    out = {}
    for cls in classes:
        m = re.search(r'(final )?class ' + re.escape(cls) + r'\b.*?\n(?=(final )?class |\Z)', src, re.S)
        body = m.group(0) if m else ''
        out[cls] = set(re.findall(r"'([a-z][a-z0-9_]{2,})'", body)) - {'handlers'}
    return out
cat = names('lib/features/chat/domain/services/chat_tool_handler_catalog.dart',
            ['ProjectScopedChatToolHandlers', 'OwnerScopedChatToolHandlers', 'ConversationChatToolHandlers'])
prod = names('lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart',
             ['_ProjectScopedToolHandlerModule', '_OwnerToolHandlerModule', '_ConversationToolHandlerModule'])
allc = set().union(*cat.values()); allp = set().union(*prod.values())
print(len(allc), len(allp), sorted(allc ^ allp))
PY
```

**It is not the ambient turn zones.** The first hypothesis in this investigation
was that handler bodies read `TurnGeneration` / `TurnThread` / `TurnProjectRoot`
and therefore could not accept an explicit owner. Measured, the whole chat
feature holds **five** such reads outside `runScoped`, and one of them already
prefers a parameter (`owner?.conversationId ?? TurnThread.currentId` in
`chat_notifier_approval_handlers.dart:76`). The hypothesis is rejected; the
zones are not what holds the catalogue out.

```bash
grep -rn "TurnGeneration\.\|TurnThread\.\|TurnProjectRoot\." lib/features/chat/ \
  --include='*.dart' | grep -v runScoped
```

## The actual difference

| | Production | Catalogue |
| --- | --- | --- |
| Handler type | `ChatToolHandler = Function(ToolCallInfo)` | `OwnerChatToolHandler = Function(ChatTurnOwner, ToolCallInfo)` |
| Owner arrives | captured when the registry is built | passed on every dispatch |
| Owner source | `_bindOwnerHandler` closes over an `OwnerToolApprovalCache` resolved beforehand | the caller supplies it |
| No resolvable owner | every owner-scoped tool in that registry returns `turn_owner_snapshot_unavailable` | decided per call |

`chat_tool_dispatcher.dart:6`, `chat_tool_handler_catalog.dart:7`, and
`chat_notifier_tool_handler_registry.dart:143`.

### Production buys freshness by reconstruction

`_buildToolHandlerRegistry` is called from inside the per-tool-call dispatch path
(`chat_notifier.dart:7548`), so **all 32 handler closures and a
`ChatToolDispatcher` are rebuilt for every tool call**, wrapped in three nested
`runScoped` zones. The closure-captured owner is never stale because the closure
never outlives one call.

This is why the current arrangement is correct, and also why the catalogue looks
redundant from the outside: both end up owner-correct per call. The difference is
that production pays for it with reconstruction and ambient scoping, while the
catalogue makes the owner an argument.

### What a binding would have to look like today

```dart
// The shape the catalogue needs, written against today's handlers:
(owner, toolCall) => notifier._handleWriteFile(
      toolCall,
      notifier._toolApprovalCache.forOwner(owner),
    )
```

The binding still closes over `notifier`. WS6-19's stop condition requires that
catalogue bindings capture no `ChatNotifier`, so satisfying it means each handler
receives what it needs — approval cache, UI callbacks, result store, project
root, services — rather than reaching them through the notifier.

## Corroboration for the turn-runtime design

`SubagentCatalogChildToolExecutionAdapter` is the only existing catalogue
consumer, and it checks `_isOwnerCurrent(request.taskIdentity)` **both before and
after** dispatch, treating an owner that expired mid-call as an uncertain
outcome rather than a failure. That is the identity-checked access pattern from
`docs/turn_runtime_codex_reference_findings.md` (Finding 2), implemented by hand
because the catalogue cannot enforce it at the point of access.

It also shows the adapter consuming a catalogue it does not construct. Who
constructs one in production is the unanswered half, and it is where the notifier
capture would appear.

## Consequences for the phasing

- Wiring the catalogue is **not** available as independent cheap work. The
  architecture plan already allows it to "proceed independently, but only under
  its existing WS6-19 gate"; this report is the evidence that the gate's stop
  condition cannot be met without port extraction.
- The prototype and the catalogue should be sequenced, not parallelised. Ports
  extracted for a `TurnRuntime` prototype are the same ports the catalogue needs.
- If the prototype is abandoned on its comparison gate, the catalogue does not
  become cheaper. It stays blocked for the same reason.

## Not established here

- The per-port prerequisite matrix (I2). This report names the obstacle; it does
  not enumerate which dependencies each of the six dispatcher entry points needs.
- Whether the per-tool-call registry rebuild has a measurable cost. It is 32
  closure allocations per call, observed but not profiled, and no correctness
  problem follows from it.
- Whether `lsp_go_to_definition`'s differing group placement is deliberate.
