import 'package:caverno/core/services/coding_terminal_service.dart';
import 'package:caverno/features/chat/presentation/providers/bottom_dock_provider.dart';
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
          runProjectRoot: '',
          onSendIssueToChat: _ignoreIssue,
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
          runProjectRoot: '',
          onSendIssueToChat: _ignoreIssue,
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
  testWidgets('shows the run panes for a project without a terminal', (
    tester,
  ) async {
    // The run panes do not need a shell, so the dock still opens where the
    // terminal cannot be offered.
    final providers = container();
    providers.read(codingTerminalServiceProvider).togglePanel('thread-a');

    await tester.pumpWidget(
      host(
        const CodingTerminalDock(
          runProjectRoot: '/work/app',
          onSendIssueToChat: _ignoreIssue,
          workingDirectory: null,
          threadId: 'thread-a',
          child: child,
        ),
        container: providers,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('bottom-dock-tab-run-log')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-dock-tab-terminal')),
      findsNothing,
    );
    expect(find.byType(CodingTerminalPanel), findsNothing);
  });

  testWidgets('selecting a tab swaps the pane', (tester) async {
    final providers = container();
    providers.read(codingTerminalServiceProvider).togglePanel('thread-a');

    await tester.pumpWidget(
      host(
        const CodingTerminalDock(
          runProjectRoot: '/work/app',
          onSendIssueToChat: _ignoreIssue,
          workingDirectory: null,
          threadId: 'thread-a',
          child: child,
        ),
        container: providers,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('bottom-dock-tab-issues')));
    await tester.pump();

    expect(
      providers.read(bottomDockTabProvider)['thread-a'],
      BottomDockTab.issues,
    );
  });
}

void _ignoreIssue(Object issue) {}
