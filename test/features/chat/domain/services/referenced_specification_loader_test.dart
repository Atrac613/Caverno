import 'dart:io';

import 'package:caverno/features/chat/domain/services/referenced_specification_loader.dart';
import 'package:test/test.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'caverno_referenced_specification_',
    );
  });

  tearDown(() {
    if (projectRoot.existsSync()) {
      projectRoot.deleteSync(recursive: true);
    }
  });

  test('loads the first relative Markdown reference', () {
    final specification = File(
      '${projectRoot.path}${Platform.pathSeparator}docs'
      '${Platform.pathSeparator}requirements.md',
    );
    specification.parent.createSync(recursive: true);
    specification.writeAsStringSync('# Requirements\n\n- Persist tasks.\n');

    final result = const ReferencedSpecificationLoader().load(
      projectRoot: ' ${projectRoot.path} ',
      request: 'Read docs/requirements.md before optional.md.',
    );

    expect(result, isNotNull);
    expect(result!.path, 'docs/requirements.md');
    expect(result.content, '# Requirements\n\n- Persist tasks.\n');
  });

  test('rejects traversal and absolute outside-root references', () {
    final outsideFile = File(
      '${projectRoot.parent.path}${Platform.pathSeparator}'
      '${projectRoot.uri.pathSegments.last}outside.md',
    )..writeAsStringSync('# Outside\n');
    final absolutePathCollision = File(
      '${projectRoot.path}${outsideFile.path}',
    );
    absolutePathCollision.parent.createSync(recursive: true);
    absolutePathCollision.writeAsStringSync('# Inside collision\n');
    addTearDown(() {
      if (outsideFile.existsSync()) {
        outsideFile.deleteSync();
      }
    });
    final loader = const ReferencedSpecificationLoader();

    expect(
      loader.load(
        projectRoot: projectRoot.path,
        request: 'Read ../${outsideFile.uri.pathSegments.last}.',
      ),
      isNull,
    );
    expect(
      loader.load(
        projectRoot: projectRoot.path,
        request: 'Read ${outsideFile.path}.',
      ),
      isNull,
    );
  });

  test(
    'checks existence, length, and read in order for only the first match',
    () {
      final port = _RecordingSpecificationFilePort();
      final result = ReferencedSpecificationLoader(filePort: port).load(
        projectRoot: projectRoot.path,
        request: 'Read first.md before second.md.',
      );

      expect(result?.path, 'first.md');
      expect(result?.content, '# Specification\n');
      expect(port.calls, [
        'exists:first.md',
        'length:first.md',
        'read:first.md',
      ]);
    },
  );

  test('short-circuits before length or read when the file is absent', () {
    final port = _RecordingSpecificationFilePort(existsResult: false);

    expect(
      ReferencedSpecificationLoader(
        filePort: port,
      ).load(projectRoot: projectRoot.path, request: 'Read missing.md.'),
      isNull,
    );
    expect(port.calls, ['exists:missing.md']);
  });

  test('returns null for empty roots and malformed references', () {
    final loader = const ReferencedSpecificationLoader();

    expect(
      loader.load(projectRoot: ' ', request: 'Read requirements.md.'),
      isNull,
    );
    expect(
      loader.load(projectRoot: projectRoot.path, request: 'Read requirements.'),
      isNull,
    );
    expect(loader.load(projectRoot: projectRoot.path, request: ''), isNull);
  });

  test('returns null for missing files and Markdown directories', () {
    final markdownDirectory = Directory(
      '${projectRoot.path}${Platform.pathSeparator}directory.md',
    )..createSync();
    final loader = const ReferencedSpecificationLoader();

    expect(
      loader.load(projectRoot: projectRoot.path, request: 'Read missing.md.'),
      isNull,
    );
    expect(
      loader.load(
        projectRoot: projectRoot.path,
        request: 'Read ${markdownDirectory.uri.pathSegments.last}.',
      ),
      isNull,
    );
  });

  test('rejects files larger than the default byte limit', () {
    File(
      '${projectRoot.path}${Platform.pathSeparator}oversize.md',
    ).writeAsBytesSync(List<int>.filled(262145, 0x61));

    expect(
      const ReferencedSpecificationLoader().load(
        projectRoot: projectRoot.path,
        request: 'Read oversize.md.',
      ),
      isNull,
    );
  });

  test('allows a file exactly at a custom byte limit', () {
    File(
      '${projectRoot.path}${Platform.pathSeparator}boundary.md',
    ).writeAsStringSync('four');

    final result = const ReferencedSpecificationLoader().load(
      projectRoot: projectRoot.path,
      request: 'Read boundary.md.',
      maxBytes: 4,
    );

    expect(result?.content, 'four');
  });

  test('loads Unicode Markdown paths', () {
    const unicodeName = '\u4ed5\u69d8\u66f8.md';
    File(
      '${projectRoot.path}${Platform.pathSeparator}$unicodeName',
    ).writeAsStringSync('# Unicode path\n');

    final result = const ReferencedSpecificationLoader().load(
      projectRoot: projectRoot.path,
      request: 'Read $unicodeName.',
    );

    expect(result?.path, unicodeName);
    expect(result?.content, '# Unicode path\n');
  });

  test('returns null when reading the file throws', () {
    final loader = ReferencedSpecificationLoader(
      filePort: _FailingSpecificationFilePort(readFails: true),
    );

    expect(
      loader.load(
        projectRoot: projectRoot.path,
        request: 'Read unreadable.md.',
      ),
      isNull,
    );
  });

  test('preserves length failures outside the read catch', () {
    final loader = ReferencedSpecificationLoader(
      filePort: _FailingSpecificationFilePort(lengthFails: true),
    );

    expect(
      () => loader.load(
        projectRoot: projectRoot.path,
        request: 'Read inaccessible.md.',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('preserves existence failures outside the read catch', () {
    final loader = ReferencedSpecificationLoader(
      filePort: _FailingSpecificationFilePort(existsFails: true),
    );

    expect(
      () => loader.load(
        projectRoot: projectRoot.path,
        request: 'Read inaccessible.md.',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}

final class _FailingSpecificationFilePort implements SpecificationFilePort {
  const _FailingSpecificationFilePort({
    this.existsFails = false,
    this.lengthFails = false,
    this.readFails = false,
  });

  final bool existsFails;
  final bool lengthFails;
  final bool readFails;

  @override
  bool exists(String path) {
    if (existsFails) {
      throw FileSystemException('Existence check failed.', path);
    }
    return true;
  }

  @override
  int length(String path) {
    if (lengthFails) {
      throw FileSystemException('Length failed.', path);
    }
    return 1;
  }

  @override
  String readAsString(String path) {
    if (readFails) {
      throw FileSystemException('Read failed.', path);
    }
    return '# Specification\n';
  }
}

final class _RecordingSpecificationFilePort implements SpecificationFilePort {
  _RecordingSpecificationFilePort({this.existsResult = true});

  final bool existsResult;
  final List<String> calls = [];

  String _name(String path) => Uri.file(path).pathSegments.last;

  @override
  bool exists(String path) {
    calls.add('exists:${_name(path)}');
    return existsResult;
  }

  @override
  int length(String path) {
    calls.add('length:${_name(path)}');
    return 1;
  }

  @override
  String readAsString(String path) {
    calls.add('read:${_name(path)}');
    return '# Specification\n';
  }
}
