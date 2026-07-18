import 'package:caverno/features/chat/presentation/widgets/chat_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('compact scaffold exposes app bar drawer banner and FAB', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ChatPageScaffold.compact(
          workspaceBody: ColoredBox(
            key: ValueKey('workspace'),
            color: Colors.blue,
          ),
          taskBanner: SizedBox(key: ValueKey('task-banner'), height: 24),
          title: Text('Compact title'),
          actions: [Icon(Icons.tune)],
          drawer: Drawer(child: Text('Temporary drawer')),
          floatingActionButton: FloatingActionButton(
            onPressed: null,
            child: Icon(Icons.add),
          ),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.appBar, isA<AppBar>());
    expect(scaffold.drawer, isA<Drawer>());
    expect(scaffold.floatingActionButton, isA<FloatingActionButton>());
    expect(find.text('Compact title'), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byKey(const ValueKey('task-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace')), findsOneWidget);
  });

  testWidgets('persistent scaffold replaces compact chrome with fixed drawer', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ChatPageScaffold.persistent(
          workspaceBody: ColoredBox(
            key: ValueKey('workspace'),
            color: Colors.blue,
          ),
          taskBanner: SizedBox(key: ValueKey('task-banner'), height: 24),
          drawer: ColoredBox(
            key: ValueKey('persistent-drawer'),
            color: Colors.red,
          ),
          header: SizedBox(key: ValueKey('persistent-header'), height: 48),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.appBar, isNull);
    expect(scaffold.drawer, isNull);
    expect(scaffold.floatingActionButton, isNull);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('task-banner')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('persistent-drawer'))).width,
      chatPagePersistentDrawerWidth,
    );
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.byKey(const ValueKey('persistent-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace')), findsOneWidget);
  });

  testWidgets('persistent scaffold honors an explicit drawer width', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ChatPageScaffold.persistent(
          workspaceBody: SizedBox(),
          taskBanner: SizedBox(),
          drawer: ColoredBox(
            key: ValueKey('persistent-drawer'),
            color: Colors.red,
          ),
          header: SizedBox(),
          persistentDrawerWidth: 280,
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('persistent-drawer'))).width,
      280,
    );
  });
}
