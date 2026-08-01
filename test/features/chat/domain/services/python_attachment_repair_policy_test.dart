import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/python_attachment_repair_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const _policy = PythonAttachmentRepairPolicy();

PythonAttachmentRepairInput _input({
  String candidateResponse = 'I will inspect the attachment.',
  List<ToolResultInfo> executedResults = const <ToolResultInfo>[],
  Set<String> availableToolNames = const {'run_python_script'},
  bool runPythonScriptDisabled = false,
  bool hasPythonAttachment = true,
  String owningTurnLatestUserText =
      'Use run_python_script to analyze the metadata.',
}) {
  return PythonAttachmentRepairInput(
    candidateResponse: candidateResponse,
    executedResults: executedResults,
    availableToolNames: availableToolNames,
    runPythonScriptDisabled: runPythonScriptDisabled,
    hasPythonAttachment: hasPythonAttachment,
    owningTurnLatestUserText: owningTurnLatestUserText,
  );
}

ToolResultInfo _result({
  String name = 'run_python_script',
  String result = '{"stdout":"ok"}',
}) {
  return ToolResultInfo(
    id: 'tool-result',
    name: name,
    arguments: const {},
    result: result,
  );
}

void main() {
  group('PythonAttachmentRepairInput', () {
    test('freezes executed results and available tool names', () {
      final sourceResults = <ToolResultInfo>[];
      final sourceToolNames = <String>{'run_python_script'};
      final input = _input(
        executedResults: sourceResults,
        availableToolNames: sourceToolNames,
      );

      sourceResults.add(_result());
      sourceToolNames.clear();

      expect(input.executedResults, isEmpty);
      expect(input.availableToolNames, {'run_python_script'});
      expect(
        () => input.executedResults.add(_result()),
        throwsUnsupportedError,
      );
      expect(
        () => input.availableToolNames.add('other_tool'),
        throwsUnsupportedError,
      );
    });
  });

  group('skipped Python attachment analysis', () {
    test('repairs an eligible English analysis request', () {
      expect(
        _policy.shouldRepairSkippedPythonAttachmentAnalysis(_input()),
        isTrue,
      );
    });

    test('rejects empty candidate content', () {
      expect(
        _policy.shouldRepairSkippedPythonAttachmentAnalysis(
          _input(candidateResponse: '  '),
        ),
        isFalse,
      );
    });

    test('rejects a disabled or unavailable Python tool', () {
      expect(
        _policy.shouldRepairSkippedPythonAttachmentAnalysis(
          _input(runPythonScriptDisabled: true),
        ),
        isFalse,
      );
      expect(
        _policy.shouldRepairSkippedPythonAttachmentAnalysis(
          _input(availableToolNames: const {'tool_search'}),
        ),
        isFalse,
      );
    });

    test('rejects a missing attachment', () {
      expect(
        _policy.shouldRepairSkippedPythonAttachmentAnalysis(
          _input(hasPythonAttachment: false),
        ),
        isFalse,
      );
    });

    test('rejects prior Python execution', () {
      expect(
        _policy.shouldRepairSkippedPythonAttachmentAnalysis(
          _input(executedResults: [_result(name: ' RUN_PYTHON_SCRIPT ')]),
        ),
        isFalse,
      );
      expect(
        _policy.hasRunPythonScriptToolResult([_result(name: 'read_file')]),
        isFalse,
      );
    });

    test('rejects empty and unrelated owning-turn requests', () {
      for (final text in [
        '',
        'Use Python for this task.',
        'Inspect the attachment metadata.',
        'Please summarize the photo.',
      ]) {
        expect(
          _policy.shouldRepairSkippedPythonAttachmentAnalysis(
            _input(owningTurnLatestUserText: text),
          ),
          isFalse,
          reason: text,
        );
      }
    });

    test('accepts English analysis marker variants', () {
      for (final marker in [
        'metadata',
        'exif',
        'analyze',
        'analyse',
        'analysis',
        'inspect',
        'parse',
      ]) {
        expect(
          _policy.looksLikePythonAttachmentAnalysisRequest(
            'Use Python to $marker the attachment.',
          ),
          isTrue,
          reason: marker,
        );
      }
      expect(
        _policy.looksLikePythonAttachmentAnalysisRequest(
          'Use RUN_PYTHON_SCRIPT for METADATA.',
        ),
        isTrue,
      );
    });

    test('accepts CJK analysis marker variants with a Python request', () {
      final markers = [
        String.fromCharCodes([0x30e1, 0x30bf, 0x30c7, 0x30fc, 0x30bf]),
        String.fromCharCodes([0x89e3, 0x6790]),
        String.fromCharCodes([0x753b, 0x50cf]),
        String.fromCharCodes([0x5199, 0x771f]),
        String.fromCharCodes([0x6dfb, 0x4ed8]),
      ];

      for (final marker in markers) {
        expect(
          _policy.looksLikePythonAttachmentAnalysisRequest('python $marker'),
          isTrue,
        );
        expect(_policy.containsCjkAnalysisMarker(marker), isTrue);
      }
      expect(_policy.containsCjkAnalysisMarker('plain text'), isFalse);
    });
  });

  group('Python attachment path failure', () {
    test('repairs supported path-failure variants', () {
      for (final failure in [
        'FileNotFoundError: test.jpg',
        'No such file or directory: test.jpg',
        'FILE NOT FOUND: test.jpg',
      ]) {
        final results = [_result(result: failure)];
        expect(_policy.hasRunPythonScriptPathFailure(results), isTrue);
        expect(
          _policy.shouldRepairPythonAttachmentPathFailure(
            _input(executedResults: results),
          ),
          isTrue,
        );
      }
    });

    test('rejects absent, unrelated, and non-Python path failures', () {
      expect(
        _policy.shouldRepairPythonAttachmentPathFailure(_input()),
        isFalse,
      );
      expect(
        _policy.shouldRepairPythonAttachmentPathFailure(
          _input(executedResults: [_result(result: 'ValueError: bad input')]),
        ),
        isFalse,
      );
      expect(
        _policy.hasRunPythonScriptPathFailure([
          _result(name: 'read_file', result: 'FileNotFoundError'),
        ]),
        isFalse,
      );
    });

    test('still requires every shared repair precondition', () {
      final pathFailure = [_result(result: 'FileNotFoundError')];
      for (final input in [
        _input(candidateResponse: '', executedResults: pathFailure),
        _input(executedResults: pathFailure, runPythonScriptDisabled: true),
        _input(executedResults: pathFailure, hasPythonAttachment: false),
        _input(
          executedResults: pathFailure,
          availableToolNames: const {'tool_search'},
        ),
        _input(
          executedResults: pathFailure,
          owningTurnLatestUserText: 'Summarize the response.',
        ),
      ]) {
        expect(_policy.shouldRepairPythonAttachmentPathFailure(input), isFalse);
      }
    });
  });

  group('repair prompts', () {
    test('keeps skipped-analysis prompt byte-compatible', () {
      const expected =
          'The latest user request requires run_python_script to inspect an attached file.\n'
          'A file is already staged for run_python_script as caverno.inputs[0].\n'
          'Do not answer in prose that analysis will happen, and do not claim the attachment is missing.\n'
          'Call run_python_script now with a complete Python script in the code argument.\n'
          'The script should read caverno.inputs[0], print concise metadata findings, and use only the standard library plus piexif when useful.\n'
          'For image metadata, start with `path = caverno.inputs[0].path` and `piexif.load(path)`.\n'
          'When naming EXIF tags, use `piexif.TAGS[ifd][tag].get(\'name\', str(tag))`; TAGS entries are maps.';

      expect(
        PythonAttachmentRepairPolicy.buildSkippedPythonAttachmentAnalysisRepairPrompt(),
        expected,
      );
    });

    test('keeps path-failure prompt byte-compatible', () {
      const expected =
          'The previous run_python_script call failed because it opened a guessed file path such as test.jpg.\n'
          'The latest user request still has an attached file staged for run_python_script as caverno.inputs[0].\n'
          'Do not ask the user to reattach the file or provide a path.\n'
          'Call run_python_script again with a complete Python script that reads caverno.inputs[0].path or caverno.inputs[0].read_bytes().\n'
          'Do not open literal paths such as test.jpg, attachment_0.jpg, or any guessed relative path.\n'
          'For image metadata, prefer `path = caverno.inputs[0].path` followed by `piexif.load(path)`.\n'
          'When naming EXIF tags, use `piexif.TAGS[ifd][tag].get(\'name\', str(tag))`; TAGS entries are maps.\n'
          'Print concise metadata findings from the staged attachment.';

      expect(
        PythonAttachmentRepairPolicy.buildPythonAttachmentPathFailureRepairPrompt(),
        expected,
      );
    });
  });
}
