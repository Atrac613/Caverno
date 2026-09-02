import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../security/egress_destination_policy.dart';
import '../utils/logger.dart';
import 'browser_mediation_proxy.dart';
import 'browser_pinned_http_client.dart';

/// Singleton service backing the built-in agent-controlled browser.
///
/// It owns the live [InAppWebViewController] that the on-screen browser panel
/// attaches, exposes session state for that panel to render (URL, title,
/// loading), and implements every `browser_*` tool as a JSON-returning method.
///
/// This mirrors `MacosComputerUseService`: a plain injectable service that
/// `McpToolService` calls into, gated by [isAvailable]. The difference is that
/// the browser must drive a Flutter widget, so the panel registers its
/// controller via [attachController] and the action methods await readiness.
final browserSessionServiceProvider = Provider<BrowserSessionService>((ref) {
  final service = BrowserSessionService();
  ref.onDispose(service.dispose);
  return service;
});

/// Thrown when a browser action is requested on an unsupported platform or
/// while the feature is disabled in settings.
class BrowserUnavailableException implements Exception {
  const BrowserUnavailableException();
}

/// Thrown when the browser panel did not mount its webview in time.
class BrowserNotReadyException implements Exception {
  const BrowserNotReadyException();
}

class BrowserNavigationDecision {
  const BrowserNavigationDecision._({
    required this.allowed,
    required this.code,
    required this.message,
  });

  const BrowserNavigationDecision.allowInternalBlank()
    : this._(
        allowed: true,
        code: 'internal_blank',
        message: 'Internal blank-page initialization is allowed.',
      );

  const BrowserNavigationDecision.allowLocalPreview()
    : this._(
        allowed: true,
        code: 'local_preview',
        message: 'User-initiated local HTML preview is allowed.',
      );

  const BrowserNavigationDecision.allowMediatedProxy()
    : this._(
        allowed: true,
        code: 'mediated_proxy',
        message: 'Loopback proxy navigation is allowed.',
      );

  const BrowserNavigationDecision.mediatePinnedProxy()
    : this._(
        allowed: false,
        code: 'mediate_pinned_proxy',
        message:
            'External browser navigation is loaded through a pinned loopback proxy.',
      );

  const BrowserNavigationDecision.deny(this.code, this.message)
    : allowed = false;

  final bool allowed;
  final String code;
  final String message;

  bool get shouldMediate => code == 'mediate_pinned_proxy';
}

class BrowserSaveTarget {
  const BrowserSaveTarget({
    required this.directory,
    required this.requestedFilename,
    required this.filename,
    required this.format,
    required this.requestedDestination,
    required this.destination,
  });

  final Directory directory;
  final String requestedFilename;
  final String filename;
  final String format;
  final String requestedDestination;
  final BrowserSaveDestination destination;

  String get path => '${directory.path}${Platform.pathSeparator}$filename';

  bool get filenameChanged => requestedFilename.trim() != filename;

  bool get destinationChanged {
    final requested = requestedDestination.trim();
    return requested.isNotEmpty && requested != destination.toolValue;
  }

  Map<String, dynamic> toJson() => {
    'directory': directory.path,
    'destination': destination.toolValue,
    'requestedDestination': requestedDestination,
    'destinationChanged': destinationChanged,
    'requestedFilename': requestedFilename,
    'filename': filename,
    'filenameChanged': filenameChanged,
    'path': path,
    'format': format,
  };
}

enum BrowserSaveDestination {
  app('app', 'Caverno application storage'),
  downloads('downloads', 'Downloads folder'),
  documents('documents', 'Documents folder');

  const BrowserSaveDestination(this.toolValue, this.label);

  final String toolValue;
  final String label;

  static BrowserSaveDestination fromToolArgument(String? value) {
    final normalized = (value ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[-_\s]+'),
      '',
    );
    return switch (normalized) {
      'download' || 'downloads' => BrowserSaveDestination.downloads,
      'document' || 'documents' => BrowserSaveDestination.documents,
      _ => BrowserSaveDestination.app,
    };
  }
}

class _ResolvedBrowserSaveDirectory {
  const _ResolvedBrowserSaveDirectory({
    required this.directory,
    required this.destination,
  });

  final Directory directory;
  final BrowserSaveDestination destination;
}

class BrowserSessionService extends ChangeNotifier {
  BrowserSessionService({
    Directory? saveDirectoryOverride,
    EgressDestinationPolicy destinationPolicy = const EgressDestinationPolicy(),
    BrowserPinnedHttpClient? pinnedHttpClient,
    Future<HttpServer> Function(InternetAddress address, int port)? proxyBind,
  }) : _saveDirectoryOverride = saveDirectoryOverride,
       _destinationPolicy = destinationPolicy,
       _pinnedHttpClient =
           pinnedHttpClient ??
           BrowserPinnedHttpClient(destinationPolicy: destinationPolicy),
       _proxyBind = proxyBind;

  InAppWebViewController? _controller;
  Completer<InAppWebViewController>? _controllerReady;
  Completer<void>? _loadCompleter;
  final Directory? _saveDirectoryOverride;
  final EgressDestinationPolicy _destinationPolicy;
  final BrowserPinnedHttpClient _pinnedHttpClient;
  final Future<HttpServer> Function(InternetAddress address, int port)?
  _proxyBind;
  BrowserMediationProxy? _mediationProxy;
  String? _inFlightReroute;

