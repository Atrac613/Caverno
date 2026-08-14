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

The 2026-08-14 audit found that imported trust and hook enablement are not yet
quarantined behind a dedicated executable review. Until SEC4.2 is complete,
keep external hooks disabled, keep imported MCP servers disabled and pending,
and inspect every command, argument, endpoint, and environment key before
enabling it. See `docs/security_audit_2026-08-14.md` SA-02.

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
