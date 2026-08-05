import 'package:caverno/features/chat/domain/services/tool_outcome_shadow_comparison.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareToolOutcomeExitCode', () {
    test('agrees when both sources report the same status', () {
      final record = compareToolOutcomeExitCode(
        toolName: 'local_execute_command',
        outcome: const ToolOutcome(exitCode: 0),
        parsedExitCode: 0,
      );

      expect(record.agreement, ToolOutcomeAgreement.agree);
      expect(record.isNoteworthy, isFalse);
    });

    test('disagrees when the statuses differ', () {
      final record = compareToolOutcomeExitCode(
        toolName: 'local_execute_command',
        outcome: const ToolOutcome(exitCode: 1),
        parsedExitCode: 0,
      );

      expect(record.agreement, ToolOutcomeAgreement.disagree);
      expect(record.isNoteworthy, isTrue);
    });

    // Zero is a status, not an absence. Treating it as missing would report
    // every successful command as an unreadable one.
    test('treats a zero exit status as present on either side', () {
      expect(
        compareToolOutcomeExitCode(
          toolName: 'run_tests',
          outcome: const ToolOutcome(exitCode: 0),
          parsedExitCode: null,
        ).agreement,
        ToolOutcomeAgreement.parsedMissing,
      );
      expect(
        compareToolOutcomeExitCode(
          toolName: 'run_tests',
          outcome: null,
          parsedExitCode: 0,
        ).agreement,
        ToolOutcomeAgreement.structuredMissing,
      );
    });

    // An outcome carrying only fileChanged has no exit status to compare, and
    // must not be read as one.
    test('an outcome without an exit status counts as missing', () {
      final record = compareToolOutcomeExitCode(
        toolName: 'edit_file',
        outcome: const ToolOutcome(fileChanged: true),
        parsedExitCode: 2,
      );

      expect(record.agreement, ToolOutcomeAgreement.structuredMissing);
      expect(record.structuredExitCode, isNull);
    });

    test('reports nothing when neither source has a status', () {
      final record = compareToolOutcomeExitCode(
        toolName: 'http_get',
        outcome: null,
        parsedExitCode: null,
      );

      expect(record.agreement, ToolOutcomeAgreement.bothAbsent);
      expect(record.isNoteworthy, isFalse);
    });

    // structuredMissing is the expected state for every producer that does not
    // attach an outcome yet, so logging it would bury the cases that decide
    // whether a consumer can switch.
    test('only disagreement and a missing parse are worth recording', () {
      final noteworthy = <ToolOutcomeAgreement>{
        for (final record in [
          compareToolOutcomeExitCode(
            toolName: 't',
            outcome: const ToolOutcome(exitCode: 1),
            parsedExitCode: 0,
          ),
          compareToolOutcomeExitCode(
            toolName: 't',
            outcome: const ToolOutcome(exitCode: 0),
            parsedExitCode: null,
          ),
          compareToolOutcomeExitCode(
            toolName: 't',
            outcome: null,
            parsedExitCode: 1,
          ),
          compareToolOutcomeExitCode(
            toolName: 't',
            outcome: const ToolOutcome(exitCode: 3),
            parsedExitCode: 3,
          ),
          compareToolOutcomeExitCode(
            toolName: 't',
            outcome: null,
            parsedExitCode: null,
          ),
        ])
          if (record.isNoteworthy) record.agreement,
      };

      expect(noteworthy, {
        ToolOutcomeAgreement.disagree,
        ToolOutcomeAgreement.parsedMissing,
      });
    });

    // The line is what a triage script greps, and it must never carry payload
    // text: tool results are untrusted content.
    test('the log line carries the shape and no payload', () {
      final line = compareToolOutcomeExitCode(
        toolName: 'local_execute_command',
        outcome: const ToolOutcome(exitCode: 1),
        parsedExitCode: 0,
      ).logLine;

      expect(
        line,
        '[ToolOutcomeShadow] tool=local_execute_command verdict=disagree '
        'structured=1 parsed=0',
      );
    });
  });
}
