import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../../../core/services/coding_terminal_service.dart';

/// Minimum and maximum heights the drag handle can resize the panel to.
const double codingTerminalPanelMinHeight = 120;
const double codingTerminalPanelDefaultHeight = 260;

/// Bottom-docked terminal for the coding workspace.
///
/// Renders the shared [CodingTerminalService] session — the widget is
/// disposable, the shell behind it is not — with a compact header carrying the
/// working directory, a restart action, and a close action.
class CodingTerminalPanel extends ConsumerStatefulWidget {
  const CodingTerminalPanel({
    super.key,
    required this.workingDirectory,
    required this.onClose,
  });

  /// Root of the active coding project; where the shell is spawned.
  final String workingDirectory;
  final VoidCallback onClose;

  @override
  ConsumerState<CodingTerminalPanel> createState() =>
      _CodingTerminalPanelState();
}

class _CodingTerminalPanelState extends ConsumerState<CodingTerminalPanel> {
  final FocusNode _terminalFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Spawning touches the login shell, so keep it off the first frame.
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(codingTerminalServiceProvider)
            .ensureStarted(workingDirectory: widget.workingDirectory),
      );
    });
  }

  @override
  void didUpdateWidget(CodingTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workingDirectory == widget.workingDirectory) return;
    // Project switched under an open panel: re-anchor the shell to the new
    // root rather than leaving a terminal in a project the user has left.
    unawaited(
      ref
          .read(codingTerminalServiceProvider)
          .ensureStarted(workingDirectory: widget.workingDirectory),
    );
  }

  @override
  void dispose() {
    _terminalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(codingTerminalServiceProvider);
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: _terminalTheme(theme).background,
            border: Border(
              top: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(context, service),
              Expanded(
                child: TerminalView(
                  service.terminal,
                  controller: service.terminalController,
                  focusNode: _terminalFocusNode,
                  autofocus: true,
                  theme: _terminalTheme(theme),
                  textStyle: const TerminalStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  // Right-click copies the selection, or pastes when there is
                  // none — the convention on Windows terminals and the only
                  // clipboard affordance a bare PTY view offers.
                  onSecondaryTapDown: (details, offset) =>
                      unawaited(_handleSecondaryTap(service)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, CodingTerminalService service) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final directory = service.workingDirectory ?? widget.workingDirectory;

    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 12, right: 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.terminal_rounded,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          // Expanded, not Flexible + Spacer: sharing the free space with a
          // Spacer would let a long path push the buttons off the right edge.
          Expanded(
            child: Text(
              _displayDirectory(directory),
              style: labelStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!service.isRunning && service.exitCode != null) ...[
            const SizedBox(width: 8),
            Text(
              'chat.terminal_exited'.tr(
                namedArgs: {'code': '${service.exitCode}'},
              ),
              style: labelStyle?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(width: 8),
          _headerButton(
            context,
            icon: Icons.refresh_rounded,
            tooltip: 'chat.terminal_restart'.tr(),
            onPressed: () => unawaited(
              service.restart(workingDirectory: widget.workingDirectory),
            ),
          ),
          _headerButton(
            context,
            icon: Icons.close_rounded,
            tooltip: 'chat.terminal_hide'.tr(),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _headerButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    );
  }

  Future<void> _handleSecondaryTap(CodingTerminalService service) async {
    final selection = service.terminalController.selection;
    if (selection != null) {
      final text = service.terminal.buffer.getText(selection);
      service.terminalController.clearSelection();
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      service.terminal.paste(text);
    }
  }

  /// Collapse `$HOME` to `~` the way a shell prompt does.
  String _displayDirectory(String directory) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty && directory.startsWith(home)) {
      return '~${directory.substring(home.length)}';
    }
    return directory;
  }

  /// Map the app theme onto the terminal palette so the panel does not read as
  /// a foreign window: dark themes keep the familiar dark terminal, light
  /// themes get a light background with the same ANSI colors.
  TerminalTheme _terminalTheme(ThemeData theme) {
    final base = TerminalThemes.defaultTheme;
    if (theme.brightness == Brightness.dark) {
      return base;
    }
    return TerminalTheme(
      cursor: theme.colorScheme.primary,
      selection: theme.colorScheme.primary.withValues(alpha: 0.3),
      foreground: const Color(0xFF1F2328),
      background: theme.colorScheme.surface,
      black: const Color(0xFF24292F),
      red: const Color(0xFFCF222E),
      green: const Color(0xFF116329),
      yellow: const Color(0xFF7D4E00),
      blue: const Color(0xFF0969DA),
      magenta: const Color(0xFF8250DF),
      cyan: const Color(0xFF1B7C83),
      white: const Color(0xFF6E7781),
      brightBlack: const Color(0xFF57606A),
      brightRed: const Color(0xFFA40E26),
      brightGreen: const Color(0xFF1A7F37),
      brightYellow: const Color(0xFF633C01),
      brightBlue: const Color(0xFF218BFF),
      brightMagenta: const Color(0xFFA475F9),
      brightCyan: const Color(0xFF3192AA),
      brightWhite: const Color(0xFF8C959F),
      searchHitBackground: base.searchHitBackground,
      searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
      searchHitForeground: base.searchHitForeground,
    );
  }
}
