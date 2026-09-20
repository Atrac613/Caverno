import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/composer_shortcut_suggestion_service.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conversation({List<Message> messages = const []}) {
  final now = DateTime(2026, 8, 17);
  return Conversation(
    id: 'thread-1',
    title: 'Composer shortcuts',
    messages: messages,
    createdAt: now,
    updatedAt: now,
  );
}

Message _userMessage(String content) => Message(
  id: 'user-1',
  role: MessageRole.user,
  content: content,
  timestamp: DateTime(2026, 8, 17),
);

void main() {
  test('parses shortcuts from fenced JSON and maps kinds', () {
    final shortcuts = ComposerShortcutSuggestionService.parse('''
```json
{"shortcuts":[
  {"kind":"git","label":"Commit","prompt":"Commit the composer shortcut changes."},
  {"kind":"verify","label":"Run tests","prompt":"Run flutter test and report failures."},
  {"kind":"follow_up","label":"Explain","prompt":"Explain how the chip row is wired."}
]}
```
''');

    expect(shortcuts, hasLength(3));
    expect(shortcuts[0].kind, ComposerShortcutKind.git);
    expect(shortcuts[0].label, 'Commit');
    expect(shortcuts[0].prompt, 'Commit the composer shortcut changes.');
    expect(shortcuts[1].kind, ComposerShortcutKind.verify);
    expect(shortcuts[2].kind, ComposerShortcutKind.followUp);
  });

  test('unknown or missing kinds fall back to a follow-up shortcut', () {
    final shortcuts = ComposerShortcutSuggestionService.parse(
      '{"shortcuts":[{"kind":"whatever","label":"Continue","prompt":"Keep going."},'
      '{"label":"Summarize","prompt":"Summarize the change."}]}',
    );

    expect(shortcuts, hasLength(2));
    expect(
      shortcuts.every(
        (shortcut) => shortcut.kind == ComposerShortcutKind.followUp,
      ),
      isTrue,
    );
  });

  test('returns an empty list for unusable responses', () {
    expect(ComposerShortcutSuggestionService.parse('not json at all'), isEmpty);
    expect(
      ComposerShortcutSuggestionService.parse('{"shortcuts":"nope"}'),
      isEmpty,
    );
    expect(
      ComposerShortcutSuggestionService.parse('{"shortcuts":[]}'),
      isEmpty,
    );
    expect(
      ComposerShortcutSuggestionService.parse(
        '{"shortcuts":[{"label":"","prompt":"Do it."},{"label":"No prompt","prompt":"  "}]}',
      ),
      isEmpty,
    );
  });

  test('clamps over-long labels and prompts', () {
    final shortcuts = ComposerShortcutSuggestionService.parse(
      '{"shortcuts":[{"kind":"git","label":"${'L' * 60}","prompt":"${'P' * 400}"}]}',
    );

    expect(shortcuts, hasLength(1));
    expect(
      shortcuts.single.label.length,
      ComposerShortcutSuggestionService.maxLabelLength,
    );
    expect(
      shortcuts.single.prompt.length,
      ComposerShortcutSuggestionService.maxPromptLength,
    );
    expect(shortcuts.single.label, endsWith('...'));
  });

  test('collapses whitespace and de-duplicates labels case-insensitively', () {
    final shortcuts = ComposerShortcutSuggestionService.parse(
      '{"shortcuts":[{"kind":"git","label":"Commit\\n now","prompt":"Commit  the\\nchanges."},'
      '{"kind":"git","label":"commit NOW","prompt":"Commit again."}]}',
    );

    expect(shortcuts, hasLength(1));
    expect(shortcuts.single.label, 'Commit now');
    expect(shortcuts.single.prompt, 'Commit the changes.');
  });

  test('caps the shortcut count', () {
    final entries = List.generate(
      8,
      (index) =>
          '{"kind":"follow_up","label":"Step $index","prompt":"Do step $index."}',
    ).join(',');

    expect(
      ComposerShortcutSuggestionService.parse('{"shortcuts":[$entries]}'),
      hasLength(ComposerShortcutSuggestionService.maxShortcuts),
    );
  });

  test('drops destructive prompts', () {
    final shortcuts = ComposerShortcutSuggestionService.parse(
      '{"shortcuts":['
      '{"kind":"git","label":"Force push","prompt":"Run git push --force to the remote."},'
      '{"kind":"git","label":"Reset","prompt":"Run git reset --hard HEAD~1."},'
      '{"kind":"git","label":"Wipe","prompt":"Run rm -rf build to start clean."},'
      '{"kind":"git","label":"Commit","prompt":"Commit the staged changes."}]}',
    );

    expect(shortcuts, hasLength(1));
    expect(shortcuts.single.label, 'Commit');
  });

  test('keeps release and deploy prompts', () {
    // These were dropped until 2026-09-20. Running one is gated by tool
    // approval, and a release needs its own issued token, so the button could
    // never release unattended -- while the ban removed the most useful
    // shortcut at the moment a release thread pauses to ask whether to go on.
    final shortcuts = ComposerShortcutSuggestionService.parse(
      '{"shortcuts":['
      '{"kind":"follow_up","label":"リリースを実行","prompt":"実際のリリース実行に進んでください。"},'
      '{"kind":"follow_up","label":"Release it","prompt":"Run the iOS and macOS release now."},'
      '{"kind":"follow_up","label":"Release notes","prompt":"Write the release notes for this version."},'
      '{"kind":"git","label":"Deploy","prompt":"Deploy the build to production."}]}',
    );

    expect(
      shortcuts.map((shortcut) => shortcut.label),
      ['リリースを実行', 'Release it', 'Release notes', 'Deploy'],
    );
  });

  test('the prompt keeps follow_up available when git and verify are gated', () {
    // A finished release leaves a clean tree and no code change, closing git
    // and verify at once. Without this guarantee the model answered
    // {"shortcuts":[]} -- 29 of 45 drafts came back empty.
    const prompt = ComposerShortcutSuggestionService.systemPrompt;

    expect(prompt, contains('never restrict "follow_up"'));
    expect(prompt, contains('always available'));
    expect(
      prompt,
      contains('ends by asking the user something'),
      reason: 'the answer to a trailing question is the obvious first chip',
    );
    expect(
      prompt,
      isNot(contains('deploying and releasing')),
      reason: 'the release ban was lifted; see keeps release and deploy prompts',
    );
  });

  test('hasUsefulContext requires an assistant answer and a user message', () {
    final withUser = _conversation(messages: [_userMessage('Add the chips.')]);

    expect(
      ComposerShortcutSuggestionService.hasUsefulContext(
        conversation: withUser,
        assistantContent: 'Added the chip row above the composer.',
      ),
      isTrue,
    );
    expect(
      ComposerShortcutSuggestionService.hasUsefulContext(
        conversation: withUser,
        assistantContent: '   ',
      ),
      isFalse,
    );
    expect(
      ComposerShortcutSuggestionService.hasUsefulContext(
        conversation: _conversation(),
        assistantContent: 'Done.',
      ),
      isFalse,
    );
  });

  test('buildMessages carries language, repo state and the last request', () {
    final messages = ComposerShortcutSuggestionService.buildMessages(
      conversation: _conversation(
        messages: [_userMessage('Add the shortcut chips.')],
      ),
      assistantContent: 'Added composer_shortcut_bar.dart and wired it up.',
      languageCode: 'ja',
      isCodingWorkspace: true,
      repoSnapshot: const ComposerShortcutRepoSnapshot(
        branchName: 'claude/chat-composer-shortcut-buttons',
        changedFileCount: 7,
        insertions: 214,
        deletions: 11,
      ),
      now: DateTime(2026, 8, 17),
    );

    expect(messages, hasLength(2));
    expect(messages.first.role, MessageRole.system);
    expect(
      messages.first.content,
      ComposerShortcutSuggestionService.systemPrompt,
    );

    final input = messages.last.content;
    expect(input, contains('language code: ja'));
    expect(input, contains('coding'));
    expect(input, contains('claude/chat-composer-shortcut-buttons'));
    expect(input, contains('uncommitted files: 7'));
    expect(input, contains('+214 -11'));
    expect(input, contains('Add the shortcut chips.'));
    expect(input, contains('Added composer_shortcut_bar.dart'));
  });

  test('buildMessages tells the model to skip git without repo state', () {
    final messages = ComposerShortcutSuggestionService.buildMessages(
      conversation: _conversation(messages: [_userMessage('Explain this.')]),
      assistantContent: 'Here is the explanation.',
      languageCode: 'en',
    );

    expect(messages.last.content, contains('Repository state: unavailable'));
  });

  group('shouldSuggestAfterTurn', () {
    Message assistant({
      String id = 'assistant-1',
      String content = 'Edited the composer.',
      bool isStreaming = false,
    }) => Message(
      id: id,
      role: MessageRole.assistant,
      content: content,
      timestamp: DateTime(2026, 8, 17),
      isStreaming: isStreaming,
    );

    test('fires once on the loading -> idle edge', () {
      expect(
        ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
          wasLoading: true,
          isLoading: false,
          lastMessage: assistant(),
        ),
        isTrue,
      );
      expect(
        ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
          wasLoading: true,
          isLoading: false,
          lastMessage: assistant(),
          lastSuggestedMessageId: 'assistant-1',
        ),
        isFalse,
      );
    });

    test('ignores non-edges, running turns and unfinished answers', () {
      expect(
        ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
          wasLoading: false,
          isLoading: false,
          lastMessage: assistant(),
        ),
        isFalse,
      );
      expect(
        ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
          wasLoading: true,
          isLoading: true,
          lastMessage: assistant(),
        ),
        isFalse,
      );
      expect(
        ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
          wasLoading: true,
          isLoading: false,
          lastMessage: assistant(isStreaming: true),
        ),
        isFalse,
      );
      expect(
        ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
          wasLoading: true,
          isLoading: false,
          lastMessage: assistant(content: '   '),
        ),
        isFalse,
      );
      expect(
        ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
          wasLoading: true,
          isLoading: false,
          lastMessage: _userMessage('Do it again.'),
        ),
        isFalse,
      );
      expect(
        ComposerShortcutSuggestionService.shouldSuggestAfterTurn(
          wasLoading: true,
          isLoading: false,
          lastMessage: null,
        ),
        isFalse,
      );
    });
  });
}
