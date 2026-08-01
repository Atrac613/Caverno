import '../entities/tool_call_info.dart';

// ChatNotifier decomposition collaborator: python-attachment-repair-policy

final class PythonAttachmentRepairInput {
  PythonAttachmentRepairInput({
    required this.candidateResponse,
    required List<ToolResultInfo> executedResults,
    required Set<String> availableToolNames,
    required this.runPythonScriptDisabled,
    required this.hasPythonAttachment,
    required this.owningTurnLatestUserText,
  }) : executedResults = List<ToolResultInfo>.unmodifiable(executedResults),
       availableToolNames = Set<String>.unmodifiable(availableToolNames);

  final String candidateResponse;
  final List<ToolResultInfo> executedResults;
  final Set<String> availableToolNames;
  final bool runPythonScriptDisabled;
  final bool hasPythonAttachment;
  final String owningTurnLatestUserText;
}

final class PythonAttachmentRepairPolicy {
  const PythonAttachmentRepairPolicy();

  bool shouldRepairSkippedPythonAttachmentAnalysis(
    PythonAttachmentRepairInput input,
  ) {
    if (!_canRepair(input)) {
      return false;
    }
    return !hasRunPythonScriptToolResult(input.executedResults);
  }

  bool shouldRepairPythonAttachmentPathFailure(
    PythonAttachmentRepairInput input,
  ) {
    if (!_canRepair(input)) {
      return false;
    }
    return hasRunPythonScriptPathFailure(input.executedResults);
  }

  bool _canRepair(PythonAttachmentRepairInput input) {
    if (input.candidateResponse.trim().isEmpty) {
      return false;
    }
    if (input.runPythonScriptDisabled) {
      return false;
    }
    if (!input.hasPythonAttachment) {
      return false;
    }
    if (!input.availableToolNames.contains('run_python_script')) {
      return false;
    }
    return looksLikePythonAttachmentAnalysisRequest(
      input.owningTurnLatestUserText,
    );
  }

  bool hasRunPythonScriptToolResult(List<ToolResultInfo> toolResults) {
    return toolResults.any(
      (toolResult) =>
          toolResult.name.trim().toLowerCase() == 'run_python_script',
    );
  }

  bool looksLikePythonAttachmentAnalysisRequest(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final mentionsPythonTool = _containsAny(normalized, const [
      'run_python_script',
      'python',
    ]);
    final mentionsAnalysis = _containsAny(normalized, const [
      'metadata',
      'exif',
      'analyze',
      'analyse',
      'analysis',
      'inspect',
      'parse',
    ]);
    return mentionsPythonTool &&
        (mentionsAnalysis || containsCjkAnalysisMarker(text));
  }

  bool containsCjkAnalysisMarker(String value) {
    final analysisMarkers = [
      String.fromCharCodes([0x30e1, 0x30bf, 0x30c7, 0x30fc, 0x30bf]),
      String.fromCharCodes([0x89e3, 0x6790]),
      String.fromCharCodes([0x753b, 0x50cf]),
      String.fromCharCodes([0x5199, 0x771f]),
      String.fromCharCodes([0x6dfb, 0x4ed8]),
    ];
    return analysisMarkers.any(value.contains);
  }

  static String buildSkippedPythonAttachmentAnalysisRepairPrompt() {
    return [
      'The latest user request requires run_python_script to inspect an attached file.',
      'A file is already staged for run_python_script as caverno.inputs[0].',
      'Do not answer in prose that analysis will happen, and do not claim the attachment is missing.',
      'Call run_python_script now with a complete Python script in the code argument.',
      'The script should read caverno.inputs[0], print concise metadata findings, and use only the standard library plus piexif when useful.',
      'For image metadata, start with `path = caverno.inputs[0].path` and `piexif.load(path)`.',
      'When naming EXIF tags, use `piexif.TAGS[ifd][tag].get(\'name\', str(tag))`; TAGS entries are maps.',
    ].join('\n');
  }

  bool hasRunPythonScriptPathFailure(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      if (toolResult.name.trim().toLowerCase() != 'run_python_script') {
        return false;
      }
      final normalized = toolResult.result.toLowerCase();
      return _containsAny(normalized, const [
        'filenotfounderror',
        'no such file or directory',
        'file not found',
      ]);
    });
  }

  static String buildPythonAttachmentPathFailureRepairPrompt() {
    return [
      'The previous run_python_script call failed because it opened a guessed file path such as test.jpg.',
      'The latest user request still has an attached file staged for run_python_script as caverno.inputs[0].',
      'Do not ask the user to reattach the file or provide a path.',
      'Call run_python_script again with a complete Python script that reads caverno.inputs[0].path or caverno.inputs[0].read_bytes().',
      'Do not open literal paths such as test.jpg, attachment_0.jpg, or any guessed relative path.',
      'For image metadata, prefer `path = caverno.inputs[0].path` followed by `piexif.load(path)`.',
      'When naming EXIF tags, use `piexif.TAGS[ifd][tag].get(\'name\', str(tag))`; TAGS entries are maps.',
      'Print concise metadata findings from the staged attachment.',
    ].join('\n');
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }
}
