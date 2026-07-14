class StructuredCodingExecutionDeferralDetector {
  const StructuredCodingExecutionDeferralDetector();

  static final RegExp _planningMarker = RegExp(
    r'^(?:#{1,6}\s*)?(?:\d+[.)]\s*)?(?:\*{0,2})?'
    r'(?:next chunk|next implementation step|what i need to '
    r'(?:verify|inspect|check))\s*:?(?:\*{0,2})?\s*$|'
    r'^(?:#{1,6}\s*)?(?:\d+[.)]\s*)?(?:\*{0,2})?'
    r'(?:\u5b9f\u884c\u8a08\u753b|'
    r'\u6b21\u306e\u5b9f\u88c5\u30b9\u30c6\u30c3\u30d7|'
    r'\u78ba\u8a8d\u4e8b\u9805)\s*:?(?:\*{0,2})?\s*$',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _concreteActionLine = RegExp(
    r'^\s*(?:(?:[-*]|\d+[.)])\s*)?'
    r'(?:read|inspect|check|verify|list|search|implement|create|write|edit|'
    r'update|fix|run|test)\b|'
    r'^\s*(?:#{1,6}\s*)?(?:(?:[-*]|\d+[.)])\s*)?.{0,160}'
    r'(?:\u8aad\u3080|\u78ba\u8a8d|\u8abf\u67fb|'
    r'\u521d\u671f\u5316|\u5b9f\u88c5|\u4f5c\u6210|'
    r'\u7de8\u96c6|\u66f4\u65b0|\u4fee\u6b63|'
    r'\u691c\u8a3c|\u30c6\u30b9\u30c8|\u5b9f\u884c).{0,40}$',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _codingTarget = RegExp(
    r'''(?:\b(?:code|source|file|project|dart|python|script|entrypoint|implementation|test|diagnostic)\b|(?:^|[\s`"'(])[^\s`"'()]+\.(?:dart|py|md|json|ya?ml|toml)\b)''',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _blocker = RegExp(
    r'\b(?:cannot|can not|unable|blocked|need your|please provide|'
    r'not enough information)\b|'
    r'(?:\u3067\u304d\u307e\u305b\u3093|\u4e0d\u53ef\u80fd|'
    r'\u30d6\u30ed\u30c3\u30af|\u63d0\u4f9b\u3057\u3066\u304f\u3060\u3055\u3044|'
    r'\u60c5\u5831\u304c\u4e0d\u8db3)',
    caseSensitive: false,
  );

  bool matches(String content) {
    final candidate = content.trim();
    if (candidate.isEmpty || candidate.length > 2400) {
      return false;
    }
    if (candidate.endsWith('?') ||
        candidate.endsWith('\u{ff1f}') ||
        _blocker.hasMatch(candidate)) {
      return false;
    }
    return _planningMarker.hasMatch(candidate) &&
        _concreteActionLine.hasMatch(candidate) &&
        _codingTarget.hasMatch(candidate);
  }
}
