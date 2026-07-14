import 'dart:io';

enum DartCliEntrypointPolicy { fixed, singleUnderBin }

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
    final candidates = _dartFiles(entrypointDirectory, root);
    return switch (policy) {
      DartCliEntrypointPolicy.fixed => _resolveFixed(
        root: root,
        canonical: canonical,
        candidates: candidates,
      ),
      DartCliEntrypointPolicy.singleUnderBin => _resolveSingle(
        canonical: canonical,
        candidates: candidates,
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
  }) {
    if (candidates.isEmpty) {
      return DartCliEntrypointResolution(
        candidates: candidates,
        issues: [
          DartCliEntrypointIssue(
            kind: DartCliEntrypointIssueKind.missing,
            relativePath: canonical,
            message:
                'No Dart entrypoint exists under bin/. Create exactly one Dart '
                'file there, for example $canonical.',
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
              'Multiple Dart entrypoints exist under bin/: '
              '${candidates.join(', ')}. Keep exactly one and rerun the '
              'verifier.',
        ),
      ],
    );
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
