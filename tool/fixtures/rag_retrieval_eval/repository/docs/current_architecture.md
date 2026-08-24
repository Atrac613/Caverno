# Current Architecture

Conversation and memory persistence use drift on SQLite. Conversation search
uses FTS5 and can fall back to lexical search when embeddings are unavailable.

The planned local-knowledge entry point is an explicit read-only
`search_knowledge` tool. Automatic retrieval is deferred until router shadow
evaluation passes.
