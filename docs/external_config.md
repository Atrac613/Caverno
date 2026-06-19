# External Config

Caverno can sync selected settings from a Caverno-owned JSON file. The default
path is `~/.caverno/config.json`; it can be changed in Tools > External
Settings.

The file is optional. When sync is enabled, Caverno reads the file on settings
startup and when the user presses Sync now. MCP servers and hooks loaded from
this file are tracked with the `external:caverno-config` source id, so later
syncs replace only the entries managed by this file.

```json
{
  "version": 1,
  "settings": {
    "baseUrl": "http://localhost:1234/v1",
    "model": "mlx-community/GLM-4.7-Flash-4bit",
    "apiKey": "no-key",
    "temperature": 0.7,
    "maxTokens": 4096,
    "reasoningEffort": "automatic",
    "mcpEnabled": true,
    "externalToolHooksEnabled": true,
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
      "trustState": "trusted",
      "enabled": true
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
      "enabled": true
    },
    {
      "event": "Stop",
      "command": "~/.local/bin/agent-kb-local",
      "args": ["hook", "--agent", "codex"],
      "env": {
        "KB_BASE_DIR": "~/.kb"
      },
      "enabled": true
    }
  ]
}
```

`mcpServers` can also be an object keyed by server name, and `hooks` can also be
an object keyed by event name. Hook commands receive the hook payload as one JSON
line on standard input.
