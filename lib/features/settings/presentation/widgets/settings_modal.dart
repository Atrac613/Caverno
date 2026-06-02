import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../pages/advanced_settings_page.dart';
import '../pages/chat_settings_page.dart';
import '../pages/computer_use_settings_page.dart';
import '../pages/general_settings_page.dart';
import '../pages/slash_command_settings_page.dart';
import '../pages/tools_settings_page.dart';
import '../pages/voice_settings_page.dart';
import 'settings_actions_menu.dart';

/// Opens the desktop settings experience as a centered modal with a sidebar of
/// categories and a content panel. Used by the macOS application menu
/// (Caverno > Settings…) and the conversation drawer on desktop platforms.
Future<void> showSettingsModal(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const SettingsModal(),
  );
}

/// A settings category shown in the sidebar. [builder] creates the existing
/// per-category page that is hosted inside the content panel's nested navigator.
class _SettingsCategory {
  const _SettingsCategory({
    required this.icon,
    required this.labelKey,
    required this.builder,
  });

  final IconData icon;
  final String labelKey;
  final WidgetBuilder builder;
}

class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key});

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  int _selectedIndex = 0;

  static final List<_SettingsCategory> _categories = [
    _SettingsCategory(
      icon: Icons.settings_outlined,
      labelKey: 'settings.menu_general',
      builder: (_) => const GeneralSettingsPage(),
    ),
    _SettingsCategory(
      icon: Icons.memory_outlined,
      labelKey: 'settings.menu_chat',
      builder: (_) => const ChatSettingsPage(),
    ),
    _SettingsCategory(
      icon: Icons.terminal_outlined,
      labelKey: 'settings.menu_slash_commands',
      builder: (_) => const SlashCommandSettingsPage(),
    ),
    _SettingsCategory(
      icon: Icons.mic_outlined,
      labelKey: 'settings.menu_voice',
      builder: (_) => const VoiceSettingsPage(),
    ),
    _SettingsCategory(
      icon: Icons.build_outlined,
      labelKey: 'settings.menu_tools',
      builder: (_) => const ToolsSettingsPage(),
    ),
    _SettingsCategory(
      icon: Icons.tune_outlined,
      labelKey: 'settings.menu_advanced',
      builder: (_) => AdvancedSettingsPage(
        computerUseBuilder: (_) => const ComputerUseSettingsPage(),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = math.min(920.0, media.size.width * 0.92);
    final height = math.min(640.0, media.size.height * 0.88);

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _SettingsModalHeader(onClose: () => Navigator.of(context).pop()),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsSidebar(
                    categories: _categories,
                    selectedIndex: _selectedIndex,
                    onSelected: (index) =>
                        setState(() => _selectedIndex = index),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ClipRect(
                      // A nested navigator keeps any drill-down (e.g. Advanced ->
                      // Computer Use) inside the modal. The key resets it to the
                      // category root whenever the sidebar selection changes.
                      child: Navigator(
                        key: ValueKey<int>(_selectedIndex),
                        onGenerateInitialRoutes: (navigator, initialRoute) => [
                          MaterialPageRoute<void>(
                            builder: _categories[_selectedIndex].builder,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsModalHeader extends StatelessWidget {
  const _SettingsModalHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
      child: Row(
        children: [
          Text('settings.title'.tr(), style: theme.textTheme.titleLarge),
          const Spacer(),
          const SettingsActionsMenu(),
          IconButton(
            tooltip: 'common.close'.tr(),
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.categories,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_SettingsCategory> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return _SidebarTile(
            icon: category.icon,
            label: category.labelKey.tr(),
            selected: index == selectedIndex,
            onTap: () => onSelected(index),
          );
        },
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
