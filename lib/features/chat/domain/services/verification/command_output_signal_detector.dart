/// Interprets failure signals in output, independently of invocation metadata.
class CommandOutputSignalDetector {
  const CommandOutputSignalDetector();
  static final RegExp _markdownErrorHeadingPattern = RegExp(
    r'^\s*#{1,6}\s+error\b',
    caseSensitive: false,
  );
  static final RegExp _tracebackPattern = RegExp(
    r'traceback\s+\(most recent call last\)',
    caseSensitive: false,
  );
  static final RegExp _runtimeFailurePattern = RegExp(
    r'\b(?:uncaught exception|unhandled exception|fatal exception|assertionerror:)\b|'
    r'^(?:(?:.*[/\\])?python(?:\d+(?:\.\d+)*)?(?:\.exe)?|ModuleNotFoundError):'
    r'\s+No module named\b|'
    r'^={2,}\s*(?:\d+\s+\w+,\s*)*[1-9]\d*\s+failed\b.*={2,}\s*$',
    caseSensitive: false,
  );
  static final String _cjkErrorLabel = String.fromCharCodes([
    0x30a8,
    0x30e9,
    0x30fc,
  ]);
  static final String _cjkDataMissing = String.fromCharCodes([
    0x30c7,
    0x30fc,
    0x30bf,
    0x304c,
    0x898b,
    0x3064,
    0x304b,
    0x308a,
    0x307e,
    0x305b,
    0x3093,
  ]);

  CommandOutputSignal? detect(String output, {required bool runtimeSignals}) {
    final lines = output.split(RegExp(r'\r?\n'));
    var offset = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        if (_markdownErrorHeadingPattern.hasMatch(trimmed) ||
            _isCjkErrorHeading(trimmed)) {
          return CommandOutputSignal(
            summary: 'Output contains a Markdown error heading.',
            startIndex: offset,
          );
        }

        final normalized = trimmed.toLowerCase();
        if (normalized.contains('no data found') ||
            normalized.contains('data not found') ||
            normalized.contains('could not find data') ||
            normalized.contains('required data was not found') ||
            trimmed.contains(_cjkDataMissing)) {
          return CommandOutputSignal(
            summary: 'Output reports that required data was not found.',
            startIndex: offset,
          );
        }
        if (runtimeSignals &&
            (_tracebackPattern.hasMatch(trimmed) ||
                _runtimeFailurePattern.hasMatch(trimmed))) {
          return CommandOutputSignal(
            summary: 'Output contains a runtime failure signal.',
            startIndex: offset,
          );
        }
      }
      offset += line.length + 1;
    }
    return null;
  }

  bool _isCjkErrorHeading(String line) {
    final withoutHashes = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    return withoutHashes.trim() == _cjkErrorLabel;
  }
}

class CommandOutputSignal {
  const CommandOutputSignal({required this.summary, required this.startIndex});

  final String summary;
  final int startIndex;
}
