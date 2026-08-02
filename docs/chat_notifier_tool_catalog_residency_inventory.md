# ChatNotifier Tool Catalogue Residency Inventory

Measured 2026-08-02. This is a read-only architecture finding; it does not
change production dispatch or payload composition.

## Conclusion

The catalogue is unwired because its registry-last migration gate was never
satisfied, not because the catalogue abstraction was rejected. The production
path still constructs `ChatToolHandlerRegistry.fromModules` from three modules
that capture `ChatNotifier`, then dispatches Computer Use and Browser tools
through protocol-specific intercepts before one generic MCP fallback.

The recorded WS6-19 gate requires WS6-1 through WS6-18 plus WS8-2 and WS8-7.
The decomposition closeout explicitly deferred several of those slices and
states that WS8-2 and WS8-7 must remove the final notifier-bound question and
goal bindings. WS6-19 also says to stop if any catalogue module still stores a
`ChatNotifier`. Current production code still violates that stop condition in
all three named modules.

This conclusion separates two kinds of evidence:

- **Recorded fact:** the task index and WS6-19 specification explicitly leave
  the migration deferred behind unmet ordering and no-notifier-capture gates.
- **Code fact:** the production composition has no `ChatToolHandlerCatalog`
  reference; the catalogue is consumed only by its tests and
  `SubagentCatalogChildToolExecutionAdapter`, which is also absent from the
  production composition path.
- **Inference:** no binding needs permanent residence in the core turn loop.
  The catalogue already accepts `ChatTurnOwner`, an explicit fallback port,
  and immutable calls. The remaining work is to expose owner-scoped services,
  approval/UI effects, and turn-state stores as narrow ports. Computer Use and
  Browser need policy-aware catalogue adapters, not plain fallback handlers.

Do not wire the catalogue from this finding. Reconcile the WS6-19 prerequisites
or approve a replacement safety contract first.

## Measurement Provenance

| Field | Value |
| --- | --- |
| Classified source revision | `de73f746f16eed1125b0f4f92cb44a11b57ea7de` |
| Analyser revision | `de73f746f16eed1125b0f4f92cb44a11b57ea7de` |
| Tool-manifest revision | `de73f746f16eed1125b0f4f92cb44a11b57ea7de` |
| Tool-manifest SHA-256 | `22c5f288efa870dcebbc498532f5f5ca82ab003e8bb20f6386f1ce4b8cf272dd` |
| Corpus-manifest SHA-256 | `b4b24f21d53d237cf80b5c34fb21fb2844cd477948f56286d514dae6666cbe4d` |
| Catalogue-snapshot SHA-256 | `e88e3934e120280a474df6061515f315f863de5f23eca55595d669eb02dcd3c6` |
| Private measurement SHA-256 | `b1937e7ff3d5088528315964e83941a4a4084e8b35e0a65bab373de1caaf3139` |
| Storage class | Private local Caverno inventory output; not committed |
| Corpus | 1 file, 2 records, 1 configuration segment, 1 catalogue snapshot |
| Logged range | `2026-08-02T02:45:00Z` through `2026-08-02T02:46:00Z`, inclusive |
| Represented build | `739957a5ae1958347b3ea118b34e388747f954c4`, clean |
| Definitions | 118 static plus 52 dynamic; 170 inventory rows |
| Effective snapshot | 169 definitions: 117 static plus 52 dynamic |
| Observation | 1 normalized submission for 1 definition; 169 inventory rows had zero submissions |

`web_search` is deliberately retained as a static row even though it was absent
from the pinned configuration. Dynamic names, schemas, endpoints, configuration
fingerprints, paths, and session identifiers remain private. `D001` through
`D052` are opaque ordinals obtained by sorting private dynamic names within the
pinned snapshot; the private output retains the reproducible mapping.

## Binding Inventory

The definition table links to these six production residency groups. “Can
register” means the handler can live behind an owner-bound catalogue after the
listed dependencies become ports; it does not assert that WS6-19 is ready.

