import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Layout claims about the watch transcript that only a device can disprove.
///
/// Source checks, because the watch app is a native SwiftUI target with no test
/// host in this repository's `flutter test` run. Each one encodes a defect a
/// real wrist session found and no other test could have caught.

/// watchOS renders one toolbar item per placement.
///
/// `TranscriptView` declared four `ToolbarItem`s at `.topBarTrailing`: the
/// approval, question, and goal indicators -- carefully ranked against each
/// other -- and the thread picker, which was not part of that ranking. The
/// picker appears whenever the phone has more than one thread, which is the
/// ordinary case, and it took the slot. The result was a watch drawing a frame
/// whose status was `waitingApproval`, with nothing on screen to reach it: a
/// blocked turn, invisible on the wrist, for as long as the user had two
/// threads. Only a device session found it -- the wire contract, the Dart
/// projection, and the Swift decode were all correct.
///
/// This is a source check because the watch app is a native SwiftUI target with
/// no test host in this repository's `flutter test` run. It is cheap and it
/// covers the exact mistake: a second claim on a single slot.
void main() {
  const path = 'ios/CavernoWatch Watch App/TranscriptView.swift';

  test('claims each watch toolbar placement at most once', () {
    final source = File(path).readAsStringSync();
    final placements = RegExp(
      r'ToolbarItem\(\s*placement:\s*\.(\w+)',
    ).allMatches(source).map((match) => match.group(1)!).toList();

    expect(
      placements,
      isNotEmpty,
      reason: 'the toolbar is what this test exists to constrain',
    );
    expect(
      placements.toSet(),
      hasLength(placements.length),
      reason:
          'watchOS shows one item per toolbar placement, so a second claim on '
          '$placements silently hides the other. Pin the extra affordance in '
          'the view body instead.',
    );
  });

  /// The compose bar is the only control the transcript offers.
  ///
  /// `.ignoresSafeArea(edges: .bottom)` on the screen's root stack pushed it
  /// past the bottom inset, and the watch's rounded display clipped the input
  /// capsule's lower edge. The scroll view sits above the bar and never reached
  /// that edge anyway, so the modifier bought nothing.
  test('keeps the compose bar inside the bottom safe area', () {
    final code = _withoutComments(File(path).readAsStringSync());

    expect(
      code,
      isNot(contains(RegExp(r'\.ignoresSafeArea\([^)]*\.bottom'))),
      reason:
          'the compose bar is the last thing in this screen\'s stack, so '
          'ignoring the bottom inset clips it against the display edge',
    );
  });

  test('keeps the blocked-turn affordance out of the toolbar', () {
    final source = File(path).readAsStringSync();
    final toolbar = _blockAfter(source, '.toolbar {');

    for (final destination in ['ApprovalView', 'QuestionView', 'GoalView']) {
      expect(
        toolbar,
        isNot(contains(destination)),
        reason:
            '$destination is how a blocked turn is answered on the wrist. In '
            'the toolbar it competes for the one trailing slot with the thread '
            'picker and loses.',
      );
      expect(
        source,
        contains(destination),
        reason: '$destination still has to be reachable from the transcript',
      );
    }
  });
}

/// The braced block introduced by [opening], so a check on the toolbar does not
/// also read the whole rest of the file.
String _blockAfter(String source, String opening) {
  final start = source.indexOf(opening);
  expect(start, isNot(-1), reason: 'missing $opening');
  var depth = 0;
  for (var i = start + opening.length - 1; i < source.length; i += 1) {
    if (source[i] == '{') depth += 1;
    if (source[i] == '}') {
      depth -= 1;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('unbalanced braces after $opening');
}

/// Drops `//` line comments, so a comment explaining why a modifier is absent
/// does not read as the modifier being present.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) {
      final comment = line.indexOf('//');
      return comment == -1 ? line : line.substring(0, comment);
    })
    .join('\n');
