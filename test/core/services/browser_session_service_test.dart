import 'dart:io';

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
  });
}
