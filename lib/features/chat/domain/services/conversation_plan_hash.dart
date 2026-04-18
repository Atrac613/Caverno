String computeConversationPlanHash(String markdown) {
  const int offsetBasis = 0x811c9dc5;
  const int prime = 0x01000193;
  var hash = offsetBasis;
  for (final codeUnit in markdown.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * prime) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
