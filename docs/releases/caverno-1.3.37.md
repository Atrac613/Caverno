# Caverno v1.3.37

> Release date: 2026-09-20

## Summary

Built-in tool registry fix so all offered tools reach the initial tool selection, plus a clearer diagnostic feedback format and a new search-churn signal in session log triage.

## Changes

### Features

- **Elapsed time display** — Display elapsed time in minutes and seconds format (e.g. `13m 36s`) instead of clock-like `13:36`.
- **Search-churn signal** — Add a search-churn signal to session log triage that groups search queries by their longest identifier token and counts repeated phrasings of the same needle beyond a free threshold.

### Fixes

- **Built-in tool registry** — Register `inspect_file`, `delete_file`, and `lsp_go_to_definition`, which were offered in the LLM catalog but missing from `BuiltInToolRegistry`, so they were deferred behind `tool_search` and never reached a turn unless searched by name. Add a reverse-direction assertion that every catalog-offered tool is present in the registry. Initial tool selection grows from 23 to 26 headless and 38 to 41 on macOS.

### Refactors

- **Diagnostic feedback ordering** — Reorder the diagnostic feedback prompt copy so `instruction` and `diagnostics` come first, and drop `telemetry`, `analyzer`, and `language_diagnostics_bridge` fields the model cannot act on. The real payload shrinks from 1911 to 939 characters; the full payload is still kept in `ToolResultInfo.result`.

### Testing

- **Symbol-navigation catalog watch** — Register a session-log watch row for the `lsp_go_to_definition` tool-catalog key to verify the registry fix reaches real turns.

## Version

- `1.3.37+50`

## Notes

The tool registry fix is the third instance of the same defect class (a tool offered in the catalog but absent from the registry); the new reverse-direction assertion is expected to catch future occurrences.
