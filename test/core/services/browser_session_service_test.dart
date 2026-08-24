import 'dart:io';
import 'dart:convert';

import 'package:caverno/core/services/browser_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserSessionService', () {
    test('preserves Unicode filenames when resolving save targets', () async {
      final directory = Directory.systemTemp.createTempSync(
        'browser_save_target_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final service = BrowserSessionService(saveDirectoryOverride: directory);

      final target = await service.resolveSaveTarget(
        filename: 'アジサイ_概要.md',
        format: 'md',
      );

      expect(target.directory.path, directory.path);
      expect(target.destination, BrowserSaveDestination.app);
      expect(target.destinationChanged, isFalse);
      expect(target.filename, 'アジサイ_概要.md');
      expect(target.filenameChanged, isFalse);
      expect(
        target.path,
        '${directory.path}${Platform.pathSeparator}アジサイ_概要.md',
      );
    });

    test('preserves Markdown filenames when format uses long name', () async {
      final directory = Directory.systemTemp.createTempSync(
        'browser_save_target_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final service = BrowserSessionService(saveDirectoryOverride: directory);

      final target = await service.resolveSaveTarget(
        filename: 'アジサイ_概要.md',
        format: 'markdown',
      );

      expect(target.format, 'markdown');
      expect(target.filename, 'アジサイ_概要.md');
      expect(target.filenameChanged, isFalse);
    });

    test('uses md extension for Markdown format without extension', () async {
      final directory = Directory.systemTemp.createTempSync(
        'browser_save_target_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final service = BrowserSessionService(saveDirectoryOverride: directory);

      final target = await service.resolveSaveTarget(
        filename: 'summary',
        format: 'markdown',
      );

      expect(target.format, 'markdown');
      expect(target.filename, 'summary.md');
    });

    test('removes path separators while keeping readable text', () async {
      final directory = Directory.systemTemp.createTempSync(
        'browser_save_target_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final service = BrowserSessionService(saveDirectoryOverride: directory);

      final target = await service.resolveSaveTarget(
        filename: '../アジサイ:概要',
        format: '.md',
      );

      expect(target.filename, 'アジサイ_概要.md');
      expect(target.filenameChanged, isTrue);
      expect(target.path, isNot(contains('..')));
      expect(target.path, isNot(contains(':')));
    });

    test('keeps explicit save destinations in resolved metadata', () async {
      final directory = Directory.systemTemp.createTempSync(
        'browser_save_target_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final service = BrowserSessionService(saveDirectoryOverride: directory);

      final target = await service.resolveSaveTarget(
        filename: 'report',
        format: 'json',
        destination: 'downloads',
      );

      expect(target.destination, BrowserSaveDestination.downloads);
      expect(target.requestedDestination, 'downloads');
      expect(target.destinationChanged, isFalse);
      expect(target.toJson(), containsPair('destination', 'downloads'));
    });

    test('falls back to app storage for unknown destinations', () async {
      final directory = Directory.systemTemp.createTempSync(
        'browser_save_target_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final service = BrowserSessionService(saveDirectoryOverride: directory);

      final target = await service.resolveSaveTarget(
        filename: 'report',
        destination: 'desktop',
      );

      expect(target.destination, BrowserSaveDestination.app);
      expect(target.requestedDestination, 'desktop');
      expect(target.destinationChanged, isTrue);
    });

    test('creates the save directory before writing data', () async {
      final root = Directory.systemTemp.createTempSync('browser_save_root_');
      addTearDown(() => root.deleteSync(recursive: true));
      final saveDirectory = Directory(
        '${root.path}${Platform.pathSeparator}nested',
      );
      final service = BrowserSessionService(
        saveDirectoryOverride: saveDirectory,
      );

      await service.saveData(
        filename: 'summary',
        data: '# Summary',
        format: 'md',
      );

      final savedFile = File(
        '${saveDirectory.path}${Platform.pathSeparator}summary.md',
      );
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.readAsStringSync(), '# Summary');
    });

    test('click script returns target metadata for result grounding', () {
      final service = BrowserSessionService();

      final script = service.buildClickScriptForTest('document.body');

      expect(script, contains('labelFor(el)'));
      expect(script, contains('role: el.getAttribute'));
      expect(script, contains('href: tag ==='));
      expect(script, contains('label: labelFor(el)'));
      expect(script, contains('Object.assign({ok:true}, target)'));
    });

    test('allows only the internal blank-page navigation', () {
      final service = BrowserSessionService();

      final decision = service.navigationDecision(
        'about:blank',
        allowInternalBlank: true,
      );

      expect(decision.allowed, isTrue);
      expect(decision.code, 'internal_blank');
    });

    test('rejects unsafe schemes through the shared destination policy', () {
      final service = BrowserSessionService();

      for (final url in [
        'file:///etc/passwd',
        'data:text/plain,secret',
        'javascript:alert(1)',
        'about:blank',
      ]) {
        final decision = service.navigationDecision(url);
        expect(decision.allowed, isFalse, reason: url);
        expect(decision.code, 'unsafe_scheme', reason: url);
      }
    });

    test('keeps public WebView navigation closed without peer evidence', () {
      final service = BrowserSessionService();

      final decision = service.navigationDecision('https://example.com/');

      expect(decision.allowed, isFalse);
      expect(decision.code, 'browser_peer_verification_unavailable');
    });

    test('allows only the active loopback HTML preview origin', () {
      final service = BrowserSessionService();
      final preview = Uri.parse('http://127.0.0.1:4321/index.html');
      service.armLocalPreviewOriginForTest(preview);

      final allowed = service.navigationDecision(preview.toString());
      expect(allowed.allowed, isTrue);
      expect(allowed.code, 'local_preview');
      expect(
        service.navigationDecision('http://127.0.0.1:4321/other.html').allowed,
        isTrue,
      );
      expect(
        service.navigationDecision('http://127.0.0.1:9999/index.html').allowed,
        isFalse,
      );
      expect(
        service.navigationDecision('https://example.com/').allowed,
        isFalse,
      );
      expect(service.navigationDecision('file:///etc/passwd').allowed, isFalse);
    });

    test('allows preview subresources but rejects every external origin', () {
      final service = BrowserSessionService();
      service.armLocalPreviewOriginForTest(
        Uri.parse('http://127.0.0.1:4321/index.html'),
      );

      expect(
        service.allowsResourceRequest('http://127.0.0.1:4321/app.js'),
        isTrue,
      );
      expect(
        service.allowsResourceRequest('data:image/png;base64,AA=='),
        isTrue,
      );
      expect(service.allowsResourceRequest('blob:http://127.0.0.1/id'), isTrue);
      for (final url in [
        'https://example.com/collect',
        'http://127.0.0.1:9999/collect',
        'file:///etc/passwd',
        'javascript:alert(1)',
        '',
      ]) {
        expect(service.allowsResourceRequest(url), isFalse, reason: url);
      }
    });

    test(
      'browser_open fails before mounting a WebView or resolving DNS',
      () async {
        final service = BrowserSessionService();

        final result = jsonDecode(await service.openUrl('example.com'));

        expect(result, containsPair('ok', false));
        expect(
          result,
          containsPair('code', 'browser_peer_verification_unavailable'),
        );
        expect(service.isPanelOpen, isFalse);
      },
    );
  });
}
