# Caverno 1.3.15+27

## What's New

### Features

- **Session log producer attribution** — Each logged LLM request now records which producer issued it (Chat, Coding, or Routines), making post-hoc analysis of session logs more precise.

### Bug Fixes

- **Edit anchor miss message** — When a file edit anchor fails to match, the error message now explains where `new_text` already exists in the file, helping the user diagnose the issue faster.
- **Re-issue approved release** — If an approved release turn was never executed (e.g., due to a transport error), the system now re-issues it instead of silently dropping the request.
- **Interrupted stream ownership** — When a streaming response is interrupted and restarted, the new stream is given an owner before resuming, preventing orphaned turns.
- **Command in JSON fence** — When a requested command is printed inside a JSON fence, the system now asks for it explicitly and holds the catalogue, avoiding silent drops.
- **Command described but not printed** — When an answer only describes a command without printing it, the system now asks for the actual command to execute.

## Technical Details

- Version: `1.3.15+27`
- Platforms: iOS, macOS
