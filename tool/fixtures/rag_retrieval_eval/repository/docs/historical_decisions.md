# Historical Decisions

Tool results are usually resent as a user-role message because some local
models handle tool-role messages poorly.

LL5 deliberately used brute-force cosine for conversation embeddings. ANN was
deferred until scale measurements justify another dependency.

A third knowledge store was rejected. Caverno owns current project snapshots,
while agent-kb owns durable cross-agent history and generated wiki pages.
