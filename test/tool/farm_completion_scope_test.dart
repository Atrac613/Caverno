import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/canaries/support/farm_completion_fixture.dart';
import '../../tool/canaries/support/farm_completion_tools.dart';

void main() {
  FarmCompletionScope scope() => FarmCompletionScope(
    FarmCompletionFixture(
      Directory('/private/tmp/farm-scope'),
      FarmCompletionScenario.normal,
    ),
  );
  test('file effects stay within the two named fixture paths', () {
    final value = scope();
    expect(value.canWrite('/private/tmp/farm-scope/fixture.py'), isTrue);
    expect(value.canWrite('/private/tmp/farm-scope/tool/verify.py'), isFalse);
    expect(value.canWrite('/private/tmp/farm-scope/../fixture.py'), isFalse);
    expect(value.canWrite('/private/tmp/outside/fixture.py'), isFalse);
  });
  test('roadmap mutation is admitted only after clean review', () {
    final value = scope();
    expect(value.canWrite('/private/tmp/farm-scope/roadmap.md'), isFalse);
    value.stage = 'prepare';
    expect(value.canWrite('/private/tmp/farm-scope/roadmap.md'), isTrue);
    expect(value.canWrite('/private/tmp/farm-scope/fixture.py'), isFalse);
  });
  test('review refuses file effects but permits bounded Git inspection', () {
    final value = scope()..stage = 'review';
    expect(value.canWrite('/private/tmp/farm-scope/fixture.py'), isFalse);
    expect(
      value.canGit('diff -- fixture.py roadmap.md', value.fixture.root.path),
      isTrue,
    );
    expect(
      value.canGit('add -- fixture.py roadmap.md', value.fixture.root.path),
      isFalse,
    );
  });
  test(
    'diff admits task paths while rejecting external paths and writable options',
    () {
      final value = scope()..stage = 'review';
      for (final command in [
        'diff -- fixture.py',
        'diff HEAD -- /private/tmp/farm-scope/fixture.py',
      ]) {
        expect(value.canGit(command, value.fixture.root.path), isTrue);
      }
      for (final command in [
        'diff -- /private/tmp/outside.txt',
        'diff -- ../../outside.txt',
        'diff --output=/private/tmp/output.txt',
        'diff --no-index fixture.py /private/tmp/outside.txt',
      ]) {
        expect(value.canGit(command, value.fixture.root.path), isFalse);
      }
    },
  );
  test('history inspection remains bounded', () {
    final value = scope()..stage = 'commit';
    expect(value.canGit('log --oneline -3', value.fixture.root.path), isTrue);
    expect(value.canGit('log --oneline', value.fixture.root.path), isFalse);
    expect(
      value.canGit('log --oneline -100', value.fixture.root.path),
      isFalse,
    );
  });
  test(
    'Git refuses other roots, operators, broad staging and global options',
    () {
      final value = scope()..stage = 'commit';
      for (final command in [
        'status && touch outside',
        'add .',
        'add -- unrelated.txt',
        '-C /private/tmp/outside status',
        'config --global user.name changed',
        'push',
        'reset --hard',
        'commit --amend -m "fix: clamp"',
      ]) {
        expect(
          value.canGit(command, value.fixture.root.path),
          isFalse,
          reason: command,
        );
      }
      expect(value.canGit('status', '/private/tmp/outside'), isFalse);
    },
  );
  test('permits task-only restaging while rejecting other files', () {
    final value = scope()..stage = 'commit';
    for (final command in [
      'add -- fixture.py',
      'add -- roadmap.md',
      'add -- /private/tmp/farm-scope/roadmap.md',
      'add -- roadmap.md fixture.py',
    ]) {
      expect(value.canGit(command, value.fixture.root.path), isTrue);
    }
    for (final command in [
      'add -- unrelated.txt fixture.py',
      'add -- tool/verify.py roadmap.md',
      'add -- /private/tmp/outside/roadmap.md',
    ]) {
      expect(value.canGit(command, value.fixture.root.path), isFalse);
    }
  });
  test('commit requires separate subject and body without other flags', () {
    final value = scope()..stage = 'commit';
    expect(
      value.canGit(
        'commit -m "fix: clamp fixture values" -m "Constrain values to the roadmap interval."',
        value.fixture.root.path,
      ),
      isTrue,
    );
    expect(
      value.canGit(
        'commit -m "feat(fixture): clamp values to inclusive [0, 10]" -m "Constrain clamp() to [0, 10], including negative inputs."',
        value.fixture.root.path,
      ),
      isTrue,
    );
    for (final command in [
      'commit -m "Unconventional subject" -m "Body"',
      'commit -m "fix: ${'x' * 70}" -m "Body"',
      'commit -m "fix: clamp" -m ""',
      'commit -m "fix: clamp" -m "Body" --amend',
    ]) {
      expect(value.canGit(command, value.fixture.root.path), isFalse);
    }
    value.stage = 'prepare';
    expect(
      value.canGit('commit -m "fix: clamp" -m "Body"', value.fixture.root.path),
      isFalse,
    );
    value.stage = 'commit';
    expect(
      value.canGit(
        'commit -m "fix: clamp fixture values"',
        value.fixture.root.path,
      ),
      isFalse,
    );
  });
}
