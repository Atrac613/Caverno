import 'package:caverno/features/chat/domain/services/skills/loaded_skill_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the most recently loaded skill is the one carried', () {
    final memory = LoadedSkillMemory()
      ..record(conversationId: 'thread', skillRef: 'first')
      ..record(conversationId: 'thread', skillRef: 'second');

    expect(memory.carriedRefFor('thread'), 'second');
    expect(memory.loadedRefsFor('thread'), {'first', 'second'});
  });

  test('reloading moves a skill to the front instead of duplicating it', () {
    final memory = LoadedSkillMemory()
      ..record(conversationId: 'thread', skillRef: 'a')
      ..record(conversationId: 'thread', skillRef: 'b')
      ..record(conversationId: 'thread', skillRef: 'a');

    expect(memory.carriedRefFor('thread'), 'a');
    expect(memory.loadedRefsFor('thread'), {'a', 'b'});
  });

  test('threads do not see each other', () {
    // Keyed by conversation because the span that matters is the task, and two
    // threads working from different skills must not swap them.
    final memory = LoadedSkillMemory()
      ..record(conversationId: 'one', skillRef: 'release')
      ..record(conversationId: 'two', skillRef: 'review');

    expect(memory.carriedRefFor('one'), 'release');
    expect(memory.carriedRefFor('two'), 'review');
  });

  test('a thread that loaded nothing carries nothing', () {
    final memory = LoadedSkillMemory();

    expect(memory.carriedRefFor('thread'), isNull);
    expect(memory.loadedRefsFor('thread'), isEmpty);
  });

  test('empty references are not recorded', () {
    // A load_skill call carrying neither id nor name would otherwise make the
    // index try to carry a skill that cannot be found.
    final memory = LoadedSkillMemory()
      ..record(conversationId: 'thread', skillRef: '   ')
      ..record(conversationId: '', skillRef: 'release');

    expect(memory.carriedRefFor('thread'), isNull);
    expect(memory.carriedRefFor(''), isNull);
  });

  test('forgetting a thread clears it', () {
    final memory = LoadedSkillMemory()
      ..record(conversationId: 'thread', skillRef: 'release')
      ..forget('thread');

    expect(memory.carriedRefFor('thread'), isNull);
  });
}