| ID | Current binding and definitions | Notifier or runtime state read | Approval / owner plumbing | Can register? | Catalogue gap |
| --- | --- | --- | --- | --- | --- |
| B1 | `_ProjectScopedToolHandlerModule`; 5 static | Active coding-project access, project-root argument resolution, and `McpToolService` | Reads are project-scoped; process variants require the exact owner | Yes, through a project-access/root port and MCP execution port | None intrinsic; current module captures `ChatNotifier` |
| B2 | `_OwnerToolHandlerModule`; 23 static | Exact-owner snapshot/messages/project root; approval cache; Python runtime; LSP, skill, routine, file, process, SSH, Git, BLE, and serial services; success markers such as `_lastSaveSkillGeneration` | Required for mutations, commands, connections, skill/routine writes, owner expiry, compensation, and uncertain effects | Yes, but only after the remaining WS6 handlers expose typed owner-aware ports | No unrepresentable state: `ChatTurnOwner` is sufficient identity, but the current catalogue factory lacks the concrete ports and production modules still capture the notifier |
| B3 | `_ConversationToolHandlerModule`; 4 static | Interaction generation; saved task; question cache/UI; subagent task lifecycle and inherited catalogue; conversation goal; completed tool results; goal outcome/finalization stores | Exact owner is required for all four; `ask_user_question` also needs UI suspension/resumption | Yes after WS8-2, WS6-17, and WS8-7 replace notifier callbacks | Current handlers accept a generation and recover owner/state from the notifier. Passing only owner is adequate if question, subagent, goal, and turn-result ports are injected; there is no proven impossible turn-state dependency |
| B4 | `MacosComputerUseToolPolicy.allToolNames`; 19 static intercepted before the registry | Computer-use approval UI, policy/arming state, approval cache, MCP service, owner-current check, audit log, and post-action observation | Sensitive actions require exact-owner approval; observations do not, but post-action checks remain owner-fenced | Yes as a policy-aware module with separate action/observation callbacks | A single generic handler would lose the current action-versus-observation precedence and post-action protocol; the catalogue can represent it only with an adapter/module that preserves those branches |
| B5 | `BrowserToolPolicy.allTools`; 12 static intercepted before the registry | Chat approval mode, auto-review builder, browser approval UI, current browser session URL, approval cache, owner-current check, and MCP service | Five sensitive actions require exact-owner approval; seven observation actions do not | Yes as a policy-aware module with separate action/observation callbacks | A plain registry callback would erase the sensitive-action gate and secret-sanitized review path; inject those ports and preserve branch precedence |
| B6 | `ChatToolDispatcher.executeFallbackTool`; 55 static plus 52 dynamic | `McpToolService` catalogue/connection state and built-in or remote execution backends | No notifier turn state is intrinsically required; remote/built-in services own their own capability checks | Yes; retain one explicit `ChatMcpToolExecutionPort` fallback | None. This is already the catalogue's intended fallback shape |

No binding was found that reaches turn state in a way an owner-aware registry
cannot provide. B2-B5 do reach turn state that the *current catalogue
composition* does not provide, which is why copying the current callbacks into
the catalogue would violate the no-notifier-capture gate.

## Definition Inventory

`present` means present in the pinned effective snapshot, not enabled on every
platform or configuration. Observation counts are normalized tool-result
submissions in this small synthetic pinned corpus; zero is not evidence of
death or lack of production use.

