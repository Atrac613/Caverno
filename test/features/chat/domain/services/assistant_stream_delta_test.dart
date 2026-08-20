import 'package:caverno/features/chat/domain/services/assistant_stream_delta.dart';
import 'package:test/test.dart';

void main() {
  const delta = AssistantStreamDelta();

  test('an offset inside a think block does not leak the reasoning', () {
    // Session ae491799: the offset is a raw character index taken from
    // whichever message was last, so it can land inside the tag. Slicing first
    // removed `<think>` and left bare deliberation, which the
    // unexecuted-command guard then read as a claim.
    const content =
        '<think>The user is asking about Opus 4.8. It was released on '
        '2026-05-28.</think>'
        'Opus 4.8 は 2026年5月28日にリリースされたモデルです。';

    final result = delta.since(content: content, startingLength: 7);

    expect(result, isNot(contains('released')));
    expect(result, isNot(contains('The user is asking')));
    expect(result, contains('リリースされたモデル'));
  });

  test('a whole fresh message yields only its visible answer', () {
    const content = '<think>weighing options</think>Done.';

    expect(delta.since(content: content, startingLength: 0), 'Done.');
  });

  test('only what this segment added is returned', () {
    const content = 'First part. Second part.';

    expect(
      delta.since(content: content, startingLength: 'First part. '.length),
      'Second part.',
    );
  });

  test('nothing new yields nothing', () {
    const content = 'All of it.';

    expect(delta.since(content: content, startingLength: content.length), '');
    expect(delta.since(content: content, startingLength: 999), '');
  });

  test('an offset past the visible text falls back to the whole answer', () {
    // The prefix stops being a prefix of the visible text once tags are gone;
    // judging the whole visible answer is the safe reading.
    const content = '<think>a</think>Answer.';

    expect(delta.since(content: content, startingLength: 12), 'Answer.');
  });
}
