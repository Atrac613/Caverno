import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/command_payload_facts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tryParse', () {
    test('reads the facts a command payload reported', () {
      final facts = CommandPayloadFacts.tryParse(
        jsonEncode({
          'exit_code': 2,
          'stdout': 'built 3 targets',
          'stderr': 'missing dependency',
        }),
      );

      expect(facts?.exitCode, 2);
      expect(facts?.stdout, 'built 3 targets');
      expect(facts?.stderr, 'missing dependency');
      expect(facts?.explicitError, isNull);
    });

    test('yields nothing for payloads with no schema to read', () {
      // Third-party MCP output and plain text must not be guessed at.
      expect(CommandPayloadFacts.tryParse('Command finished.'), isNull);
      expect(CommandPayloadFacts.tryParse('[1, 2, 3]'), isNull);
      expect(CommandPayloadFacts.tryParse(''), isNull);
    });

    test('ignores an error field that carries no message', () {
      final facts = CommandPayloadFacts.tryParse(
        jsonEncode({'exit_code': 0, 'error': '   '}),
      );

      expect(facts?.explicitError, isNull);
    });
  });

  group('toOutcome', () {
    test('carries the exit status a completed command reported', () {
      final facts = CommandPayloadFacts.tryParse(
        jsonEncode({'exit_code': 1, 'stderr': 'failed'}),
      );

      expect(facts?.toOutcome()?.exitCode, 1);
      expect(facts?.toOutcome()?.hasFailingExitCode, isTrue);
    });

    test('reports no exit status when the command never reached one', () {
      // A payload with no exit_code, and one whose explicit error says the
      // command failed to run, must not surface an exit status: consumers
      // treat its presence as proof the process completed.
      expect(
        CommandPayloadFacts.tryParse(jsonEncode({'stdout': ''}))?.toOutcome(),
        isNull,
      );
      expect(
        CommandPayloadFacts.tryParse(
          jsonEncode({'exit_code': 1, 'error': 'Process failed to start.'}),
        )?.toOutcome(),
        isNull,
      );
    });

    test('carries a zero exit status as a fact in its own right', () {
      final facts = CommandPayloadFacts.tryParse(jsonEncode({'exit_code': 0}));

      expect(facts?.toOutcome()?.exitCode, 0);
      expect(facts?.toOutcome()?.hasSucceedingExitCode, isTrue);
    });
  });

  group('failureMessage', () {
    test('returns null when the command succeeded', () {
      final facts = CommandPayloadFacts.tryParse(
        jsonEncode({'exit_code': 0, 'stdout': 'ok'}),
      );

      expect(facts?.failureMessage('Git command'), isNull);
    });

    test('prefers an explicit error over the exit status', () {
      final facts = CommandPayloadFacts.tryParse(
        jsonEncode({'exit_code': 1, 'error': 'Working directory missing.'}),
      );

      expect(
        facts?.failureMessage('Git command'),
        'Working directory missing.',
      );
    });

    test('annotates a non-zero exit with stderr, falling back to stdout', () {
      final withStderr = CommandPayloadFacts.tryParse(
        jsonEncode({'exit_code': 3, 'stdout': 'out', 'stderr': 'err'}),
      );
      final stdoutOnly = CommandPayloadFacts.tryParse(
        jsonEncode({'exit_code': 3, 'stdout': 'out', 'stderr': '  '}),
      );
      final noOutput = CommandPayloadFacts.tryParse(
        jsonEncode({'exit_code': 3}),
      );

      expect(
        withStderr?.failureMessage('Git command'),
        'Git command exited with code 3: err',
      );
      expect(
        stdoutOnly?.failureMessage('Git command'),
        'Git command exited with code 3: out',
      );
      expect(
        noOutput?.failureMessage('Git command'),
        'Git command exited with code 3',
      );
    });
  });
}