| ID | Definition | Origin | Binding | Pinned snapshot | Submissions |
| --- | --- | --- | --- | --- | --- |
| S001 | `arp` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S002 | `ask_user_question` | static | [B3](#binding-inventory) | present | 0 (zero) |
| S003 | `ble_add_service` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S004 | `ble_connect` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S005 | `ble_disconnect` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S006 | `ble_discover_services` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S007 | `ble_get_connection_state` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S008 | `ble_get_peripheral_state` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S009 | `ble_get_scan_results` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S010 | `ble_read_characteristic` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S011 | `ble_start_advertising` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S012 | `ble_start_scan` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S013 | `ble_stop_advertising` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S014 | `ble_stop_scan` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S015 | `ble_subscribe_characteristic` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S016 | `ble_unsubscribe_characteristic` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S017 | `ble_update_characteristic` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S018 | `ble_write_characteristic` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S019 | `browser_click` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S020 | `browser_close` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S021 | `browser_eval` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S022 | `browser_fill` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S023 | `browser_get_content` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S024 | `browser_navigate_history` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S025 | `browser_open` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S026 | `browser_save_data` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S027 | `browser_screenshot` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S028 | `browser_snapshot` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S029 | `browser_submit` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S030 | `browser_wait` | static | [B5](#binding-inventory) | present | 0 (zero) |
| S031 | `computer_accessibility_snapshot` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S032 | `computer_click` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S033 | `computer_drag` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S034 | `computer_focus_window` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S035 | `computer_get_permissions` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S036 | `computer_list_displays` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S037 | `computer_list_windows` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S038 | `computer_move_mouse` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S039 | `computer_open_system_settings` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S040 | `computer_press_key` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S041 | `computer_request_permissions` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S042 | `computer_screenshot` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S043 | `computer_screenshot_window` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S044 | `computer_scroll` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S045 | `computer_start_system_audio_recording` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S046 | `computer_stop_system_audio_recording` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S047 | `computer_switch_space` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S048 | `computer_type_text` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S049 | `computer_vision_observe` | static | [B4](#binding-inventory) | present | 0 (zero) |
| S050 | `create_routine` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S051 | `delete_file` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S052 | `dns_lookup` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S053 | `dns_query` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S054 | `edit_file` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S055 | `find_files` | static | [B1](#binding-inventory) | present | 0 (zero) |
| S056 | `get_current_datetime` | static | [B6](#binding-inventory) | present | 1 (observed) |
| S057 | `get_subagent_result` | static | [B3](#binding-inventory) | present | 0 (zero) |
| S058 | `git_execute_command` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S059 | `git_finish_worktree_session` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S060 | `http_delete` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S061 | `http_get` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S062 | `http_head` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S063 | `http_patch` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S064 | `http_post` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S065 | `http_put` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S066 | `http_status` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S067 | `inspect_file` | static | [B1](#binding-inventory) | present | 0 (zero) |
| S068 | `interface_info` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S069 | `lan_get_scan_results` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S070 | `lan_scan` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S071 | `list_directory` | static | [B1](#binding-inventory) | present | 0 (zero) |
| S072 | `load_skill` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S073 | `local_execute_command` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S074 | `lsp_go_to_definition` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S075 | `mdns_browse` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S076 | `ndp` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S077 | `os_get_system_info` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S078 | `os_log_read` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S079 | `path_mtu` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S080 | `ping` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S081 | `ping6` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S082 | `port_check` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S083 | `process_cancel` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S084 | `process_list` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S085 | `process_start` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S086 | `process_status` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S087 | `process_tail` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S088 | `process_wait` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S089 | `read_file` | static | [B1](#binding-inventory) | present | 0 (zero) |
| S090 | `recall_memory` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S091 | `resolve_installed_dependency` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S092 | `rollback_last_file_change` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S093 | `route_lookup` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S094 | `run_python_script` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S095 | `run_tests` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S096 | `save_skill` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S097 | `search_files` | static | [B1](#binding-inventory) | present | 0 (zero) |
| S098 | `search_past_conversations` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S099 | `serial_close` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S100 | `serial_decode` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S101 | `serial_list_ports` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S102 | `serial_open` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S103 | `serial_read` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S104 | `serial_write` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S105 | `spawn_subagent` | static | [B3](#binding-inventory) | present | 0 (zero) |
| S106 | `ssh_connect` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S107 | `ssh_disconnect` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S108 | `ssh_execute_command` | static | [B2](#binding-inventory) | present | 0 (zero) |
| S109 | `ssl_certificate` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S110 | `tool_search` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S111 | `traceroute` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S112 | `update_goal` | static | [B3](#binding-inventory) | present | 0 (zero) |
| S113 | `web_search` | static | [B6](#binding-inventory) | absent from pinned configuration | 0 (zero) |
| S114 | `whois_lookup` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S115 | `wifi_get_connection_info` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S116 | `wifi_get_scan_results` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S117 | `wifi_scan` | static | [B6](#binding-inventory) | present | 0 (zero) |
| S118 | `write_file` | static | [B2](#binding-inventory) | present | 0 (zero) |
| D001 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D002 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D003 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D004 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D005 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D006 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D007 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D008 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D009 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D010 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D011 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D012 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D013 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D014 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D015 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D016 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D017 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D018 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D019 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D020 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D021 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D022 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D023 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D024 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D025 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D026 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D027 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D028 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D029 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D030 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D031 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D032 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D033 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D034 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D035 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D036 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D037 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D038 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D039 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D040 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D041 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D042 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D043 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D044 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D045 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D046 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D047 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D048 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D049 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D050 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D051 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |
| D052 | private snapshot definition | dynamic, opaque | [B6](#binding-inventory) | present | 0 (zero) |

## Reproduction and Inspection Commands

Run the private measurement with the documented analyser entrypoint, assigning
the private paths outside the repository:

```bash
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision de73f746f16eed1125b0f4f92cb44a11b57ea7de \
  --require-clean-source \
  --corpus-manifest "$PRIVATE_CORPUS_MANIFEST" \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --tool-manifest tool/chat_notifier_tool_catalog_inventory.json \
  --output "$PRIVATE_OUTPUT"
shasum -a 256 "$PRIVATE_OUTPUT"
jq '{sourceRevision,analyserRevision,inputs,corpus,summary,bindings}' \
  "$PRIVATE_OUTPUT"
jq '[.definitions[] | select(.origin == "static_manifest")] | length' \
  "$PRIVATE_OUTPUT"
jq '[.definitions[] | select(.origin == "dynamic_catalogue_snapshot")] | length' \
  "$PRIVATE_OUTPUT"
```

The checked-in architecture and history inspection used:

```bash
rg -n "ChatToolHandlerCatalog|SubagentCatalogChildToolExecutionAdapter|WS6-19|executeFallbackTool|_buildToolHandlerRegistry" \
  lib docs test -g '*.dart' -g '*.md'
git log --oneline --all -S'final class ChatToolHandlerCatalog' -- \
  lib/features/chat/domain/services/chat_tool_handler_catalog.dart
git log --oneline --all -S'SubagentCatalogChildToolExecutionAdapter' -- \
  lib/features/chat/data/datasources/subagent_catalog_child_tool_execution_adapter.dart
git diff --quiet de73f746f16eed1125b0f4f92cb44a11b57ea7de -- \
  lib tool/analyze_chat_notifier_inventory.py \
  tool/chat_notifier_tool_catalog_inventory.json
```

## Exclusions and Unresolved Items

- Payload subsetting and KV-cache prefix stability are excluded; this report is
  about handler code residency.
- The corpus is intentionally tiny and synthetic. It establishes enumeration
  and joins, not representative frequency or traffic share.
- Dynamic names and schemas are excluded from checked-in documentation. The
  opaque rows preserve completeness without publishing private MCP topology.
- Platform and settings gates remain those recorded per definition in the
  static manifest; `present` does not override them.
- The report does not claim the deferred WS6/WS8 slices are still the best
  implementation design. Replacing their gate requires a separate reviewed
  safety contract with equivalent owner, precedence, fallback, and poison-test
  guarantees.
- Production `SubagentCatalogChildToolExecutionAdapter` wiring remains
  unresolved and belongs with the eventual catalogue composition-root task.
