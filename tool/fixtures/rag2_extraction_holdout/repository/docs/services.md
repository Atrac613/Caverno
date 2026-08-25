# Service References

The billing console is served at `https://billing.local:8443`.
The status dashboard uses
`https://status.local/health` for public checks.

Traffic moves from edge gateway endpoint `https://edge.local:7444` to core API
endpoint `https://core.local:9443` during normal operation.

For examples only, use `https://example.invalid:6553` in tests.
The broken endpoint uses `https://bad.local:notaport` and must be ignored.
