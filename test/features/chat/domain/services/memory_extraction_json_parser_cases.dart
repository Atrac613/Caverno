part of 'chat_domain_services_test.dart';

void _runMemoryExtractionJsonParser() {
  test('closes only a missing root brace with complete extraction values', () {
    final document = {
      'summary': 'Prepared the fixture for review.',
      'open_loops': ['Commit remains pending.'],
      'profile': {'persona': [], 'preferences': [], 'do_not': []},
      'memories': [
        {'text': r'Keep "quotes", {braces}, and C:\work intact.'},
      ],
    };
    final encoded = jsonEncode(document);
    final incomplete = encoded.substring(0, encoded.length - 1);
    for (final raw in [incomplete, '```json\n$incomplete\n```']) {
      final result = MemoryExtractionJsonParser.parse(raw)!;
      expect(result.wasRepaired, isTrue);
      expect(result.decoded, document);
    }
    expect(MemoryExtractionJsonParser.parse(encoded)!.wasRepaired, isFalse);
  });

  test('root repair never supplies missing sections or nested values', () {
    for (final raw in [
      '{"summary":"Incomplete',
      '{"summary":"Incomplete\\',
      '{"summary":"Incomplete","open_loops":[],"profile":{},"memories":[',
      '{"summary":"Incomplete","open_loops":[],"profile":{},"memories":[{}',
      '{"summary":"Incomplete","open_loops":[],"profile":{},"memories":',
      '{"summary":"Incomplete","open_loops":[],"profile":{},',
      '{"summary":"Incomplete","open_loops":[],"profile":{}',
      '{"summary":"Incomplete","open_loops":[],"profile":{},"memories":null',
    ]) {
      final result = MemoryExtractionJsonParser.parse(raw);
      expect(result?.wasRepaired, isNot(true), reason: raw);
    }
  });

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
