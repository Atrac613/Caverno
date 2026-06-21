// Same-library extension on [_ChatPageState]; see chat_page_empty_state_builders.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_page.dart';

/// Built-in agent-controlled browser pane and its sensitive-action approval
/// sheet. The webview is hosted once (a single [InAppWebView]); the
/// [BrowserSessionService] drives navigation and reads back its state here.
extension _ChatPageBrowserBuilders on _ChatPageState {
  /// Wraps the chat workspace with the browser pane when the session is open.
  /// On wide layouts it sits as the right-most pane; on narrow layouts it
  /// stays above the chat so the composer remains reachable.
  Widget _wrapWithBrowserPane(
    BuildContext context,
    Widget coreBody, {
    required double availableWidth,
    required double availableHeight,
  }) {
    final service = ref.watch(browserSessionServiceProvider);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!service.isAvailable || !service.isPanelOpen) {
          return coreBody;
        }
        if (availableWidth >= _ChatPageState._browserPanelBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: coreBody),
              SizedBox(
                width: _ChatPageState._browserPanelWidth,
                child: _buildBrowserPanel(context, service),
              ),
            ],
          );
        }
        final compactHeight = availableHeight.isFinite
            ? availableHeight
            : MediaQuery.sizeOf(context).height;
        final maxBrowserHeight =
            compactHeight - _ChatPageState._compactBrowserChatReserveHeight;
        final browserHeight = maxBrowserHeight <= 0
            ? 0.0
            : (compactHeight *
                      _ChatPageState._compactBrowserPanelHeightFraction)
                  .clamp(0.0, maxBrowserHeight)
                  .toDouble();
        return Column(
          children: [
            SizedBox(
              height: browserHeight,
              child: _buildBrowserPanel(
                context,
                service,
                fullScreen: true,
                bottomBorder: true,
                bottomSafeArea: false,
              ),
            ),
            Expanded(child: coreBody),
          ],
        );
      },
    );
  }

  Widget _buildBrowserPanel(
    BuildContext context,
    BrowserSessionService service, {
    bool fullScreen = false,
    bool bottomBorder = false,
    bool bottomSafeArea = true,
  }) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: bottomBorder
            ? Border(bottom: BorderSide(color: theme.dividerColor))
            : fullScreen
            ? null
            : Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: bottomSafeArea,
        child: Column(
          children: [
            _buildBrowserToolbar(context, service),
            if (service.isLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: ClipRect(child: _browserWebViewHost())),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowserToolbar(
    BuildContext context,
    BrowserSessionService service,
  ) {
    final theme = Theme.of(context);
    final title = (service.pageTitle?.trim().isNotEmpty ?? false)
        ? service.pageTitle!.trim()
        : (service.currentUrl ?? 'settings.browser_untitled'.tr());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: 'settings.browser_back'.tr(),
            onPressed: service.canGoBack
                ? () => service.navigateHistory('back')
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward, size: 18),
            tooltip: 'settings.browser_forward'.tr(),
            onPressed: service.canGoForward
                ? () => service.navigateHistory('forward')
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'settings.browser_reload'.tr(),
            onPressed: () => service.navigateHistory('reload'),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
                if (service.currentUrl != null)
                  Text(
                    _browserHostLabel(service.currentUrl!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'settings.browser_close'.tr(),
            onPressed: () => service.closePanel(),
          ),
        ],
      ),
    );
  }

  /// The single webview instance, built once and reused (stable [GlobalKey]) so
  /// toggling the pane or moving between pane/full-screen preserves the page.
  Widget _browserWebViewHost() {
    return _browserWebView ??= _BrowserWebViewHost(
      key: _browserWebViewKey,
      service: ref.read(browserSessionServiceProvider),
    );
  }

  String _browserHostLabel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.host.isNotEmpty ? uri.host : url;
  }

  Future<void> _showBrowserActionDialog(
    BuildContext context,
    PendingBrowserAction pending,
  ) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.travel_explore,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pending.title,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            pending.riskLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ToolPerimeterSummary(toolName: pending.toolName),
                const SizedBox(height: 12),
                Text(pending.warningMessage, style: theme.textTheme.bodyMedium),
                _browserApprovalRow(
                  theme,
                  Icons.bolt_outlined,
                  pending.summary,
                ),
                if (pending.targetSummary != null)
                  _browserApprovalRow(
                    theme,
                    Icons.my_location_outlined,
                    pending.targetSummary!,
                  ),
                if (pending.sensitiveValuePreview != null)
                  _browserApprovalRow(
                    theme,
                    Icons.short_text,
                    pending.sensitiveValuePreview!,
                    monospace: true,
                  ),
                if (pending.reason != null && pending.reason!.trim().isNotEmpty)
                  _browserApprovalRow(
                    theme,
                    Icons.psychology_outlined,
                    pending.reason!.trim(),
                  ),
                if (pending.details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...pending.details.map(
                    (detail) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• $detail',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: Text('settings.browser_deny'.tr()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(pending.approveLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    ref
        .read(chatNotifierProvider.notifier)
        .resolveBrowserAction(id: pending.id, approved: approved ?? false);
  }

  Widget _browserApprovalRow(
    ThemeData theme,
    IconData icon,
    String text, {
    bool monospace = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: monospace
                  ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hosts the single [InAppWebView] and registers/unregisters its controller
/// with the [BrowserSessionService] across its lifecycle. Kept stateful so the
/// controller is detached when the pane is removed (closed, workspace switch,
/// or navigation), letting a later `browser_open` re-arm readiness cleanly.
class _BrowserWebViewHost extends StatefulWidget {
  const _BrowserWebViewHost({super.key, required this.service});

  final BrowserSessionService service;

  @override
  State<_BrowserWebViewHost> createState() => _BrowserWebViewHostState();
}

class _BrowserWebViewHostState extends State<_BrowserWebViewHost> {
  InAppWebViewController? _controller;

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      widget.service.detachController(controller);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: InAppWebViewSettings(
        isInspectable: kDebugMode,
        javaScriptEnabled: true,
        transparentBackground: false,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.service.attachController(controller);
      },
      onLoadStart: (controller, url) =>
          widget.service.handleLoadStart(url?.toString()),
      onLoadStop: (controller, url) =>
          widget.service.handleLoadStop(url?.toString()),
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? true) {
          widget.service.handleError(error.description);
        }
      },
      onTitleChanged: (controller, title) =>
          widget.service.handleTitleChanged(title),
    );
  }
}
