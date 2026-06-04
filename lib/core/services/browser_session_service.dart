import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

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
  BrowserSessionService({Directory? saveDirectoryOverride})
    : _saveDirectoryOverride = saveDirectoryOverride;

  InAppWebViewController? _controller;
  Completer<InAppWebViewController>? _controllerReady;
  Completer<void>? _loadCompleter;
  final Directory? _saveDirectoryOverride;

  bool _enabled = false;
  bool _isPanelOpen = false;
  bool _isLoading = false;
  String? _currentUrl;
  String? _pageTitle;
  String? _lastError;
  bool _canGoBack = false;
  bool _canGoForward = false;

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

  /// Pushed in from the settings listener without recreating this singleton.
  void updateEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      // Tear down the session so a disabled feature holds no live page.
      _isPanelOpen = false;
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
      controller.loadUrl(urlRequest: URLRequest(url: WebUri(_currentUrl!)));
    }
  }

  void detachController(InAppWebViewController controller) {
    if (identical(_controller, controller)) {
      _resetController();
    }
  }

  void handleLoadStart(String? url) {
    _isLoading = true;
    if (url != null && url.isNotEmpty) _currentUrl = url;
    _lastError = null;
    notifyListeners();
  }

  Future<void> handleLoadStop(String? url) async {
    _isLoading = false;
    if (url != null && url.isNotEmpty) _currentUrl = url;
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

  // ---------------------------------------------------------------------------
  // Panel visibility.
  // ---------------------------------------------------------------------------

  void open() {
    if (_isPanelOpen) return;
    _isPanelOpen = true;
    notifyListeners();
  }

  String closePanel() {
    if (_isPanelOpen) {
      _isPanelOpen = false;
      // The webview unmounts when the pane closes, disposing its controller;
      // drop the now-stale reference so a later browser_open re-arms readiness.
      _resetController();
      notifyListeners();
    }
    return jsonEncode({'ok': true, 'closed': true});
  }

  // ---------------------------------------------------------------------------
  // Tool actions. Each returns a JSON string payload for the tool result.
  // ---------------------------------------------------------------------------

  Future<String> openUrl(String url) async {
    final normalized = _normalizeUrl(url);
    if (normalized.isEmpty) {
      return _error('invalid_url', 'A non-empty url is required');
    }
    return _guard('browser_open', () async {
      open();
      final controller = await _ensureReady();
      _currentUrl = normalized;
      _loadCompleter = Completer<void>();
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));
      await _waitForLoad();
      final title = await controller.getTitle();
      final current = await controller.getUrl();
      _pageTitle = title;
      return jsonEncode({
        'ok': true,
        'requestedUrl': normalized,
        'url': current?.toString() ?? normalized,
        'title': title ?? '',
        'nextAction':
            'Call browser_snapshot to list interactive elements before acting.',
      });
    });
  }

  Future<String> snapshot({int? maxElements}) async {
    final cap = (maxElements == null || maxElements <= 0)
        ? _defaultSnapshotElements
        : maxElements;
    return _guard('browser_snapshot', () async {
      final raw = await _runJs(_snapshotScript(cap));
      final decoded = _decodeJsResult(raw);
      if (decoded is Map) return jsonEncode(decoded);
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
      final beforeUrl = (await controller.getUrl())?.toString() ?? _currentUrl;
      final beforeTitle = await controller.getTitle();
      _loadCompleter = Completer<void>();
      final raw = await _runJs(_clickScript(expr));
      // A click may trigger navigation; give it a short window to settle.
      await _waitForLoad(timeout: const Duration(seconds: 8));
      final afterUrl = (await controller.getUrl())?.toString() ?? _currentUrl;
      final afterTitle = await controller.getTitle();
      final decoded = _decodeJsResult(raw);
      if (decoded is Map) {
        final result = Map<String, dynamic>.from(decoded);
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
      _loadCompleter = Completer<void>();
      final raw = await _runJs(_submitScript(expr));
      await _waitForLoad(timeout: const Duration(seconds: 12));
      final result = _decodeJsResult(raw);
      final url = await _controller?.getUrl();
      if (result is Map) {
        result['url'] = url?.toString() ?? _currentUrl;
        return jsonEncode(result);
      }
      return jsonEncode({'ok': true, 'url': url?.toString() ?? _currentUrl});
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
    return _guard('browser_navigate_history', () async {
      final controller = await _ensureReady();
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
  }) async {
    if (!isAvailable) throw const BrowserUnavailableException();
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
    if (trimmed.contains('://')) return trimmed;
    if (trimmed.startsWith('about:') || trimmed.startsWith('data:')) {
      return trimmed;
    }
    return 'https://$trimmed';
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
    _resetController();
    super.dispose();
  }
}
