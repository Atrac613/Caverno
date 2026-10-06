import 'package:flutter/material.dart';

const double chatCompanionSidebarBreakpoint = 1180;
const double chatCompanionSidebarWidth = 344;
const double chatFileWorkspacePanelMinWidth = 420;
const double chatFileWorkspacePanelMaxWidth = 720;

enum ChatRightSidebarTab { companion, files, processes }

class ChatRightSidebarPanel extends StatelessWidget {
  const ChatRightSidebarPanel({
    super.key,
    required this.availableWidth,
    required this.companionPanel,
    required this.fileViewer,
    required this.selectedTab,
    required this.onSelected,
    this.processPanel,
  });

  final double availableWidth;
  final Widget companionPanel;
  final Widget? fileViewer;

  /// Background processes of the conversation; null where none can run.
  final Widget? processPanel;
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
    final processes = processPanel;
    if (viewer == null && processes == null) {
      return SizedBox(width: _panelWidth, child: companionPanel);
    }
    final tabs = <ChatRightSidebarTab, Widget>{
      ChatRightSidebarTab.companion: companionPanel,
      ChatRightSidebarTab.files: ?viewer,
      // Mounted only while selected: the list polls the job registry, and a
      // hidden tab has no reason to keep that timer alive.
      ChatRightSidebarTab.processes: ?(processes == null
          ? null
          : selectedTab == ChatRightSidebarTab.processes
          ? processes
          : const SizedBox.shrink()),
    };
    // A tab whose body went away (the file viewer closed) falls back to the
    // companion instead of showing nothing.
    final activeTab = tabs.containsKey(selectedTab)
        ? selectedTab
        : ChatRightSidebarTab.companion;
    // Three labelled segments do not fit the companion width with icons.
    final showIcons = tabs.length < 3;

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
                  selected: {activeTab},
                  segments: [
                    ButtonSegment(
                      value: ChatRightSidebarTab.companion,
                      icon: showIcons
                          ? const Icon(Icons.view_sidebar_outlined, size: 18)
                          : null,
                      label: const Text('Companion'),
                    ),
                    if (viewer != null)
                      ButtonSegment(
                        value: ChatRightSidebarTab.files,
                        icon: showIcons
                            ? const Icon(Icons.description_outlined, size: 18)
                            : null,
                        label: const Text('Files'),
                      ),
                    if (processes != null)
                      ButtonSegment(
                        value: ChatRightSidebarTab.processes,
                        icon: showIcons
                            ? const Icon(Icons.terminal, size: 18)
                            : null,
                        label: const Text('Processes'),
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
                index: tabs.keys.toList().indexOf(activeTab),
                children: tabs.values.toList(),
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
