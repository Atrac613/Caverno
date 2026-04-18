import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/memory_extraction_json_parser.dart';

void main() {
  test('parses valid memory extraction JSON without repair', () {
    const raw = '''
{
  "summary":"User prefers concise summaries.",
  "open_loops":[],
  "profile":{"persona":[],"preferences":["Concise"],"do_not":[]},
  "memories":[
    {"text":"The user prefers concise summaries.","type":"preference","confidence":0.9,"importance":0.8,"ttl_days":null}
  ]
}
''';

    final result = MemoryExtractionJsonParser.parse(raw);

    expect(result, isNotNull);
    expect(result!.wasRepaired, isFalse);
    expect(result.decoded['summary'], 'User prefers concise summaries.');
  });

  test('repairs missing key quotes inside memory entries', () {
    const raw = '''
{"summary":"Prefers concise review notes.","open_loops":[],"profile":{"persona":[],"preferences":[],"do_not":[]},"memories":[{"text":"The user prefers concise release notes.","type":"fact","confidence:1.0,"importance":0.8,"ttl_days":null}]}
''';

    final result = MemoryExtractionJsonParser.parse(raw);

    expect(result, isNotNull);
    expect(result!.wasRepaired, isTrue);
    final memories = result.decoded['memories'] as List<dynamic>;
    final firstMemory = memories.first as Map<String, dynamic>;
    expect(firstMemory['confidence'], 1.0);
    expect(firstMemory['importance'], 0.8);
  });

  test('repairs unquoted keys and trailing commas', () {
    const raw = '''
```json
{
  "summary": "Tracks blocker state",
  open_loops: ["Waiting on CI",],
  "profile": {"persona": [], "preferences": [], "do_not": [],},
  "memories": [
    {"text":"CI blocker is unresolved","type":"topic","confidence":0.7,"importance":0.6,"ttl_days":14,},
  ],
}
```
''';

    final result = MemoryExtractionJsonParser.parse(raw);

    expect(result, isNotNull);
    expect(result!.wasRepaired, isTrue);
    expect(result.decoded['open_loops'], ['Waiting on CI']);
    final memories = result.decoded['memories'] as List<dynamic>;
    expect(memories, hasLength(1));
  });
}
