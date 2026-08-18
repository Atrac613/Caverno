import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/html_project_detector.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('html_project_detector_');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('prefers a root index.html', () {
    File('${root.path}/about.html').writeAsStringSync('<p>about</p>');
    File('${root.path}/index.html').writeAsStringSync('<p>home</p>');

    final entry = const HtmlProjectDetector().detect(root.path);

    expect(entry, isNotNull);
    expect(entry!.relativePath, 'index.html');
  });

  test('uses the only root html file when index.html is missing', () {
    File('${root.path}/ocean.html').writeAsStringSync('<p>ocean</p>');

    final entry = const HtmlProjectDetector().detect(root.path);

    expect(entry, isNotNull);
    expect(entry!.relativePath, 'ocean.html');
  });

  test('finds public/index.html when the root has no html files', () {
    Directory('${root.path}/public').createSync();
    File('${root.path}/public/index.html').writeAsStringSync('<p>app</p>');

    final entry = const HtmlProjectDetector().detect(root.path);

    expect(entry, isNotNull);
    expect(entry!.relativePath, 'public/index.html');
  });

  test(
    'ignores Flutter packages so web/index.html is not a preview target',
    () {
      File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: demo
environment:
  sdk: ^3.0.0
flutter:
  uses-material-design: true
''');
      Directory('${root.path}/web').createSync();
      File(
        '${root.path}/web/index.html',
      ).writeAsStringSync('<p>flutter web</p>');

      expect(const HtmlProjectDetector().detect(root.path), isNull);
    },
  );

  test('returns null for an empty directory', () {
    expect(const HtmlProjectDetector().detect(root.path), isNull);
  });

  test('does not auto-pick when several root html files exist', () {
    File('${root.path}/about.html').writeAsStringSync('<p>about</p>');
    File('${root.path}/ocean.html').writeAsStringSync('<p>ocean</p>');

    const detector = HtmlProjectDetector();
    expect(detector.preferredEntry(root.path), isNull);
    expect(detector.listEntries(root.path).map((entry) => entry.relativePath), [
      'about.html',
      'ocean.html',
    ]);
    expect(detector.detect(root.path)?.relativePath, 'about.html');
  });
}
