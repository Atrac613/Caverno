/// Recognizes package availability and identity queries, never pytest execution.
abstract final class PytestMetadataInspectionPolicy {
  static bool applies(List<String> args) =>
      args.length == 2 &&
      args.first == '-c' &&
      RegExp(
        r'^import\s+pytest\s*;\s*print\(\s*'
        r'''(?:(?:'pytest'|"pytest")\s*,\s*)?'''
        r'pytest\.(?:__file__|__version__)\s*\)\s*$',
      ).hasMatch(args.last.trim());
}
