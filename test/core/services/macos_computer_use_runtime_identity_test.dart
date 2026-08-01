import 'package:caverno/core/services/macos_computer_use_runtime_identity.dart';
import 'package:test/test.dart';

void main() {
  group('MacosComputerUseRuntimeIdentityProvider', () {
    test('captures one immutable normalized runtime identity', () {
      final provider = MacosComputerUseRuntimeIdentityProvider(
        initialSessionId: ' runtime-a ',
        initialRevision: 3,
      );

      final first = provider.capture();
      final second = provider.capture();

      expect(first, same(second));
      expect(first.sessionId, 'runtime-a');
      expect(first.revision, 3);
    });

    test('helper restart rotates the session and increments revision', () {
      final provider = MacosComputerUseRuntimeIdentityProvider(
        initialSessionId: 'runtime-a',
        initialRevision: 3,
        sessionIdFactory: () => 'runtime-b',
      );

      final invalidation = provider.helperRestarted();

      expect(
        invalidation.cause,
        MacosComputerUseRuntimeInvalidationCause.helperRestart,
      );
      expect(invalidation.previous.sessionId, 'runtime-a');
      expect(invalidation.previous.revision, 3);
      expect(invalidation.current.sessionId, 'runtime-b');
      expect(invalidation.current.revision, 4);
      expect(invalidation.rotatedSession, isTrue);
      expect(provider.capture(), same(invalidation.current));
    });

    test('emergency stop preserves the session and increments revision', () {
      final provider = MacosComputerUseRuntimeIdentityProvider(
        initialSessionId: 'runtime-a',
        initialRevision: 3,
      );

      final invalidation = provider.emergencyStop();

      expect(
        invalidation.cause,
        MacosComputerUseRuntimeInvalidationCause.emergencyStop,
      );
      expect(invalidation.previous.sessionId, 'runtime-a');
      expect(invalidation.current.sessionId, 'runtime-a');
      expect(invalidation.current.revision, 4);
      expect(invalidation.rotatedSession, isFalse);
    });

    test('keeps a helper transition unavailable until exact settlement', () {
      final provider = MacosComputerUseRuntimeIdentityProvider(
        initialSessionId: 'runtime-a',
        sessionIdFactory: () => 'runtime-b',
      );

      final transition = provider.beginHelperRestart();

      expect(provider.captureAvailable(), isNull);
      expect(
        provider.captureSnapshot().availability,
        MacosComputerUseRuntimeAvailability.transitioning,
      );
      expect(transition.invalidation.current.sessionId, 'runtime-b');
      expect(
        provider.finishTransition(transition, helperAvailable: true),
        isTrue,
      );
      expect(provider.captureAvailable()?.sessionId, 'runtime-b');
      expect(
        provider.captureSnapshot().availability,
        MacosComputerUseRuntimeAvailability.available,
      );
    });

    test('ignores stale transition completion and can remain stopped', () {
      var nextSession = 0;
      final provider = MacosComputerUseRuntimeIdentityProvider(
        initialSessionId: 'runtime-a',
        sessionIdFactory: () => 'runtime-${++nextSession}',
      );
      final first = provider.beginHelperLaunch();
      final second = provider.beginHelperTermination();

      expect(provider.finishTransition(first, helperAvailable: true), isFalse);
      expect(provider.captureAvailable(), isNull);
      expect(provider.finishTransition(second, helperAvailable: false), isTrue);
      expect(provider.captureAvailable(), isNull);
      expect(
        provider.captureSnapshot().availability,
        MacosComputerUseRuntimeAvailability.stopped,
      );
    });

    test(
      'notifies attached listeners synchronously and detaches exactly once',
      () {
        final provider = MacosComputerUseRuntimeIdentityProvider(
          initialSessionId: 'runtime-a',
        );
        final observed = <MacosComputerUseRuntimeInvalidation>[];
        final detach = provider.addInvalidationListener(observed.add);

        final first = provider.emergencyStop();
        expect(observed, [same(first)]);

        detach();
        detach();
        provider.helperRestarted();
        expect(observed, [same(first)]);
      },
    );

    test('isolates a failing listener from runtime invalidation', () {
      final provider = MacosComputerUseRuntimeIdentityProvider(
        initialSessionId: 'runtime-a',
      );
      final observed = <MacosComputerUseRuntimeInvalidation>[];
      provider.addInvalidationListener((_) => throw StateError('listener'));
      provider.addInvalidationListener(observed.add);

      final invalidation = provider.emergencyStop();

      expect(observed, [same(invalidation)]);
      expect(provider.capture().revision, 1);
    });

    test('rejects invalid initial identity values', () {
      expect(
        () => MacosComputerUseRuntimeIdentityProvider(initialSessionId: ' '),
        throwsArgumentError,
      );
      expect(
        () => MacosComputerUseRuntimeIdentityProvider(initialRevision: -1),
        throwsRangeError,
      );
    });
  });
}
