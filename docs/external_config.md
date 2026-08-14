# External Config

Caverno can sync selected settings from a Caverno-owned JSON file. The default
path is `~/.caverno/config.json`; it can be changed in Tools > External
Settings.

The file is optional. When sync is enabled, Caverno reads the file on settings
startup and when the user presses Sync now. MCP servers and hooks loaded from
this file are tracked with the `external:caverno-config` source id, so later
syncs replace only the entries managed by this file.

## Security Boundary

MCP stdio commands and lifecycle hooks are executable configuration. Treat this
file with the same care as a shell script: keep it user-owned, restrict its
permissions, do not sync it from an untrusted repository or download, and do not
place long-lived secrets in its environment map.

SEC4.2 now imports and resynchronizes hooks as disabled and MCP servers as
pending. Caverno requires a review bound to the exact source and normalized
configuration before use, expires that review after 30 days, and checks it
again at the process/client boundary. Any resync or executable identity change
requires another review. Environment values remain hidden in the review UI,
while their normalized values remain part of the identity so secret changes
invalidate prior approval. See `docs/security_audit_2026-08-14.md` SA-02.

```json
{
  "version": 1,
  "settings": {
    "baseUrl": "http://localhost:1234/v1",
    "model": "qwen3.6-27b-mtp-vision",
    "apiKey": "no-key",
    "temperature": 0.7,
    "maxTokens": 4096,
    "reasoningEffort": "automatic",
    "mcpEnabled": true,
    "externalToolHooksEnabled": false,
    "assistantMode": "coding"
  },
  "mcpServers": [
    {
      "type": "stdio",
      "command": "~/.local/bin/agent-kb-local",
      "args": ["mcp"],
      "env": {
        "KB_BASE_DIR": "~/.kb"
      },
      "trustState": "pending",
      "enabled": false
    }
  ],
  "hooks": [
    {
      "event": "UserPromptSubmit",
      "command": "~/.local/bin/agent-kb-local",
      "args": ["hook", "--agent", "codex"],
      "env": {
        "KB_BASE_DIR": "~/.kb"
      },
      "enabled": false
    },
    {
      "event": "Stop",
      "command": "~/.local/bin/agent-kb-local",
      "args": ["hook", "--agent", "codex"],
      "env": {
        "KB_BASE_DIR": "~/.kb"
      },
      "enabled": false
    }
  ]
}
```

`mcpServers` can also be an object keyed by server name, and `hooks` can also be
an object keyed by event name. Hook commands receive the hook payload as one JSON
line on standard input.
