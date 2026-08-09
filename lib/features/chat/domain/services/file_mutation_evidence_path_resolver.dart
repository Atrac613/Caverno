import 'dart:convert';

import '../entities/tool_call_info.dart';

abstract final class FileMutationEvidencePathResolver {
  static String? resultPayloadPath(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) {
        final path = decoded['path'];
        if (path is String && path.trim().isNotEmpty) return path.trim();
      }
    } catch (_) {}
    return null;
  }

  static String? argumentPath(Object? arguments) {
    final rawPath = arguments is Map ? arguments['path'] : null;
    if (rawPath is! String) return null;
    final path = rawPath.trim();
    return path.isEmpty ? null : path;
  }

  static String? pathForResult(ToolResultInfo result) =>
      (result.outcome?.fileMutations.length == 1
          ? result.outcome!.fileMutations.single.path
          : null) ??
      resultPayloadPath(result.result) ??
      argumentPath(result.arguments);
}
