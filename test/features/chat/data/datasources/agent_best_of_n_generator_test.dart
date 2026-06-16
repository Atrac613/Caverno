import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/agent_best_of_n_generator.dart';
import 'package:caverno/features/chat/data/datasources/best_of_n_runner.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

void main() {
  test('runs an attempt and reports git-changed paths and a summary', () async {
    List<Message>? seenMessages;
    final generator = AgentBestOfNGenerator(
      goal: 'Fix the failing parser test',
      candidateCount: 3,
      runAttempt: (messages) async {
        seenMessages = messages;
        return 'Done. Updated the tokenizer.\nMore detail here.';
      },
      changedPaths: () async => ['lib/parser.dart', 'test/parser_test.dart'],
    );

    final generation = await generator.generate(0);

    expect(generation.changedPaths, [
      'lib/parser.dart',
      'test/parser_test.dart',
    ]);
    expect(generation.summary, contains('2 file(s) changed'));
    expect(generation.summary, contains('Updated the tokenizer'));

    // Prompt carries the goal and a per-candidate diversity nudge.
    expect(seenMessages, isNotNull);
    expect(seenMessages!.first.role, MessageRole.system);
    final user = seenMessages!.last;
    expect(user.role, MessageRole.user);
    expect(user.content, contains('Fix the failing parser test'));
    expect(user.content, contains('attempt 1 of 3'));
  });

  test('omits the diversity nudge for a single candidate', () async {
    List<Message>? seenMessages;
    final generator = AgentBestOfNGenerator(
      goal: 'Add a null check',
      candidateCount: 1,
      runAttempt: (messages) async {
        seenMessages = messages;
        return 'changed';
      },
      changedPaths: () async => const ['lib/x.dart'],
    );

    await generator.generate(0);
    expect(seenMessages!.last.content, 'Add a null check');
  });

  test('summarizes a no-change attempt', () async {
    final generator = AgentBestOfNGenerator(
      goal: 'g',
      candidateCount: 1,
      runAttempt: (messages) async => '',
      changedPaths: () async => const [],
    );
    final generation = await generator.generate(0);
    expect(generation.summary, '0 file(s) changed');
    expect(generation.changedPaths, isEmpty);
  });

  test('the step plugs into BestOfNGeneration consumers', () async {
    final generator = AgentBestOfNGenerator(
      goal: 'g',
      candidateCount: 2,
      runAttempt: (messages) async => 'ok',
      changedPaths: () async => const ['lib/a.dart'],
    );
    final BestOfNGenerationStep step = generator.step;
    final generation = await step(1);
    expect(generation, isA<BestOfNGeneration>());
    expect(generation.changedPaths, ['lib/a.dart']);
  });
}
