import 'package:flutter/material.dart';

const double chatPagePersistentDrawerBreakpoint = 900;
const double chatPagePersistentDrawerWidth = 320;

class ChatPageScaffold extends StatelessWidget {
  const ChatPageScaffold.compact({
    super.key,
    required this.workspaceBody,
    required this.taskBanner,
    required Widget title,
    required List<Widget> actions,
    required Widget drawer,
    this.floatingActionButton,
  }) : _persistent = false,
       _persistentDrawer = null,
       _persistentHeader = null,
       _compactTitle = title,
       _compactActions = actions,
       _compactDrawer = drawer,
       persistentDrawerWidth = chatPagePersistentDrawerWidth;

  const ChatPageScaffold.persistent({
    super.key,
    required this.workspaceBody,
    required this.taskBanner,
    required Widget drawer,
    required Widget header,
    this.persistentDrawerWidth = chatPagePersistentDrawerWidth,
  }) : _persistent = true,
       _persistentDrawer = drawer,
       _persistentHeader = header,
       _compactTitle = null,
       _compactActions = const [],
       _compactDrawer = null,
       floatingActionButton = null;

  final Widget workspaceBody;
  final Widget taskBanner;
  final Widget? floatingActionButton;
  final double persistentDrawerWidth;
  final bool _persistent;
  final Widget? _persistentDrawer;
  final Widget? _persistentHeader;
  final Widget? _compactTitle;
  final List<Widget> _compactActions;
  final Widget? _compactDrawer;

  @override
  Widget build(BuildContext context) {
    final scaffoldBody = _persistent
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: persistentDrawerWidth, child: _persistentDrawer!),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).dividerColor,
              ),
              Expanded(
                child: Column(
                  children: [
                    _persistentHeader!,
                    Expanded(child: workspaceBody),
                  ],
                ),
              ),
            ],
          )
        : workspaceBody;

    return Scaffold(
      appBar: _persistent
          ? null
          : AppBar(title: _compactTitle, actions: _compactActions),
      drawer: _persistent ? null : _compactDrawer,
      floatingActionButton: floatingActionButton,
      body: Column(
        children: [
          taskBanner,
          Expanded(child: scaffoldBody),
        ],
      ),
    );
  }
}