  bool _enabled = false;
  bool _isPanelOpen = false;
  bool _isLoading = false;
  String? _currentUrl;
  String? _pageTitle;
  String? _lastError;
  bool _canGoBack = false;
  bool _canGoForward = false;
  Uri? _localPreviewOrigin;

  /// Default cap on elements returned by [snapshot] to keep results compact.
  static const int _defaultSnapshotElements = 80;

  /// flutter_inappwebview supports these platforms; Linux is unsupported.
  static bool get isPlatformSupported =>
      Platform.isIOS ||
      Platform.isAndroid ||
      Platform.isMacOS ||
      Platform.isWindows;

  /// Whether the feature can be used right now (platform supported AND enabled
  /// in settings). Gates tool registration and execution.
  bool get isAvailable => isPlatformSupported && _enabled;

  bool get isPanelOpen => _isPanelOpen;
  bool get isLoading => _isLoading;
  String? get currentUrl => _currentUrl;
  String? get pageTitle => _pageTitle;
  String? get lastError => _lastError;
  bool get canGoBack => _canGoBack;
  bool get canGoForward => _canGoForward;

  /// Whether the on-screen pane should mount. Agent browser tools still
  /// require [isAvailable]; a user-started HTML preview can show the pane
  /// even when those tools are disabled.
  bool get shouldShowPanel =>
      _isPanelOpen &&
      isPlatformSupported &&
      (_enabled || _localPreviewOrigin != null);

  Uri? get localPreviewOrigin => _localPreviewOrigin;

