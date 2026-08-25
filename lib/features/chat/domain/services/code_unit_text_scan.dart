/// Matches literal code-unit sequences in model output.
///
/// Japanese markers are written as code units rather than as source literals
/// so the repository's English-only rule holds for the code itself; the cost
/// is that a plain `contains` no longer reads the text, hence this scan.
abstract final class CodeUnitTextScan {
  /// Whether [text] contains any of [sequences].
  static bool containsAny(String text, List<List<int>> sequences) {
    return sequences.any((sequence) => contains(text, sequence));
  }

  /// Whether [text] contains [sequence] as consecutive UTF-16 code units.
  static bool contains(String text, List<int> sequence) {
    if (sequence.isEmpty || text.length < sequence.length) {
      return false;
    }
    final units = text.codeUnits;
    for (var index = 0; index <= units.length - sequence.length; index++) {
      var matched = true;
      for (var offset = 0; offset < sequence.length; offset++) {
        if (units[index + offset] != sequence[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return true;
      }
    }
    return false;
  }
}
