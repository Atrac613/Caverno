import 'dart:io';

import 'short_prompt_contract_builder.dart';

// ChatNotifier decomposition collaborator: referenced-specification-loader

/// Narrow filesystem boundary used by [ReferencedSpecificationLoader].
abstract interface class SpecificationFilePort {
  bool exists(String path);

  int length(String path);

  String readAsString(String path);
}

/// Synchronous local-filesystem implementation of [SpecificationFilePort].
final class LocalSpecificationFilePort implements SpecificationFilePort {
  const LocalSpecificationFilePort();

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  int length(String path) => File(path).lengthSync();

  @override
  String readAsString(String path) => File(path).readAsStringSync();
}

/// Loads the first bounded Markdown specification referenced by a request.
final class ReferencedSpecificationLoader {
  const ReferencedSpecificationLoader({
    SpecificationFilePort filePort = const LocalSpecificationFilePort(),
  }) : _filePort = filePort;

  final SpecificationFilePort _filePort;

  SpecificationContractInput? load({
    required String projectRoot,
    required String request,
    int maxBytes = 262144,
  }) {
    final normalizedProjectRoot = projectRoot.trim();
    if (normalizedProjectRoot.isEmpty) return null;
    final match = RegExp(
      r'''(?:^|[\s"'`(])([^\s"'`()]+\.md)\b''',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(request);
    final reference = match?.group(1)?.trim() ?? '';
    if (reference.isEmpty) return null;
    if (File(reference).isAbsolute) return null;
    final normalizedRoot = Uri.file(
      Directory(normalizedProjectRoot).absolute.path,
    ).normalizePath().toFilePath();
    final candidate = Uri.file(
      File('$normalizedRoot${Platform.pathSeparator}$reference').absolute.path,
    ).normalizePath().toFilePath();
    if (!candidate.startsWith('$normalizedRoot${Platform.pathSeparator}')) {
      return null;
    }
    if (!_filePort.exists(candidate) ||
        _filePort.length(candidate) > maxBytes) {
      return null;
    }
    try {
      return SpecificationContractInput(
        path: reference,
        content: _filePort.readAsString(candidate),
      );
    } on FileSystemException {
      return null;
    }
  }
}