  @visibleForTesting
  void armLocalPreviewOriginForTest(Uri url) {
    _localPreviewOrigin = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: url.hasPort ? url.port : 80,
    );
  }

  @visibleForTesting
  Future<Uri> startMediationProxyForTest({Uri? upstream}) async {
    final proxy = await _ensureMediationProxy();
    return proxy.proxyUrlFor(
      upstream ?? Uri.parse('https://example.com/app.js'),
    );
  }

  @visibleForTesting
  String displayUrlForTest(String raw) => _displayUrlFor(raw);

  @visibleForTesting
  Completer<void> createLoadWaitForTest() {
    final completer = Completer<void>();
    _loadCompleter = completer;
    return completer;
  }

  @visibleForTesting
  Completer<void>? get loadCompleterForTest => _loadCompleter;

  @visibleForTesting
  void armLoadCompleterForTest() => _armLoadCompleter();

  /// Pushed in from the settings listener without recreating this singleton.
  void updateEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      // Tear down the session so a disabled feature holds no live page.
      _isPanelOpen = false;
      _localPreviewOrigin = null;
      unawaited(_stopMediationProxy());
      _resetController();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Panel <-> service wiring (called by the browser panel widget).
  // ---------------------------------------------------------------------------

  void attachController(InAppWebViewController controller) {
    _controller = controller;
    final ready = _controllerReady;
    if (ready != null && !ready.isCompleted) {
      ready.complete(controller);
    }
    // If we reopened onto a known URL, restore it.
    if (_currentUrl != null) {
      final loadUrl = _webviewUrlFor(_currentUrl!);
      if (loadUrl != null) {
        controller.loadUrl(urlRequest: URLRequest(url: WebUri(loadUrl)));
      }
    }
  }

  void detachController(InAppWebViewController controller) {
    if (identical(_controller, controller)) {
      _resetController();
    }
  }

  void handleLoadStart(String? url) {
    _isLoading = true;
    if (url != null && url.isNotEmpty) _currentUrl = _displayUrlFor(url);
    _lastError = null;
    notifyListeners();
  }

  Future<void> handleLoadStop(String? url) async {
    _isLoading = false;
    if (url != null && url.isNotEmpty) _currentUrl = _displayUrlFor(url);
    await _refreshNavState();
    final completer = _loadCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    notifyListeners();
  }

  void handleTitleChanged(String? title) {
    _pageTitle = title;
    notifyListeners();
  }

  void handleError(String message) {
    _isLoading = false;
    _lastError = message;
    final completer = _loadCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    notifyListeners();
  }

  BrowserNavigationDecision navigationDecision(
    String? rawUrl, {
    bool allowInternalBlank = false,
  }) {
    final normalized = rawUrl?.trim() ?? '';
    if (normalized == 'about:blank') {
      return allowInternalBlank
          ? const BrowserNavigationDecision.allowInternalBlank()
          : const BrowserNavigationDecision.deny(
              'unsafe_scheme',
              'Only HTTP and HTTPS destinations are allowed.',
            );
    }
    if (normalized.isEmpty) {
      return const BrowserNavigationDecision.deny(
        'invalid_url',
        'A non-empty URL is required.',
      );
    }
    final Uri parsed;
    try {
      parsed = Uri.parse(normalized);
    } on FormatException {
      return const BrowserNavigationDecision.deny(
        'invalid_url',
        'The browser destination URL is invalid.',
      );
    }
    if (_isAllowedLocalPreview(parsed)) {
      return const BrowserNavigationDecision.allowLocalPreview();
    }
    if (_isAllowedMediationProxy(parsed)) {
      return const BrowserNavigationDecision.allowMediatedProxy();
    }
    try {
      _destinationPolicy.validateUri(parsed);
    } on EgressPolicyException catch (error) {
      return BrowserNavigationDecision.deny(error.code, error.message);
    }
    if (_localPreviewOrigin != null) {
      return const BrowserNavigationDecision.deny(
        'browser_peer_verification_unavailable',
        'External browser navigation is disabled until the connected peer can be verified.',
      );
    }
    if (_enabled) {
      return const BrowserNavigationDecision.mediatePinnedProxy();
    }
    return const BrowserNavigationDecision.deny(
      'browser_peer_verification_unavailable',
      'External browser navigation is disabled until the connected peer can be verified.',
    );
  }

  /// Restricts WebView resource loads to the active preview origin.
  ///
  /// The preview server and CSP are the primary cross-platform boundary. This
  /// policy is defense in depth on platforms that report subresource requests.
  bool allowsResourceRequest(String? rawUrl) {
    final normalized = rawUrl?.trim() ?? '';
    if (normalized.isEmpty) return false;
    final Uri parsed;
    try {
      parsed = Uri.parse(normalized);
    } on FormatException {
      return false;
    }
    if (parsed.scheme == 'data' || parsed.scheme == 'blob') return true;
    if (normalized == 'about:blank') return true;
    return _isAllowedLocalPreview(parsed) || _isAllowedMediationProxy(parsed);
  }

  void handleBlockedNavigation(BrowserNavigationDecision decision) {
    _isLoading = false;
    _lastError = decision.message;
    final completer = _loadCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Panel visibility.
  // ---------------------------------------------------------------------------

  void open() {
    if (_isPanelOpen) return;
    _isPanelOpen = true;
    notifyListeners();
  }

  String closePanel() {
    final hadPreview = _localPreviewOrigin != null;
    _localPreviewOrigin = null;
    unawaited(_stopMediationProxy());
    if (_isPanelOpen) {
      _isPanelOpen = false;
      // The webview unmounts when the pane closes, disposing its controller;
      // drop the now-stale reference so a later browser_open re-arms readiness.
      _resetController();
      notifyListeners();
    } else if (hadPreview) {
      notifyListeners();
    }
    return jsonEncode({'ok': true, 'closed': true});
  }

  /// Opens the built-in browser onto a loopback HTML preview started by the
  /// user from the companion panel. Not a tool action: agent `browser_open`
  /// still cannot choose this origin until a preview is already running.
  Future<void> openLocalPreview(
    Uri url, {
    Duration readyTimeout = const Duration(seconds: 12),
  }) async {
    if (!isPlatformSupported) {
      throw const BrowserUnavailableException();
    }
    if (!_isLoopbackHttp(url)) {
      throw ArgumentError.value(
        url,
        'url',
        'Local preview URLs must be loopback HTTP.',
      );
    }
    await _stopMediationProxy();
    _localPreviewOrigin = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: url.hasPort ? url.port : 80,
    );
    _currentUrl = url.toString();
    _lastError = null;
    open();
    try {
      final controller = await _ensureReady(
        timeout: readyTimeout,
        requireEnabled: false,
      );
      _loadCompleter = Completer<void>();
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(url.toString())),
      );
      await _waitForLoad();
    } catch (_) {
      _localPreviewOrigin = null;
      if (!_enabled) {
        closePanel();
      } else {
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Drops the preview origin and closes the pane.
  Future<void> clearLocalPreview() async {
    closePanel();
  }

  /// Reloads the user-started HTML preview without requiring browser tools.
  Future<void> reloadLocalPreview() async {
    if (_localPreviewOrigin == null) return;
    final controller = _controller;
    if (controller == null) return;
    _loadCompleter = Completer<void>();
    await controller.reload();
    await _waitForLoad();
  }

  // ---------------------------------------------------------------------------
  // Tool actions. Each returns a JSON string payload for the tool result.
  // ---------------------------------------------------------------------------

  Future<String> openUrl(String url) async {
    final normalized = _normalizeUrl(url);
    if (normalized.isEmpty) {
      return _error('invalid_url', 'A non-empty url is required');
    }
    final decision = navigationDecision(normalized);
    if (decision.shouldMediate || _agentShouldMediate(normalized, decision)) {
      return _openMediatedUrl(normalized);
    }
    if (!decision.allowed) {
      return _refusal(decision.code, decision.message);
    }
    return _guard('browser_open', () async {
      open();
      final controller = await _ensureReady();
      _currentUrl = normalized;
      _loadCompleter = Completer<void>();
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));
      await _waitForLoad();
      final title = await controller.getTitle();
      _pageTitle = title;
      return jsonEncode({
        'ok': true,
        'requestedUrl': normalized,
        'url':
            _toolReportedUrl((await controller.getUrl())?.toString()) ??
            normalized,
        'title': title ?? '',
        'nextAction':
            'Call browser_snapshot to list interactive elements before acting.',
      });
    });
  }

  Future<String> _openMediatedUrl(String normalized) async {
    final parsed = Uri.parse(normalized);
    try {
      await _pinnedHttpClient.approve(parsed);
    } on EgressPolicyException catch (error) {
      return _error(error.code, error.message);
    } catch (error) {
      return _error('browser_error', error.toString());
    }
    return _guard('browser_open', () async {
      _localPreviewOrigin = null;
      final proxy = await _ensureMediationProxy();
      final loadUrl = await proxy.proxyUrlFor(parsed);
      _currentUrl = normalized;
      open();
      final controller = await _ensureReady();
      _loadCompleter = Completer<void>();
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(loadUrl.toString())),
      );
      await _waitForLoad();
      final title = await controller.getTitle();
      _pageTitle = title;
      return jsonEncode({
        'ok': true,
        'requestedUrl': normalized,
        'url': _currentUrl ?? normalized,
        'title': title ?? '',
        'nextAction':
            'Call browser_snapshot to list interactive elements before acting.',
      });
    });
  }

  /// Cancels a direct public navigation and reloads it through the proxy.
  void rerouteMediatedNavigation(String rawUrl) {
    unawaited(_rerouteMediatedNavigation(rawUrl));
  }

  Future<String> snapshot({int? maxElements}) async {
    final cap = (maxElements == null || maxElements <= 0)
        ? _defaultSnapshotElements
        : maxElements;
    return _guard('browser_snapshot', () async {
      final raw = await _runJs(_snapshotScript(cap));
      final decoded = _decodeJsResult(raw);
      if (decoded is Map) {
        return jsonEncode(_rewriteSnapshotPayload(decoded));
      }
      return jsonEncode({'ok': true, 'raw': decoded});
    });
  }

  Future<String> getContent({String format = 'text', int? maxChars}) async {
    final limit = (maxChars == null || maxChars <= 0) ? 100000 : maxChars;
    return _guard('browser_get_content', () async {
      final controller = await _ensureReady();
      String content;
      if (format == 'html') {
        content = (await controller.getHtml()) ?? '';
      } else {
        final raw = await _runJs(
          '(function(){return JSON.stringify({t:document.body?document.body.innerText:""});})()',
        );
        final decoded = _decodeJsResult(raw);
        content = (decoded is Map ? decoded['t'] as String? : null) ?? '';
      }
      final truncated = content.length > limit;
      return jsonEncode({
        'ok': true,
        'format': format,
        'url': _currentUrl,
        'title': _pageTitle,
        'truncated': truncated,
        'length': content.length,
        'content': truncated ? content.substring(0, limit) : content,
      });
    });
  }

  Future<String> fillField({
    int? ref,
    String? selector,
    required String value,
  }) async {
    if (ref == null && (selector == null || selector.isEmpty)) {
      return _error('missing_target', 'Provide either ref or selector');
    }
    return _guard('browser_fill', () async {
      final expr = _resolveExpr(ref: ref, selector: selector);
      final raw = await _runJs(_fillScript(expr, value));
      return _jsonOrError(raw);
    });
  }

  Future<String> clickElement({int? ref, String? selector}) async {
    if (ref == null && (selector == null || selector.isEmpty)) {
      return _error('missing_target', 'Provide either ref or selector');
    }
    return _guard('browser_click', () async {
      final controller = await _ensureReady();
      final expr = _resolveExpr(ref: ref, selector: selector);
      final beforeUrl = _toolReportedUrl(
        (await controller.getUrl())?.toString(),
      );
      final beforeTitle = await controller.getTitle();
      _armLoadCompleter();
      final raw = await _runJs(_clickScript(expr));
      // A click may trigger navigation; give it a short window to settle.
      await _waitForLoad(timeout: const Duration(seconds: 8));
      final afterUrl = _toolReportedUrl(
        (await controller.getUrl())?.toString(),
      );
      final afterTitle = await controller.getTitle();
      final decoded = _decodeJsResult(raw);
      if (decoded is Map) {
        final result = Map<String, dynamic>.from(decoded);
        final href = result['href'];
        if (href is String) {
          result['href'] = _displayUrlFor(href);
        }
        result['beforeUrl'] = beforeUrl;
        result['beforeTitle'] = beforeTitle ?? '';
        result['url'] = afterUrl;
        result['title'] = afterTitle ?? _pageTitle ?? '';
        result['navigated'] =
            beforeUrl != null && afterUrl != null && beforeUrl != afterUrl;
        return jsonEncode(result);
      }
      return jsonEncode({
        'ok': true,
        'result': decoded,
        'beforeUrl': beforeUrl,
        'beforeTitle': beforeTitle ?? '',
        'url': afterUrl,
        'title': afterTitle ?? _pageTitle ?? '',
        'navigated':
            beforeUrl != null && afterUrl != null && beforeUrl != afterUrl,
      });
    });
  }

  Future<String> submitForm({String? selector}) async {
    return _guard('browser_submit', () async {
      final expr = (selector == null || selector.isEmpty)
          ? 'null'
          : _resolveExpr(selector: selector);
      _armLoadCompleter();
      final raw = await _runJs(_submitScript(expr));
      await _waitForLoad(timeout: const Duration(seconds: 12));
      final result = _decodeJsResult(raw);
      final url = _toolReportedUrl((await _controller?.getUrl())?.toString());
      if (result is Map) {
        result['url'] = url;
        return jsonEncode(result);
      }
      return jsonEncode({'ok': true, 'url': url});
    });
  }

  Future<String> evaluateJs(String script) async {
    if (script.trim().isEmpty) {
      return _error('empty_script', 'A non-empty script is required');
    }
    return _guard('browser_eval', () async {
      // Wrap so the caller's last expression becomes the JSON return value.
      final wrapped =
          '(function(){try{var __r=(function(){$script})();'
          'return JSON.stringify({ok:true,result:(__r===undefined?null:__r)});}'
          'catch(e){return JSON.stringify({ok:false,error:String(e)});}})()';
      final raw = await _runJs(wrapped);
      return _jsonOrError(raw);
    });
  }

  Future<String> screenshot() async {
    return _guard('browser_screenshot', () async {
      final controller = await _ensureReady();
      final bytes = await controller.takeScreenshot();
      if (bytes == null) {
        return _error('screenshot_failed', 'Could not capture the page');
      }
      return jsonEncode({
        'ok': true,
        'url': _currentUrl,
        'title': _pageTitle,
        'imageMimeType': 'image/png',
        'imageBase64': base64Encode(bytes),
      });
    });
  }

  Future<String> waitFor({String? selector, int? timeoutMs}) async {
    final timeout = Duration(milliseconds: (timeoutMs ?? 8000).clamp(0, 60000));
    return _guard('browser_wait', () async {
      if (selector == null || selector.isEmpty) {
        await _waitForLoad(timeout: timeout);
        return jsonEncode({'ok': true, 'waited': 'load', 'url': _currentUrl});
      }
      final deadline = DateTime.now().add(timeout);
      final enc = jsonEncode(selector);
      while (DateTime.now().isBefore(deadline)) {
        final raw = await _runJs(
          '(function(){return JSON.stringify({found:!!document.querySelector($enc)});})()',
        );
        final decoded = _decodeJsResult(raw);
        if (decoded is Map && decoded['found'] == true) {
          return jsonEncode({'ok': true, 'found': true, 'selector': selector});
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return jsonEncode({'ok': false, 'found': false, 'selector': selector});
    });
  }

  Future<String> navigateHistory(String direction) async {
    final decision = navigationDecision(_currentUrl, allowInternalBlank: true);
    if (!decision.allowed && !decision.shouldMediate) {
      return _refusal(decision.code, decision.message);
    }
    return _guard('browser_navigate_history', () async {
      final controller = await _ensureReady(
        requireEnabled: _localPreviewOrigin == null,
      );
      _loadCompleter = Completer<void>();
      switch (direction) {
        case 'back':
          if (!await controller.canGoBack()) {
            return _error('cannot_go_back', 'No back history');
          }
          await controller.goBack();
        case 'forward':
          if (!await controller.canGoForward()) {
            return _error('cannot_go_forward', 'No forward history');
          }
          await controller.goForward();
        case 'reload':
          await controller.reload();
        default:
          return _error(
            'invalid_direction',
            'direction must be back, forward, or reload',
          );
      }
      await _waitForLoad();
      return jsonEncode({
        'ok': true,
        'direction': direction,
        'url': _currentUrl,
      });
    });
  }

  Future<String> saveData({
    required String filename,
    required String data,
    String format = 'json',
    String? destination,
  }) async {
    return _guard('browser_save_data', () async {
      final target = await resolveSaveTarget(
        filename: filename,
        format: format,
        destination: destination,
      );
      await target.directory.create(recursive: true);
      final file = File(target.path);
      await file.writeAsString(data);
      return jsonEncode({
        'ok': true,
        'path': file.absolute.path,
        'directory': target.directory.path,
        'destination': target.destination.toolValue,
        'requestedDestination': target.requestedDestination,
        'destinationChanged': target.destinationChanged,
        'filename': target.filename,
        'requestedFilename': target.requestedFilename,
        'filenameChanged': target.filenameChanged,
        'bytes': utf8.encode(data).length,
        'format': target.format,
      });
    });
  }

  Future<BrowserSaveTarget> resolveSaveTarget({
    required String filename,
    String format = 'json',
    String? destination,
  }) async {
    final destinationArgument = destination?.trim();
    final requestedDestination = BrowserSaveDestination.fromToolArgument(
      destinationArgument,
    );
    final resolvedDirectory = await _saveDirectory(requestedDestination);
    final safeFormat = _safeFormat(format);
    return BrowserSaveTarget(
      directory: resolvedDirectory.directory,
      requestedFilename: filename,
      filename: _safeFileName(filename, safeFormat),
      format: safeFormat,
      requestedDestination:
          destinationArgument != null && destinationArgument.isNotEmpty
          ? destinationArgument
          : requestedDestination.toolValue,
      destination: resolvedDirectory.destination,
    );
  }

  // ---------------------------------------------------------------------------
  // Internals.
  // ---------------------------------------------------------------------------

  Future<InAppWebViewController> _ensureReady({
    Duration timeout = const Duration(seconds: 12),
    bool requireEnabled = true,
  }) async {
    if (!isPlatformSupported) throw const BrowserUnavailableException();
    if (requireEnabled && !_enabled) {
      throw const BrowserUnavailableException();
    }
    final existing = _controller;
    if (existing != null) return existing;
    if (!_isPanelOpen) open();
    final ready = _controllerReady ??= Completer<InAppWebViewController>();
    try {
      return await ready.future.timeout(timeout);
    } on TimeoutException {
      throw const BrowserNotReadyException();
    }
  }

  Future<dynamic> _runJs(String source) async {
    final controller = await _ensureReady();
    return controller.evaluateJavascript(source: source);
  }

  Future<void> _waitForLoad({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = _loadCompleter;
    if (completer == null || completer.isCompleted) return;
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      // Proceed even if the page is slow; it may already be usable.
    }
  }

  /// Reuses an in-flight load waiter so a click/submit that is rerouted
  /// through the mediation proxy still observes the replacement navigation.
  void _armLoadCompleter() {
    final existing = _loadCompleter;
    if (existing != null && !existing.isCompleted) return;
    _loadCompleter = Completer<void>();
  }

  Future<void> _refreshNavState() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      _canGoBack = await controller.canGoBack();
      _canGoForward = await controller.canGoForward();
    } catch (_) {
      // Best-effort; navigation buttons just stay in their last state.
    }
  }

  void _resetController() {
    _controller = null;
    _controllerReady = null;
    _isLoading = false;
    _canGoBack = false;
    _canGoForward = false;
  }

  /// Runs an action with uniform error handling, returning a JSON envelope.
  Future<String> _guard(String tool, Future<String> Function() body) async {
    try {
      return await body();
    } on BrowserUnavailableException {
      return _error(
        'unsupported_platform',
        'The built-in browser is unavailable on this platform or disabled.',
      );
    } on BrowserNotReadyException {
      return _error(
        'browser_not_ready',
        'The browser panel did not finish opening. Try browser_open first.',
      );
    } catch (error) {
      appLog('[BrowserSessionService] $tool error: $error');
      return _error('browser_error', error.toString());
    }
  }

  String _error(String code, String message) =>
      jsonEncode({'ok': false, 'code': code, 'error': message});

  /// A navigation the destination policy refused, as opposed to a browser that
  /// failed.
  ///
  /// Both used to render through [_error], so `browser_error` (the WebView
  /// threw) and `browser_peer_verification_unavailable` (the policy said no)
  /// were the same shape to every reader downstream. Only the second is a
  /// refusal, and only refusals belong in a "the turn tried and was stopped"
  /// count. See ToolResultOrigin.
  String _refusal(String code, String message) => jsonEncode({
    'ok': false,
    'code': code,
    ...ToolResultOrigin.refusal.marker,
    'error': message,
  });

  /// Returns the decoded JSON when the JS payload already carries `ok`,
  /// otherwise wraps it as a success envelope.
  String _jsonOrError(dynamic raw) {
    final decoded = _decodeJsResult(raw);
    if (decoded is Map) return jsonEncode(decoded);
    return jsonEncode({'ok': true, 'result': decoded});
  }

  dynamic _decodeJsResult(dynamic raw) {
    if (raw is String) {
      if (raw.isEmpty) return null;
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  String _resolveExpr({int? ref, String? selector}) {
    if (ref != null) {
      return 'document.querySelector(\'[data-caverno-ref="$ref"]\')';
    }
    final enc = jsonEncode(selector ?? '');
    return 'document.querySelector($enc)';
  }

  String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return trimmed;
    return 'https://$trimmed';
  }

  bool _isLoopbackHttp(Uri url) {
    if (url.scheme.toLowerCase() != 'http') return false;
    if (url.userInfo.isNotEmpty) return false;
    if (!_isLoopbackHost(url.host)) return false;
    return url.hasPort && url.port > 0 && url.port <= 65535;
  }

  bool _isAllowedLocalPreview(Uri url) {
    final origin = _localPreviewOrigin;
    if (origin == null) return false;
    if (!_isLoopbackHttp(url)) return false;
    return url.port == origin.port;
  }

  bool _isAllowedMediationProxy(Uri url) {
    return _mediationProxy?.isProxyUrl(url) ?? false;
  }

  /// [browser_open] may take over a preview session; WebView clicks may not.
  bool _agentShouldMediate(
    String normalized,
    BrowserNavigationDecision decision,
  ) {
    if (!_enabled || decision.allowed) return false;
    if (decision.code != 'browser_peer_verification_unavailable') {
      return false;
    }
    try {
      _destinationPolicy.validateUri(Uri.parse(normalized));
      return true;
    } on EgressPolicyException {
      return false;
    }
  }

  Future<BrowserMediationProxy> _ensureMediationProxy() async {
    final existing = _mediationProxy;
    if (existing != null && !existing.isStopped) return existing;
    final proxy = BrowserMediationProxy(
      httpClient: _pinnedHttpClient,
      bind: _proxyBind,
    );
    _mediationProxy = proxy;
    return proxy;
  }

  Future<void> _stopMediationProxy() async {
    final proxy = _mediationProxy;
    _mediationProxy = null;
    if (proxy != null) {
      await proxy.stop();
    }
  }

  String? _toolReportedUrl(String? webviewUrl) {
    final raw = (webviewUrl == null || webviewUrl.isEmpty)
        ? _currentUrl
        : webviewUrl;
    if (raw == null || raw.isEmpty) return raw;
    return _displayUrlFor(raw);
  }

  String _displayUrlFor(String raw) {
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) return raw;
    final proxy = _mediationProxy;
    if (proxy == null) return raw;
    if (parsed.host.isEmpty) {
      final current = _currentUrl;
      if (current == null || current.isEmpty) return raw;
      return Uri.parse(current).resolveUri(parsed).toString();
    }
    return proxy.targetFromProxyUrl(parsed)?.toString() ?? raw;
  }

  String? _webviewUrlFor(String displayUrl) {
    final decision = navigationDecision(displayUrl, allowInternalBlank: true);
    if (decision.allowed) return displayUrl;
    if (!decision.shouldMediate) return null;
    final parsed = Uri.tryParse(_normalizeUrl(displayUrl));
    if (parsed == null) return null;
    return _mediationProxy?.proxyUrlForSync(parsed)?.toString();
  }

  Future<void> _rerouteMediatedNavigation(String rawUrl) async {
    final normalized = _normalizeUrl(rawUrl);
    if (normalized.isEmpty) return;
    if (_inFlightReroute == normalized) return;
    _inFlightReroute = normalized;
    try {
      await _pinnedHttpClient.approve(Uri.parse(normalized));
      _localPreviewOrigin = null;
      final proxy = await _ensureMediationProxy();
      final loadUrl = await proxy.proxyUrlFor(Uri.parse(normalized));
      _currentUrl = normalized;
      open();
      final controller = await _ensureReady();
      _armLoadCompleter();
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(loadUrl.toString())),
      );
    } on EgressPolicyException catch (error) {
      handleBlockedNavigation(
        BrowserNavigationDecision.deny(error.code, error.message),
      );
    } catch (error) {
      handleError(error.toString());
    } finally {
      if (_inFlightReroute == normalized) {
        _inFlightReroute = null;
      }
    }
  }

  Map<String, dynamic> _rewriteSnapshotPayload(Map<dynamic, dynamic> decoded) {
    final result = Map<String, dynamic>.from(decoded);
    final url = result['url'];
    if (url is String) {
      result['url'] = _displayUrlFor(url);
    }
    final elements = result['elements'];
    if (elements is List) {
      result['elements'] = [
        for (final element in elements)
          if (element is Map) _rewriteSnapshotElement(element) else element,
      ];
    }
    return result;
  }

  Map<String, dynamic> _rewriteSnapshotElement(Map<dynamic, dynamic> element) {
    final result = Map<String, dynamic>.from(element);
    final href = result['href'];
    if (href is String) {
      result['href'] = _displayUrlFor(href);
    }
    return result;
  }

  static bool _isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == '127.0.0.1' || normalized == 'localhost';
  }

  Future<_ResolvedBrowserSaveDirectory> _saveDirectory(
    BrowserSaveDestination destination,
  ) async {
    final override = _saveDirectoryOverride;
    if (override != null) {
      return _ResolvedBrowserSaveDirectory(
        directory: override,
        destination: destination,
      );
    }
    return switch (destination) {
      BrowserSaveDestination.app => _appManagedSaveDirectory(),
      BrowserSaveDestination.documents => _documentsSaveDirectory(),
      BrowserSaveDestination.downloads => _downloadsSaveDirectory(),
    };
  }

  Future<_ResolvedBrowserSaveDirectory> _appManagedSaveDirectory() async {
    final support = await getApplicationSupportDirectory();
    return _ResolvedBrowserSaveDirectory(
      directory: Directory(
        '${support.path}${Platform.pathSeparator}browser-saves',
      ),
      destination: BrowserSaveDestination.app,
    );
  }

  Future<_ResolvedBrowserSaveDirectory> _documentsSaveDirectory() async {
    return _ResolvedBrowserSaveDirectory(
      directory: await getApplicationDocumentsDirectory(),
      destination: BrowserSaveDestination.documents,
    );
  }

  Future<_ResolvedBrowserSaveDirectory> _downloadsSaveDirectory() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return _ResolvedBrowserSaveDirectory(
          directory: downloads,
          destination: BrowserSaveDestination.downloads,
        );
      }
    }
    return _appManagedSaveDirectory();
  }

  String _safeFileName(String filename, String format) {
    var name = filename.trim().isEmpty ? 'browser_data' : filename.trim();
    name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F/\\:*?"<>|]+'), '_');
    name = name.replaceAll(RegExp(r'_+'), '_');
    name = name.trim();
    name = name.replaceAll(RegExp(r'^[._]+'), '');
    name = name.replaceAll(RegExp(r'[.\s]+$'), '');
    if (name.isEmpty) {
      name = 'browser_data';
    }
    if (!_hasCompatibleExtension(name, format)) {
      name = '$name.${_fileExtensionForFormat(format)}';
    }
    return name;
  }

  bool _hasCompatibleExtension(String filename, String format) {
    final lowerName = filename.toLowerCase();
    final extensions = switch (format) {
      'md' || 'markdown' => const ['.md', '.markdown'],
      'txt' || 'text' => const ['.txt', '.text'],
      _ => ['.${_fileExtensionForFormat(format)}'],
    };
    return extensions.any(lowerName.endsWith);
  }

  String _fileExtensionForFormat(String format) {
    return switch (format) {
      'markdown' => 'md',
      'text' => 'txt',
      _ => format,
    };
  }

  String _safeFormat(String format) {
    final cleaned = format
        .trim()
        .replaceFirst(RegExp(r'^[.]+'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '')
        .toLowerCase();
    return cleaned.isEmpty ? 'json' : cleaned;
  }

  // ---- Injected JavaScript ----

  String _snapshotScript(int maxElements) {
    return '''
(function(maxElements){
  function isVisible(el){
    var r = el.getBoundingClientRect();
    var s = window.getComputedStyle(el);
    return r.width>0 && r.height>0 && s.visibility!=='hidden' && s.display!=='none' && s.opacity!=='0';
  }
  function labelFor(el){
    var l = el.getAttribute('aria-label');
    if(l) return l.trim();
    if(el.id){ try { var lab = document.querySelector('label[for="'+CSS.escape(el.id)+'"]'); if(lab) return lab.innerText.trim(); } catch(e){} }
    var wrap = el.closest ? el.closest('label') : null; if(wrap) return wrap.innerText.trim();
    if(el.placeholder) return el.placeholder.trim();
    if(el.name) return el.name.trim();
    return ((el.innerText||el.value||'')+'').trim().slice(0,120);
  }
  var sel='a[href],button,input,select,textarea,[role=button],[role=link],[onclick],[contenteditable=""],[contenteditable=true]';
  var nodes=Array.prototype.slice.call(document.querySelectorAll(sel));
  var out=[]; var i=0;
  for(var n=0;n<nodes.length;n++){
    var el=nodes[n];
    if(out.length>=maxElements) break;
    if(!isVisible(el)) continue;
    el.setAttribute('data-caverno-ref', String(i));
    var tag=el.tagName.toLowerCase();
    var type=(el.getAttribute('type')||'').toLowerCase();
    var value=null;
    if(tag==='input'||tag==='textarea'||tag==='select'){
      if(type==='password'){ value='•'.repeat((el.value||'').length); }
      else { value=((el.value||'')+'').slice(0,120); }
    }
    var r=el.getBoundingClientRect();
    out.push({
      ref:i, tag:tag, type:type||null,
      name:el.getAttribute('name')||null,
      id:el.id||null,
      role:el.getAttribute('role')||null,
      label:labelFor(el),
      placeholder:el.getAttribute('placeholder')||null,
      href: tag==='a'? el.getAttribute('href') : null,
      value:value,
      bbox:{x:Math.round(r.x),y:Math.round(r.y),w:Math.round(r.width),h:Math.round(r.height)}
    });
    i++;
  }
  return JSON.stringify({ok:true, url:location.href, title:document.title, count:out.length, elements:out});
})($maxElements)
''';
  }

  String _fillScript(String expr, String value) {
    final enc = jsonEncode(value);
    return '''
(function(){
  var el = $expr;
  if(!el) return JSON.stringify({ok:false,code:'element_not_found',error:'No element matched'});
  var tag = el.tagName.toLowerCase();
  var type = (el.getAttribute('type') || '').toLowerCase();
  var isFillable = tag === 'input' || tag === 'textarea' || tag === 'select' || el.isContentEditable;
  if(!isFillable){
    return JSON.stringify({
      ok:false,
      code:'element_not_fillable',
      error:'Matched element is not a fillable field',
      tag:tag,
      text:((el.innerText||'')+'').trim().slice(0,80)
    });
  }
  el.focus();
  if(el.isContentEditable){
    el.textContent = $enc;
  } else {
    var proto = tag==='textarea'
      ? window.HTMLTextAreaElement.prototype
      : tag==='select'
        ? window.HTMLSelectElement.prototype
        : window.HTMLInputElement.prototype;
    var desc = Object.getOwnPropertyDescriptor(proto,'value');
    if(desc && desc.set){ desc.set.call(el, $enc); } else { el.value = $enc; }
  }
  el.dispatchEvent(new Event('input',{bubbles:true}));
  el.dispatchEvent(new Event('change',{bubbles:true}));
  var redacted = type==='password';
  return JSON.stringify({ok:true, tag:tag, type:type||null, name:el.getAttribute('name')||null, valueRedacted:redacted});
})()
''';
  }

  String _clickScript(String expr) {
    return '''
(function(){
  function labelFor(el){
    var l = el.getAttribute('aria-label');
    if(l) return l.trim();
    if(el.id){ try { var lab = document.querySelector('label[for="'+CSS.escape(el.id)+'"]'); if(lab) return lab.innerText.trim(); } catch(e){} }
    var wrap = el.closest ? el.closest('label') : null; if(wrap) return wrap.innerText.trim();
    if(el.placeholder) return el.placeholder.trim();
    if(el.name) return el.name.trim();
    return ((el.innerText||el.value||'')+'').trim().slice(0,120);
  }
  var el = $expr;
  if(!el) return JSON.stringify({ok:false,code:'element_not_found',error:'No element matched'});
  if(el.scrollIntoView) el.scrollIntoView({block:'center'});
  var tag = el.tagName.toLowerCase();
  var type = (el.getAttribute('type') || '').toLowerCase();
  var target = {
    tag: tag,
    type: type || null,
    name: el.getAttribute('name') || null,
    id: el.id || null,
    role: el.getAttribute('role') || null,
    label: labelFor(el),
    href: tag === 'a' ? el.getAttribute('href') : null,
    text: ((el.innerText||'')+'').trim().slice(0,80)
  };
  el.click();
  return JSON.stringify(Object.assign({ok:true}, target));
})()
''';
  }

  @visibleForTesting
  String buildClickScriptForTest(String expression) => _clickScript(expression);

  String _submitScript(String expr) {
    return '''
(function(){
  var el = $expr;
  var form = el ? (el.closest ? (el.closest('form')||el) : el) : document.querySelector('form');
  if(!form) return JSON.stringify({ok:false,code:'no_form',error:'No form found'});
  if(form.requestSubmit){ form.requestSubmit(); } else if(form.submit){ form.submit(); } else { return JSON.stringify({ok:false,code:'no_form',error:'Element is not a form'}); }
  return JSON.stringify({ok:true});
})()
''';
  }

  @override
  void dispose() {
    unawaited(_stopMediationProxy());
    _resetController();
    super.dispose();
  }
}
