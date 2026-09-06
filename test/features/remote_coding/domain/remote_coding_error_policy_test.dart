import 'dart:io';

import 'package:caverno/features/remote_coding/domain/remote_coding_error_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteCodingErrorPolicy', () {
    test('a declined command leaves the session alone', () {
      // The page renders the pairing view whenever isConnected is false, so
      // treating one of these as a disconnection replaced the thread list --
      // and the button that creates a thread -- with a screen asking the user
      // to pair again, over a socket that was still open.
      for (final code in const [
        'project_not_found',
        'conversation_not_found',
        'approval_not_found',
        'question_not_found',
        'empty_message',
        'invalid_message',
        'unsupported_command',
        'relay_unavailable',
        'relay_delegation_expired',
        'relay_delegation_invalid',
        'relay_challenge_rejected',
        'relay_provisioning_failed',
      ]) {
        expect(
          RemoteCodingErrorPolicy.endsTheSession(code),
          isFalse,
          reason: '$code is the desktop declining one command',
        );
        expect(RemoteCodingErrorPolicy.isDeclinedCommand(code), isTrue);
      }
    });

    test('pairing failure does end it', () {
      // Answered before a session exists, so the connection view is where the
      // user retries from.
      expect(RemoteCodingErrorPolicy.endsTheSession('pairing_failed'), isTrue);
      expect(
        RemoteCodingErrorPolicy.isDeclinedCommand('pairing_failed'),
        isFalse,
      );
    });

    test('unauthorized is neither, because it is handled before both', () {
      // It voids the saved credential as well as the session, which is more
      // than this policy decides.
      expect(
        RemoteCodingErrorPolicy.isDeclinedCommand('unauthorized'),
        isFalse,
      );
    });

    test('an unknown code is reported rather than acted on', () {
      // A newer desktop's code should not log this one out. Showing a message
      // is the recoverable reading of something this build cannot classify.
      expect(
        RemoteCodingErrorPolicy.endsTheSession('some_future_code'),
        isFalse,
      );
    });

    test('every code the desktop can send is classified', () {
      // The policy is a predicate over strings and the server emits string
      // literals, so nothing makes the two agree. Reading the server's own
      // source does: a code added there without a decision here fails.
      final server = File(
        'lib/features/remote_coding/presentation/remote_coding_server_notifier.dart',
      ).readAsStringSync();
      final codes = RegExp(
        r"code: '([a-z_]+)'",
      ).allMatches(server).map((match) => match.group(1)!).toSet();

      expect(
        codes,
        contains('project_not_found'),
        reason: 'the extraction itself has to be working',
      );
      for (final code in codes) {
        final classified =
            code == RemoteCodingErrorPolicy.unauthorized ||
            RemoteCodingErrorPolicy.endsTheSession(code) ||
            RemoteCodingErrorPolicy.isDeclinedCommand(code);
        expect(classified, isTrue, reason: '$code has no decision');
      }
    });
  });
}
