import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One constructor for the main loop's assistant messages.
///
/// This gate exists because of a defect it would have caught. `Message` gained
/// `isAnabasisParent` so the transcript could say when Anabasis answered, and
/// it was set on one of three identical literals — the hidden-prompt path. The
/// ordinary send and the post-tool continuation kept the plain shape, so the
/// reply a user actually reads carried no marker and `@anabasis` looked like
/// any other turn.
///
/// A source scan rather than a behavioural test because the failure is a
/// literal appearing somewhere new, and a behavioural test would have to
/// exercise every path that creates one to notice.
void main() {
  const notifierPath =
      'lib/features/chat/presentation/providers/chat_notifier.dart';

  test('the main loop builds assistant messages in one place', () {
    final source = File(notifierPath).readAsStringSync();
    final literals = RegExp(
      r'role:\s*MessageRole\.assistant,',
    ).allMatches(source).length;

    expect(
      literals,
      1,
      reason:
          'Only _newAssistantMessage may name MessageRole.assistant in $notifierPath. '
          'A second literal is a message that will miss every field the '
          'helper sets — today isAnabasisParent, tomorrow whatever else a turn '
          'has to stamp on its own reply.',
    );
    expect(
      source,
      contains('Message _newAssistantMessage(int generation)'),
      reason: 'The helper is what the count above is counting.',
    );
  });
}
