# Current Runtime

The current response context ceiling is 8192 tokens. The `safeMode` feature is
not disabled; it remains enabled for every new workspace.

The `CAVERNO_API_KEY` environment variable names the API credential. Its value
is injected at runtime and is not stored in the repository. Managed test
passwords rotate every 90 days; this is policy metadata, not a password value.

The current endpoint alias is `primary` and resolves to localhost port 8181.
