import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';

void main() {
  test('systemPrompt rejects one-off validation markers', () {
    expect(
      MemoryExtractionDraftService.systemPrompt,
      contains('one-off task requirements'),
    );
    expect(
      MemoryExtractionDraftService.systemPrompt,
      contains('validation markers'),
    );
    expect(
      MemoryExtractionDraftService.systemPrompt,
      contains('one-off lookup results'),
    );
    expect(
      MemoryExtractionDraftService.systemPrompt,
      contains('saved artifact paths'),
    );
    expect(
      MemoryExtractionDraftService.systemPrompt,
      contains('exact local paths or filenames'),
    );
    expect(
      MemoryExtractionDraftService.systemPrompt,
      contains('uppercase identifiers'),
    );
    expect(MemoryExtractionDraftService.systemPrompt, contains('_CANARY'));
  });

  test('buildInput includes current profile and clipped conversation tail', () {
    final input = MemoryExtractionDraftService.buildInput(
      [
        Message(
          id: 'user-1',
          content: 'I prefer concise coding explanations.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 4, 18, 12),
        ),
        Message(
          id: 'assistant-1',
          content: 'Understood. I will keep responses brief.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 4, 18, 12, 1),
        ),
      ],
      UserMemoryProfile(
        persona: const ['Flutter developer'],
        preferences: const ['Concise answers'],
        doNot: const ['Avoid long digressions'],
        updatedAt: DateTime(2026, 4, 18, 11, 30),
      ),
      toolResults: [
        ToolResultInfo(
          id: 'tool-1',
          name: 'git_execute_command',
          arguments: const {'command': 'status --short'},
          result: '{"exit_code":0,"stdout":"","stderr":""}',
        ),
      ],
    );

    expect(input, contains('Current profile:'));
    expect(input, contains('Flutter developer'));
    expect(input, contains('- user: I prefer concise coding explanations.'));
    expect(input, contains('Application-executed tool results'));
    expect(input, contains('git_execute_command'));
    expect(input, contains('Only include open_loops when the latest turn'));
    expect(input, contains('Do not save assistant claims about local file'));
    expect(input, contains('git status or git log result only proves'));
    expect(input, contains('code=unexecuted_file_save'));
    expect(input, contains('missing file-operation tool action'));
    expect(input, contains('Do not summarize browser actions'));
    expect(input, contains('code=unexecuted_browser_action'));
    expect(input, contains('Treat search_past_conversations'));
    expect(input, contains('missing files'));
    expect(input, contains('unverified causes of interruptions'));
    expect(input, contains('stream_end completions'));
    expect(input, contains('validation markers'));
    expect(input, contains('current-turn tool-use instructions'));
    expect(input, contains('one-off lookup results'));
    expect(input, contains('saved artifact paths'));
    expect(input, contains('without exact local paths or filenames'));
    expect(input, contains('uppercase identifiers ending in _OK'));
    expect(input, contains('_MARKER'));
    expect(input, contains('_CANARY'));
    expect(input, contains('Output rules:'));
  });

  test('buildInput marks recalled context and keeps latest tool blockers', () {
    final toolResults = <ToolResultInfo>[
      ToolResultInfo(
        id: 'tool-1',
        name: 'search_past_conversations',
        arguments: const {'query': 'Android BLE data corruption'},
        result: 'assistant: Native byte processing is the root cause.',
      ),
      for (var index = 2; index <= 8; index += 1)
        ToolResultInfo(
          id: 'tool-$index',
          name: 'read_file',
          arguments: {'path': 'lib/file_$index.dart'},
          result: '{"path":"lib/file_$index.dart","content":"ok"}',
        ),
      ToolResultInfo(
        id: 'tool-9',
        name: 'read_file',
        arguments: const {
          'path': 'packages/pes1_ble/android/UBProviderImpl.kt',
        },
        result:
            '{"error":"File does not exist: packages/pes1_ble/android/UBProviderImpl.kt"}',
      ),
      ToolResultInfo(
        id: 'tool-10',
        name: 'list_directory',
        arguments: const {'path': 'packages/universal_ble'},
        result: '{"error":"Directory does not exist: packages/universal_ble"}',
      ),
    ];

    final input = MemoryExtractionDraftService.buildInput(
      [
        Message(
          id: 'user-1',
          content: 'Find the Android BLE data corruption root cause.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 5, 28, 12),
        ),
        Message(
          id: 'assistant-1',
          content:
              'Past investigation suspected native-side byte conversion, but source files are missing.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 5, 28, 12, 1),
        ),
      ],
      UserMemoryProfile(
        persona: const [],
        preferences: const [],
        doNot: const [],
        updatedAt: DateTime(2026, 5, 28, 11, 30),
      ),
      toolResults: toolResults,
    );

    expect(input, contains('evidence_scope=historical context'));
    expect(input, contains('verify against direct user statements'));
    expect(input, contains('omitted 2 intermediate tool result(s)'));
    expect(input, contains('File does not exist'));
    expect(input, contains('Directory does not exist'));
    expect(input, isNot(contains('lib/file_5.dart')));
    expect(input, contains('unsupported prior assistant conclusions'));
    expect(input, contains('root-cause fact'));
  });

  test('buildInput includes Open-Meteo weather code interpretation', () {
    final input = MemoryExtractionDraftService.buildInput(
      [
        Message(
          id: 'user-1',
          content: 'Create a Tokyo weather report for 2026-06-03.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 2, 9),
        ),
      ],
      UserMemoryProfile(
        persona: const [],
        preferences: const [],
        doNot: const [],
        updatedAt: DateTime(2026, 6, 2, 9),
      ),
      toolResults: [
        ToolResultInfo(
          id: 'tool-1',
          name: 'http_get',
          arguments: const {'url': 'https://api.open-meteo.com/v1/forecast'},
          result: jsonEncode({
            'url': 'https://api.open-meteo.com/v1/forecast',
            'status_code': 200,
            'body': jsonEncode({
              'daily_units': {'weathercode': 'wmo code'},
              'daily': {
                'time': ['2026-06-03'],
                'weathercode': [65],
              },
            }),
          }),
        ),
      ],
    );

    expect(input, contains('interpretation='));
    expect(
      input,
      contains(
        'Open-Meteo daily 2026-06-03 weather code 65 = Rain: Heavy intensity.',
      ),
    );
    expect(
      input,
      contains(
        'drizzle codes are 51, 53, and 55, while rain codes are 61, 63, and 65',
      ),
    );
  });

  test('parseDraft returns normalized memory extraction draft', () {
    const raw = '''
{
  "summary":"User prefers concise coding explanations.",
  "open_loops":["Need a follow-up on tests"],
  "profile":{
    "persona":["Flutter developer"],
    "preferences":["Concise answers"],
    "do_not":["Avoid long digressions"]
  },
  "memories":[
    {"text":"The user prefers concise coding explanations.","type":"preference","confidence":0.9,"importance":0.8,"ttl_days":null}
  ]
}
''';

    final draft = MemoryExtractionDraftService.parseDraft(raw);

    expect(draft, isNotNull);
    expect(draft!.summary, 'User prefers concise coding explanations.');
    expect(draft.openLoops, ['Need a follow-up on tests']);
    expect(draft.persona, ['Flutter developer']);
    expect(draft.preferences, ['Concise answers']);
    expect(draft.doNot, ['Avoid long digressions']);
    expect(draft.entries, hasLength(1));
    expect(draft.entries.single.type, 'preference');
  });

  test('parseDraft demotes unverified causal diagnostics from facts', () {
    const raw = '''
{
  "summary":"Investigated a session log interruption.",
  "open_loops":[],
  "profile":{
    "persona":[],
    "preferences":[],
    "do_not":[]
  },
  "memories":[
    {
      "text":"Session log e42da492 contains 19 entries with no recorded errors, network timeouts, or server disconnections.",
      "type":"fact",
      "confidence":1.0,
      "importance":0.9,
      "ttl_days":30
    },
    {
      "text":"Entries 17 and 18 in session log e42da492 show structural anomalies (stream_end) likely causing Caverno to terminate the session, despite no explicit error flags.",
      "type":"fact",
      "confidence":0.8,
      "importance":0.9,
      "ttl_days":30
    }
  ]
}
''';

    final draft = MemoryExtractionDraftService.parseDraft(raw);

    expect(draft, isNotNull);
    expect(draft!.entries, hasLength(2));
    expect(draft.entries.first.type, 'fact');
    expect(draft.entries.first.confidence, 1.0);
    expect(draft.entries.last.type, 'topic');
    expect(draft.entries.last.confidence, 0.4);
    expect(draft.entries.last.importance, 0.6);
    expect(draft.entries.last.text, contains('likely causing Caverno'));
  });

  test('parseDraft drops saved artifact path memories from JSON', () {
    const raw = '''
{
  "summary":"Saved a generated Markdown browser summary.",
  "open_loops":[],
  "profile":{
    "persona":[],
    "preferences":[],
    "do_not":[]
  },
  "memories":[
    {
      "text":"Saved Hydrangea Wikipedia summary to /Users/example/Library/Application Support/com.noguwo.apps.caverno/browser-saves/hydrangea_summary.md (5719 bytes, MD format).",
      "type":"fact",
      "confidence":1.0,
      "importance":0.8,
      "ttl_days":30
    },
    {
      "text":"The user prefers concise coding explanations.",
      "type":"preference",
      "confidence":0.9,
      "importance":0.8,
      "ttl_days":null
    }
  ]
}
''';

    final draft = MemoryExtractionDraftService.parseDraft(raw);

    expect(draft, isNotNull);
    expect(draft!.entries, hasLength(1));
    expect(draft.entries.single.text, contains('concise coding explanations'));
    expect(draft.entries.single.text, isNot(contains('browser-saves')));
  });

  test('parseDraft preserves unexecuted file save as an open loop', () {
    final inputContext = MemoryExtractionDraftService.buildInput(
      [
        Message(
          id: 'user-1',
          content: 'Create release notes for the current version.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 7, 9),
        ),
        Message(
          id: 'assistant-1',
          content:
              'The release note draft was created. Next, run the dry release check.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 7, 9, 1),
        ),
      ],
      UserMemoryProfile(
        persona: const [],
        preferences: const [],
        doNot: const [],
        updatedAt: DateTime(2026, 6, 7, 9),
      ),
      toolResults: [
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: const {'path': 'docs/releases/caverno-1.3.4.md'},
          result: jsonEncode({
            'ok': false,
            'code': 'unexecuted_file_save',
            'error': 'The requested file save was not executed.',
          }),
        ),
      ],
    );
    const raw = '''
{
  "summary":"Release note draft created; dry run pending.",
  "open_loops":["Confirm and execute dry run for release process"],
  "profile":{
    "persona":[],
    "preferences":[],
    "do_not":[]
  },
  "memories":[
    {
      "text":"Release note draft created for the current version.",
      "type":"fact",
      "confidence":0.95,
      "importance":0.8,
      "ttl_days":30
    },
    {
      "text":"Release entry point script is tool/release_ios_macos.sh.",
      "type":"fact",
      "confidence":0.95,
      "importance":0.7,
      "ttl_days":30
    }
  ]
}
''';

    final draft = MemoryExtractionDraftService.parseDraft(
      raw,
      inputContext: inputContext,
    );

    expect(draft, isNotNull);
    expect(
      draft!.summary,
      'Latest requested file save or mutation remains unexecuted.',
    );
    expect(
      draft.openLoops.first,
      'Create or save the requested file with a file-operation tool.',
    );
    expect(
      draft.openLoops,
      contains('Confirm and execute dry run for release process'),
    );
    expect(draft.entries, hasLength(1));
    expect(
      draft.entries.single.text,
      'Release entry point script is tool/release_ios_macos.sh.',
    );
  });

  test('parseDraft drops branch creation memories without creation evidence', () {
    final inputContext = MemoryExtractionDraftService.buildInput(
      [
        Message(
          id: 'user-1',
          content: 'Create a new branch and update the mobile settings screen.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 10, 18),
        ),
        Message(
          id: 'assistant-1',
          content: 'The branch was created and the settings work started.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 10, 18, 1),
        ),
      ],
      UserMemoryProfile(
        persona: const [],
        preferences: const [],
        doNot: const [],
        updatedAt: DateTime(2026, 6, 10, 18),
      ),
      toolResults: [
        ToolResultInfo(
          id: 'tool-status',
          name: 'git_execute_command',
          arguments: const {
            'command': 'status',
            'working_directory': '/tmp/project',
          },
          result: jsonEncode({
            'command': 'git status',
            'working_directory': '/tmp/project',
            'exit_code': 0,
            'stdout':
                'On branch fix/mobile-hide-desktop-settings\nnothing to commit, working tree clean\n',
            'stderr': '',
          }),
        ),
      ],
    );
    const raw = '''
{
  "summary":"Branch exists and settings changes are pending.",
  "open_loops":["Apply settings screen changes"],
  "profile":{
    "persona":[],
    "preferences":[],
    "do_not":[]
  },
  "memories":[
    {
      "text":"Git branch fix/mobile-hide-desktop-settings was created for the settings UI changes.",
      "type":"fact",
      "confidence":1.0,
      "importance":0.8,
      "ttl_days":7
    },
    {
      "text":"User is working on mobile settings visibility.",
      "type":"topic",
      "confidence":0.8,
      "importance":0.6,
      "ttl_days":7
    }
  ]
}
''';

    final draft = MemoryExtractionDraftService.parseDraft(
      raw,
      inputContext: inputContext,
    );

    expect(draft, isNotNull);
    expect(
      draft!.entries.map((entry) => entry.text),
      isNot(
        contains(
          'Git branch fix/mobile-hide-desktop-settings was created for the settings UI changes.',
        ),
      ),
    );
    expect(
      draft.entries.map((entry) => entry.text),
      contains('User is working on mobile settings visibility.'),
    );
  });

  test('parseDraft guards unexecuted command execution claims', () {
    final inputContext = MemoryExtractionDraftService.buildInput(
      [
        Message(
          id: 'user-1',
          content: 'Run the release dry run.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 7, 9),
        ),
        Message(
          id: 'assistant-1',
          content: 'I will run the dry-run release script now.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 7, 9, 1),
        ),
      ],
      UserMemoryProfile(
        persona: const [],
        preferences: const [],
        doNot: const [],
        updatedAt: DateTime(2026, 6, 7, 9),
      ),
      toolResults: [
        ToolResultInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: const {'reason': 'Missing command execution'},
          result: jsonEncode({
            'ok': false,
            'code': 'unexecuted_command_action',
            'error': 'The requested command was not executed.',
          }),
        ),
      ],
    );
    const raw = '''
{
  "summary":"Release dry run was executed successfully.",
  "open_loops":[],
  "profile":{
    "persona":[],
    "preferences":[],
    "do_not":[]
  },
  "memories":[
    {
      "text":"Release dry run was executed successfully.",
      "type":"fact",
      "confidence":0.95,
      "importance":0.8,
      "ttl_days":30
    },
    {
      "text":"Release entry point script is tool/release_ios_macos.sh.",
      "type":"fact",
      "confidence":0.95,
      "importance":0.7,
      "ttl_days":30
    }
  ]
}
''';

    final draft = MemoryExtractionDraftService.parseDraft(
      raw,
      inputContext: inputContext,
    );

    expect(draft, isNotNull);
    expect(
      draft!.summary,
      'Latest requested command execution remains unexecuted.',
    );
    expect(
      draft.openLoops.first,
      'Execute the requested command with a command-execution tool.',
    );
    expect(draft.entries, hasLength(1));
    expect(
      draft.entries.single.text,
      'Release entry point script is tool/release_ios_macos.sh.',
    );
  });

  test('parseDraft guards partial release failure completion claims', () {
    final inputContext = MemoryExtractionDraftService.buildInput(
      [
        Message(
          id: 'user-1',
          content: 'Release iOS and macOS.',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 9, 20),
        ),
        Message(
          id: 'assistant-1',
          content:
              'macOS succeeded, but iOS failed because build number 17 already exists.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 9, 20, 21),
        ),
      ],
      UserMemoryProfile(
        persona: const [],
        preferences: const [],
        doNot: const [],
        updatedAt: DateTime(2026, 6, 9, 20),
      ),
      toolResults: [
        ToolResultInfo(
          id: 'tool-1',
          name: 'process_wait',
          arguments: const {'job_id': 'proc_release_1'},
          result: jsonEncode({
            'ok': true,
            'status': 'exited',
            'exit_code': 0,
            'stderr_tail':
                'Encountered error while creating the IPA: error: exportArchive The bundle version must be higher than the previously uploaded version: 17.',
            'stdout_tail': 'macOS Sparkle release uploaded successfully.',
          }),
        ),
      ],
    );
    const raw = '''
{
  "summary":"Completed iOS and macOS release for Caverno v1.3.5+17.",
  "open_loops":[],
  "profile":{
    "persona":[],
    "preferences":[],
    "do_not":[]
  },
  "memories":[
    {
      "text":"Release script completed successfully for iOS and macOS.",
      "type":"fact",
      "confidence":1.0,
      "importance":0.9,
      "ttl_days":30
    },
    {
      "text":"Release procedure is documented in docs/ios_macos_release.md.",
      "type":"fact",
      "confidence":1.0,
      "importance":0.8,
      "ttl_days":90
    }
  ]
}
''';

    final draft = MemoryExtractionDraftService.parseDraft(
      raw,
      inputContext: inputContext,
    );

    expect(draft, isNotNull);
    expect(draft!.summary, 'Latest release attempt had a partial failure.');
    expect(
      draft.openLoops.first,
      'Resolve the failed release lane before recording the release as complete.',
    );
    expect(draft.entries, hasLength(1));
    expect(
      draft.entries.single.text,
      'Release procedure is documented in docs/ios_macos_release.md.',
    );
  });

  test('parseDraft recovers JSON from reasoning text with other objects', () {
    const raw = '''
<think>
The schema shape is {"not_memory":"example"}.

```json
{
  "summary":"User prefers concise English summaries.",
  "open_loops":[],
  "profile":{
    "persona":[],
    "preferences":["Concise English summaries"],
    "do_not":[]
  },
  "memories":[
    {"text":"The user bought a model canary notebook for 1200 yen on 2026-05-22.","type":"fact","confidence":0.9,"importance":0.8,"ttl_days":null}
  ]
}
```
</think>
''';

    final draft = MemoryExtractionDraftService.parseDraft(raw);

    expect(draft, isNotNull);
    expect(draft!.summary, 'User prefers concise English summaries.');
    expect(draft.preferences, ['Concise English summaries']);
    expect(draft.entries.single.text, contains('1200 yen'));
  });

  test('parseDraft recovers structured reasoning when JSON is truncated', () {
    const raw = '''
<think>
*   Summary: User prefers concise English summaries and purchased a model canary notebook for 1200 yen on 2026-05-22.
*   Open Loops: None.
*   Profile:
    *   Persona: []
    *   Preferences: ["concise English summaries"]
    *   Do Not: []
*   Memories:
    1. Text: "Prefers concise English summaries." | Type: "preference" | Confidence: 1.0 | Importance: 0.8 | TTL: null
    2. Text: "Bought a model canary notebook for 1200 yen on 2026-05-22." | Type: "fact" | Confidence: 1.0 | Importance: 0.9 | TTL: null

Final JSON Structure Check:
`{"summary":"User prefers concise English summaries","open_loops":[],"profile":{"persona":[],"preferences":["concise English summaries"],"do_not":[]},"memories":[{"text":"Prefers concise English summaries.","type":"preference","confidence":1.</think>
''';

    final repairMessages = <String>[];
    final draft = MemoryExtractionDraftService.parseDraft(
      raw,
      onRepair: repairMessages.add,
    );

    expect(draft, isNotNull);
    expect(draft!.summary, contains('concise English summaries'));
    expect(draft.preferences, ['concise English summaries']);
    expect(draft.entries, hasLength(2));
    expect(draft.entries.first.type, 'preference');
    expect(draft.entries.last.text, contains('1200 yen'));
    expect(draft.entries.last.importance, 0.9);
    expect(
      repairMessages,
      contains('Recovered memory extraction from structured reasoning text'),
    );
  });

  test('parseDraft drops saved artifact path memories from reasoning', () {
    const raw = '''
<think>
*   Summary: Saved a generated Markdown browser summary.
*   Open Loops: None.
*   Profile:
    *   Persona: []
    *   Preferences: ["concise English summaries"]
    *   Do Not: []
*   Memories:
    1. Text: "Saved Hydrangea Wikipedia summary to /Users/example/Library/Application Support/com.noguwo.apps.caverno/browser-saves/hydrangea_summary.md." | Type: "fact" | Confidence: 1.0 | Importance: 0.8 | TTL: 30
    2. Text: "Prefers concise English summaries." | Type: "preference" | Confidence: 0.9 | Importance: 0.8 | TTL: null
</think>
''';

    final draft = MemoryExtractionDraftService.parseDraft(raw);

    expect(draft, isNotNull);
    expect(draft!.entries, hasLength(1));
    expect(draft.entries.single.text, 'Prefers concise English summaries');
  });
}
