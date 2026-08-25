/// Japanese phrases the terminal-response policy looks for.
///
/// Written as code units so the source stays English-only; the cost is that
/// the phrases are unreadable in place, which is exactly why they belong
/// behind named tests rather than inline at the call site.
abstract final class CjkResponseMarkers {
  /// Whether a reply names a blocker the model is asking the user to clear.
  static bool containsBlocker(String value) {
    final markers = [
      String.fromCharCodes([0x5fc5, 0x8981, 0x3067, 0x3059]),
      String.fromCharCodes([0x304a, 0x9858, 0x3044, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([
        0x6559,
        0x3048,
        0x3066,
        0x304f,
        0x3060,
        0x3055,
        0x3044,
      ]),
    ];
    return markers.any(value.contains);
  }

  /// Whether a reply says which evidence it could not reach.
  static bool containsMissingEvidence(String value) {
    final markers = [
      String.fromCharCodes([0x30bd, 0x30fc, 0x30b9, 0x30b3, 0x30fc, 0x30c9]),
      String.fromCharCodes([0x30ea, 0x30dd, 0x30b8, 0x30c8, 0x30ea]),
      String.fromCharCodes([0x30d1, 0x30b9]),
      String.fromCharCodes([0x30a2, 0x30af, 0x30bb, 0x30b9]),
      String.fromCharCodes([0x629c, 0x7c8b]),
    ];
    return markers.any(value.contains);
  }
}
