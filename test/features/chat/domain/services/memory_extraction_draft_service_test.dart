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
    expect(input, contains('Treat search_past_conversations'));
    expect(input, contains('missing files'));
    expect(input, contains('unverified causes of interruptions'));
    expect(input, contains('stream_end completions'));
    expect(input, contains('validation markers'));
    expect(input, contains('current-turn tool-use instructions'));
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
}
