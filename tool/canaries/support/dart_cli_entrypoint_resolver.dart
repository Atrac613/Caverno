import 'dart:io';

enum DartCliEntrypointPolicy { fixed, singleUnderBin, singleConventional }

enum DartCliEntrypointIssueKind { missing, unexpected, ambiguous }

class DartCliEntrypointIssue {
  const DartCliEntrypointIssue({
    required this.kind,
    required this.relativePath,
    required this.message,
  });

  final DartCliEntrypointIssueKind kind;
  final String relativePath;
  final String message;
}

class DartCliEntrypointResolution {
  const DartCliEntrypointResolution({
    required this.candidates,
    this.selectedRelativePath,
    this.issues = const [],
  });

  final List<String> candidates;
  final String? selectedRelativePath;
  final List<DartCliEntrypointIssue> issues;

  bool get isResolved => selectedRelativePath != null && issues.isEmpty;
}

class DartCliEntrypointResolver {
  const DartCliEntrypointResolver();

  DartCliEntrypointResolution resolve({
    required Directory root,
    required String canonicalRelativePath,
    required DartCliEntrypointPolicy policy,
  }) {
    final canonical = _normalizeRelativePath(canonicalRelativePath);
    final separator = canonical.lastIndexOf('/');
    if (separator <= 0 || separator == canonical.length - 1) {
      throw ArgumentError.value(
        canonicalRelativePath,
        'canonicalRelativePath',
        'Expected a relative file path inside a directory.',
      );
    }

    final entrypointDirectory = Directory(
      '${root.absolute.path}${Platform.pathSeparator}'
      '${canonical.substring(0, separator).replaceAll('/', Platform.pathSeparator)}',
    );
    final binCandidates = _dartFiles(entrypointDirectory, root);
    return switch (policy) {
      DartCliEntrypointPolicy.fixed => _resolveFixed(
        root: root,
        canonical: canonical,
        candidates: binCandidates,
      ),
      DartCliEntrypointPolicy.singleUnderBin => _resolveSingle(
        canonical: canonical,
        candidates: binCandidates,
        locationDescription: 'under bin/',
      ),
      DartCliEntrypointPolicy.singleConventional => _resolveSingle(
        canonical: canonical,
        candidates: _conventionalCandidates(root, binCandidates),
        locationDescription: 'under bin/ or at lib/main.dart or main.dart',
      ),
    };
  }

  DartCliEntrypointResolution _resolveFixed({
    required Directory root,
    required String canonical,
    required List<String> candidates,
  }) {
    final canonicalFile = File(
      '${root.absolute.path}${Platform.pathSeparator}'
      '${canonical.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!canonicalFile.existsSync()) {
      return DartCliEntrypointResolution(
        candidates: candidates,
        issues: [
          DartCliEntrypointIssue(
            kind: DartCliEntrypointIssueKind.missing,
            relativePath: canonical,
            message: '$canonical does not exist.',
          ),
        ],
      );
    }

    final unexpected = candidates
        .where((candidate) => candidate != canonical)
        .map(
          (candidate) => DartCliEntrypointIssue(
            kind: DartCliEntrypointIssueKind.unexpected,
            relativePath: candidate,
            message:
                'Unexpected Dart entrypoint $candidate. Keep only $canonical '
                'and remove this file with delete_file.',
          ),
        )
        .toList(growable: false);
    return DartCliEntrypointResolution(
      candidates: candidates,
      selectedRelativePath: unexpected.isEmpty ? canonical : null,
      issues: unexpected,
    );
  }

  DartCliEntrypointResolution _resolveSingle({
    required String canonical,
    required List<String> candidates,
    required String locationDescription,
  }) {
    if (candidates.isEmpty) {
      return DartCliEntrypointResolution(
        candidates: candidates,
        issues: [
          DartCliEntrypointIssue(
            kind: DartCliEntrypointIssueKind.missing,
            relativePath: canonical,
            message:
                'No Dart entrypoint exists $locationDescription. Create '
                'exactly one conventional Dart CLI entrypoint, for example '
                '$canonical.',
          ),
        ],
      );
    }
    if (candidates.length == 1) {
      return DartCliEntrypointResolution(
        candidates: candidates,
        selectedRelativePath: candidates.single,
      );
    }

    return DartCliEntrypointResolution(
      candidates: candidates,
      issues: [
        DartCliEntrypointIssue(
          kind: DartCliEntrypointIssueKind.ambiguous,
          relativePath: candidates.first,
          message:
              'Multiple Dart entrypoints exist $locationDescription: '
              '${candidates.join(', ')}. Keep exactly one and rerun the '
              'verifier.',
        ),
      ],
    );
  }

  List<String> _conventionalCandidates(
    Directory root,
    List<String> binCandidates,
  ) {
    final candidates = <String>{...binCandidates};
    for (final path in const <String>['lib/main.dart', 'main.dart']) {
      final file = File(
        '${root.absolute.path}${Platform.pathSeparator}'
        '${path.replaceAll('/', Platform.pathSeparator)}',
      );
      if (file.existsSync()) {
        candidates.add(path);
      }
    }
    return candidates.toList(growable: false)..sort();
  }

  List<String> _dartFiles(Directory directory, Directory root) {
    if (!directory.existsSync()) return const [];
    final rootPrefix = '${root.absolute.path}${Platform.pathSeparator}';
    final candidates =
        directory
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .map((file) {
              final absolutePath = file.absolute.path;
              if (!absolutePath.startsWith(rootPrefix)) {
                throw StateError(
                  'Entrypoint candidate must stay inside ${root.absolute.path}.',
                );
              }
              return absolutePath
                  .substring(rootPrefix.length)
                  .replaceAll(Platform.pathSeparator, '/');
            })
            .toList(growable: false)
          ..sort();
    return candidates;
  }

  String _normalizeRelativePath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.contains('/../')) {
      throw ArgumentError.value(
        value,
        'canonicalRelativePath',
        'Expected a safe workspace-relative path.',
      );
    }
    return normalized;
  }
}
