import 'package:flutter/material.dart';

const double chatCompanionSidebarBreakpoint = 1180;
const double chatCompanionSidebarWidth = 344;
const double chatFileWorkspacePanelMinWidth = 420;
const double chatFileWorkspacePanelMaxWidth = 720;

enum ChatRightSidebarTab { companion, files }

class ChatRightSidebarPanel extends StatelessWidget {
  const ChatRightSidebarPanel({
    super.key,
    required this.availableWidth,
    required this.companionPanel,
    required this.fileViewer,
    required this.selectedTab,
    required this.onSelected,
  });

  final double availableWidth;
  final Widget companionPanel;
  final Widget? fileViewer;
  final ChatRightSidebarTab selectedTab;
  final ValueChanged<ChatRightSidebarTab> onSelected;

  double get _panelWidth {
    if (fileViewer == null || !availableWidth.isFinite) {
      return chatCompanionSidebarWidth;
    }
    return (availableWidth * 0.42)
        .clamp(chatFileWorkspacePanelMinWidth, chatFileWorkspacePanelMaxWidth)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final viewer = fileViewer;
    if (viewer == null) {
      return SizedBox(width: _panelWidth, child: companionPanel);
    }

    final theme = Theme.of(context);
    return SizedBox(
      width: _panelWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ChatRightSidebarTab>(
                  key: const ValueKey('right-sidebar-tabs'),
                  showSelectedIcon: false,
                  selected: {selectedTab},
                  segments: const [
                    ButtonSegment(
                      value: ChatRightSidebarTab.companion,
                      icon: Icon(Icons.view_sidebar_outlined, size: 18),
                      label: Text('Companion'),
                    ),
                    ButtonSegment(
                      value: ChatRightSidebarTab.files,
                      icon: Icon(Icons.description_outlined, size: 18),
                      label: Text('Files'),
                    ),
                  ],
                  onSelectionChanged: (selection) {
                    onSelected(selection.single);
                  },
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: theme.dividerColor),
            Expanded(
              child: IndexedStack(
                index: selectedTab == ChatRightSidebarTab.companion ? 0 : 1,
                children: [companionPanel, viewer],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatRightSidebarLayout extends StatelessWidget {
  const ChatRightSidebarLayout({
    super.key,
    required this.content,
    required this.sidebar,
  });

  final Widget content;
  final Widget sidebar;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: content),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).dividerColor,
        ),
        sidebar,
      ],
    );
  }
}
