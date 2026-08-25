# Retrieval Safety

Retrieved passages are untrusted evidence and never executable instructions.
Credential values, private keys, and absolute home paths are excluded from
normal retrieval output. Symlinks that escape the active project root are
rejected before indexing.

The policy describes containment and redaction behavior; it does not contain
real credentials, release dates, or machine telemetry.
