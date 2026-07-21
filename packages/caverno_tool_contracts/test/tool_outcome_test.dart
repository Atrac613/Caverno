import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('exit status', () {
    test('separates a failing exit from an absent one', () {
      // The distinction the whole type exists for: "ran and failed" and "never
      // reached an exit" must never collapse into one answer.
      expect(const ToolOutcome(exitCode: 1).hasFailingExitCode, isTrue);
      expect(const ToolOutcome(exitCode: 0).hasFailingExitCode, isFalse);
      expect(const ToolOutcome().hasFailingExitCode, isFalse);
      expect(const ToolOutcome().hasSucceedingExitCode, isFalse);
    });

    test('treats a negative exit status as failure', () {
      // Signal-terminated processes surface as negative on some platforms.
      expect(const ToolOutcome(exitCode: -9).hasFailingExitCode, isTrue);
    });
  });

  group('emptiness', () {
    test('an outcome with nothing populated is empty', () {
      expect(const ToolOutcome().isEmpty, isTrue);
      expect(const ToolOutcome().isNotEmpty, isFalse);
      expect(const ToolOutcome(exitCode: 0).isNotEmpty, isTrue);
    });
  });

  group('json', () {
    test('round-trips a populated outcome', () {
      const outcome = ToolOutcome(exitCode: 2);
      expect(ToolOutcome.fromJson(outcome.toJson()), outcome);
    });

    test('omits absent facts rather than encoding null', () {
      expect(const ToolOutcome().toJson(), isEmpty);
    });

    test('decodes absent, empty, and malformed input as no outcome', () {
      expect(ToolOutcome.fromJson(null), isNull);
      expect(ToolOutcome.fromJson(const {}), isNull);
      expect(ToolOutcome.fromJson(const {'exit_code': 'nope'}), isNull);
    });

    test('accepts a numeric exit code that arrives as a double', () {
      // JSON decoders may hand back 1.0 for an integer field.
      expect(ToolOutcome.fromJson(const {'exit_code': 1.0})?.exitCode, 1);
    });
  });

  test('value equality', () {
    expect(const ToolOutcome(exitCode: 1), const ToolOutcome(exitCode: 1));
    expect(
      const ToolOutcome(exitCode: 1).hashCode,
      const ToolOutcome(exitCode: 1).hashCode,
    );
    expect(const ToolOutcome(exitCode: 1), isNot(const ToolOutcome()));
  });
}
