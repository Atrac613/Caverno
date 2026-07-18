import 'package:caverno/features/chat/presentation/widgets/chat_right_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    );
  }

  testWidgets('companion-only panel keeps the fixed width and omits tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ChatRightSidebarPanel(
          availableWidth: 1400,
          companionPanel: const Text('companion body'),
          fileViewer: null,
          selectedTab: ChatRightSidebarTab.files,
          onSelected: (_) {},
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(ChatRightSidebarPanel)).width,
      chatCompanionSidebarWidth,
    );
    expect(find.byKey(const ValueKey('right-sidebar-tabs')), findsNothing);
    expect(find.text('companion body'), findsOneWidget);
  });

  testWidgets('file panel width is proportional and clamped', (tester) async {
    Future<double> pumpFor(double availableWidth) async {
      await tester.pumpWidget(
        host(
          ChatRightSidebarPanel(
            availableWidth: availableWidth,
            companionPanel: const Text('companion body'),
            fileViewer: const Text('file body'),
            selectedTab: ChatRightSidebarTab.companion,
            onSelected: (_) {},
          ),
        ),
      );
      return tester.getSize(find.byType(ChatRightSidebarPanel)).width;
    }

    expect(await pumpFor(800), chatFileWorkspacePanelMinWidth);
    expect(await pumpFor(1400), 588);
    expect(await pumpFor(2000), chatFileWorkspacePanelMaxWidth);
    expect(await pumpFor(double.infinity), chatCompanionSidebarWidth);
  });

  testWidgets('tab selection is controlled and keeps both bodies mounted', (
    tester,
  ) async {
    var selectedTab = ChatRightSidebarTab.companion;
    var selectionCount = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            return ChatRightSidebarPanel(
              availableWidth: 1400,
              companionPanel: const Text('companion body'),
              fileViewer: const Text('file body'),
              selectedTab: selectedTab,
              onSelected: (nextTab) {
                selectionCount++;
                setState(() => selectedTab = nextTab);
              },
            );
          },
        ),
      ),
    );

    expect(find.text('companion body'), findsOneWidget);
    expect(find.text('file body'), findsNothing);
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).children,
      hasLength(2),
    );

    await tester.tap(find.text('Files'));
    await tester.pump();

    expect(selectedTab, ChatRightSidebarTab.files);
    expect(selectionCount, 1);
    expect(find.text('companion body'), findsNothing);
    expect(find.text('file body'), findsOneWidget);
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).children,
      hasLength(2),
    );
  });

  testWidgets('split layout expands content before a one-pixel divider', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 700,
          height: 400,
          child: ChatRightSidebarLayout(
            content: ColoredBox(key: ValueKey('content'), color: Colors.blue),
            sidebar: SizedBox(
              key: ValueKey('sidebar'),
              width: chatCompanionSidebarWidth,
            ),
          ),
        ),
      ),
    );

    final divider = tester.widget<VerticalDivider>(
      find.byType(VerticalDivider),
    );
    expect(divider.width, 1);
    expect(divider.thickness, 1);
    expect(
      tester.getSize(find.byKey(const ValueKey('sidebar'))),
      const Size(chatCompanionSidebarWidth, 400),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('content'))),
      const Size(355, 400),
    );
  });
}
