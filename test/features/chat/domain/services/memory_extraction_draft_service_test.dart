import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';

void main() {
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
    );

    expect(input, contains('Current profile:'));
    expect(input, contains('Flutter developer'));
    expect(input, contains('- user: I prefer concise coding explanations.'));
    expect(input, contains('Output rules:'));
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
}
