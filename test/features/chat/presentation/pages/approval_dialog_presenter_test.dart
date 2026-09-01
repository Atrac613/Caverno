import 'package:caverno/features/chat/presentation/pages/approval_dialog_presenter.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/approval_dialog_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for one pending interaction.
class _Pending {
  const _Pending(this.id);
  final String id;
}

void main() {
  late ApprovalDialogPresenter presenter;
  late BuildContext hostContext;
  late List<String> presented;

  Future<void> pumpHost(WidgetTester tester) async {
    presenter = ApprovalDialogPresenter();
    presented = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: Text('host'));
          },
        ),
      ),
    );
  }

  Future<void> present(_Pending pending) {
    presented.add(pending.id);
    return showModalBottomSheet<void>(
      context: hostContext,
      isDismissible: false,
      routeSettings: RouteSettings(name: approvalDialogRouteName(pending.id)),
      builder: (_) => Text('sheet ${pending.id}'),
    );
  }

  void sync(_Pending? previous, _Pending? next) {
    presenter.sync<_Pending>(
      context: hostContext,
      previous: previous,
      next: next,
      idOf: (pending) => pending.id,
      present: present,
      isMounted: () => true,
    );
  }

  testWidgets('presents a pending interaction once', (tester) async {
    await pumpHost(tester);

    sync(null, const _Pending('a'));
    sync(const _Pending('a'), const _Pending('a'));
    await tester.pumpAndSettle();

    expect(presented, ['a']);
    expect(find.text('sheet a'), findsOneWidget);
  });

  testWidgets('closes the sheet when the pending is resolved elsewhere', (
    tester,
  ) async {
    await pumpHost(tester);
    sync(null, const _Pending('a'));
    await tester.pumpAndSettle();
    expect(find.text('sheet a'), findsOneWidget);

    // What the watch answering looks like from the phone's side: the pending
    // clears without the phone's own sheet having returned anything.
    sync(const _Pending('a'), null);
    await tester.pumpAndSettle();

    expect(find.text('sheet a'), findsNothing);
  });

  testWidgets('a replacement pending closes the previous sheet and opens the '
      'next', (tester) async {
    await pumpHost(tester);
    sync(null, const _Pending('a'));
    await tester.pumpAndSettle();

    sync(const _Pending('a'), const _Pending('b'));
    await tester.pumpAndSettle();

    expect(find.text('sheet a'), findsNothing);
    expect(find.text('sheet b'), findsOneWidget);
    expect(presented, ['a', 'b']);
  });

  testWidgets('never pops a route it did not open', (tester) async {
    await pumpHost(tester);
    sync(null, const _Pending('a'));
    await tester.pumpAndSettle();

    // Something unrelated is pushed on top of the approval sheet.
    unawaitedPush(hostContext);
    await tester.pumpAndSettle();
    expect(find.text('unrelated'), findsOneWidget);

    sync(const _Pending('a'), null);
    await tester.pumpAndSettle();

    expect(
      find.text('unrelated'),
      findsOneWidget,
      reason:
          'popUntil with a name predicate must be a no-op when the approval '
          'route is not topmost, or a mistimed resolution closes whatever the '
          'user is actually looking at.',
    );
  });

  testWidgets('skips a pending the caller says not to present', (tester) async {
    await pumpHost(tester);

    presenter.sync<_Pending>(
      context: hostContext,
      previous: null,
      next: const _Pending('a'),
      idOf: (pending) => pending.id,
      present: present,
      isMounted: () => true,
      shouldPresent: (_) => false,
    );
    await tester.pumpAndSettle();

    expect(presented, isEmpty);
    expect(presenter.isOpen('a'), isFalse);
  });
}

void unawaitedPush(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'unrelated'),
      builder: (_) => const Scaffold(body: Text('unrelated')),
    ),
  );
}
