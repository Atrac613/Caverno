import 'package:caverno/core/services/coding_terminal_service.dart';
import 'package:caverno/features/chat/presentation/widgets/terminal/coding_terminal_dock.dart';
import 'package:caverno/features/chat/presentation/widgets/terminal/coding_terminal_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {required ProviderContainer container}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  const child = ColoredBox(key: ValueKey('workspace'), color: Colors.blue);

  ProviderContainer container() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('renders the workspace untouched when no project is active', (
    tester,
  ) async {
    final providers = container();
    providers.read(codingTerminalServiceProvider).togglePanel('thread-a');

    await tester.pumpWidget(
      host(
        const CodingTerminalDock(
          workingDirectory: null,
          threadId: 'thread-a',
          child: child,
        ),
        container: providers,
      ),
    );

    expect(find.byKey(const ValueKey('workspace')), findsOneWidget);
    expect(find.byType(CodingTerminalPanel), findsNothing);
  });

  testWidgets('keeps the panel hidden while the toggle is off', (tester) async {
    final providers = container();

    await tester.pumpWidget(
      host(
        const CodingTerminalDock(
          workingDirectory: '/tmp/project',
          threadId: 'thread-a',
          child: child,
        ),
        container: providers,
      ),
    );

    final service = providers.read(codingTerminalServiceProvider);
    expect(service.isPanelOpenFor('thread-a'), isFalse);
    expect(find.byType(CodingTerminalPanel), findsNothing);
  });

  test('open/closed state is tracked per thread', () {
    final service = container().read(codingTerminalServiceProvider);

    service.togglePanel('thread-a');
    expect(service.isPanelOpenFor('thread-a'), isTrue);
    // A thread the user never opened the terminal on stays closed.
    expect(service.isPanelOpenFor('thread-b'), isFalse);
    // So does the not-yet-saved draft thread.
    expect(service.isPanelOpenFor(null), isFalse);

    service.togglePanel('thread-b');
    service.closePanel('thread-a');
    expect(service.isPanelOpenFor('thread-a'), isFalse);
    expect(service.isPanelOpenFor('thread-b'), isTrue);
  });

  test('toggling the panel does not start a shell on its own', () {
    final service = container().read(codingTerminalServiceProvider);

    service.togglePanel('thread-a');
    // Spawning is the panel's job, so a toggle leaves the session untouched
    // until something renders it.
    expect(service.isRunning, isFalse);
    expect(service.workingDirectory, isNull);
  });
}
