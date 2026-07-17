/// Builds deterministic OpenAI-facing names for remote MCP tools.
///
/// Exact built-in names remain reserved even when their definitions are not
/// currently exposed. Prefix reservations additionally keep remote names out
/// of built-in dispatch and policy namespaces.
class RemoteMcpToolNamePolicy {
  RemoteMcpToolNamePolicy({
    required Set<String> reservedToolNames,
    Set<String> reservedToolNamePrefixes = const {},
  }) : _reservedToolNames = Set.unmodifiable(reservedToolNames),
       _reservedToolNamePrefixes = Set.unmodifiable(
         reservedToolNamePrefixes
             .map((prefix) => prefix.trim().toLowerCase())
             .where((prefix) => prefix.isNotEmpty),
       );

  static const maxToolNameLength = 64;
  static const _neutralRemotePrefix = 'mcp__';
  static final RegExp _serverKeyInvalidChars = RegExp(r'[^a-zA-Z0-9_]+');
  static final RegExp _serverKeyConsecutiveUnderscores = RegExp(r'_+');
  static final RegExp _serverKeyEdgeUnderscores = RegExp(r'^_|_$');

  final Set<String> _reservedToolNames;
  final Set<String> _reservedToolNamePrefixes;

  Set<String> createUsedNames() => {..._reservedToolNames};

  String buildExposedName({
    required String baseName,
    required String identifier,
    required Set<String> usedNames,
    required int duplicateCount,
  }) {
    final serverKey = _buildServerKey(identifier);
    final requiresNeutralAlias = _matchesReservedPrefix(baseName);
    final aliasBaseName = requiresNeutralAlias
        ? '$_neutralRemotePrefix$baseName'
        : baseName;
    final shouldNamespace =
        duplicateCount > 1 ||
        usedNames.contains(baseName) ||
        requiresNeutralAlias;
    var candidate = shouldNamespace
        ? _buildNamespacedName(baseName: aliasBaseName, serverKey: serverKey)
        : _truncateName(baseName);
    var attempt = 2;

    while (!usedNames.add(candidate)) {
      candidate = _buildNamespacedName(
        baseName: aliasBaseName,
        serverKey: serverKey,
        attempt: attempt,
      );
      attempt += 1;
    }

    return candidate;
  }

  bool _matchesReservedPrefix(String name) {
    final normalizedName = name.toLowerCase();
    return _reservedToolNamePrefixes.any(normalizedName.startsWith);
  }

  String _buildNamespacedName({
    required String baseName,
    required String serverKey,
    int? attempt,
  }) {
    final suffix = attempt == null ? '__$serverKey' : '__${serverKey}_$attempt';
    final maxBaseLength = (maxToolNameLength - suffix.length).clamp(
      1,
      maxToolNameLength,
    );
    final truncatedBase = baseName.length <= maxBaseLength
        ? baseName
        : baseName.substring(0, maxBaseLength);
    return '$truncatedBase$suffix';
  }

  String _truncateName(String value) {
    if (value.length <= maxToolNameLength) {
      return value;
    }
    return value.substring(0, maxToolNameLength);
  }

  String _buildServerKey(String identifier) {
    final uri = Uri.tryParse(identifier);
    final rawValue = uri == null
        ? 'server'
        : [
            if (uri.host.isNotEmpty) uri.host else 'server',
            if (uri.hasPort) uri.port.toString(),
          ].join('_');
    final sanitized = rawValue.replaceAll(_serverKeyInvalidChars, '_');
    final collapsed = sanitized.replaceAll(
      _serverKeyConsecutiveUnderscores,
      '_',
    );
    final normalized = collapsed
        .replaceAll(_serverKeyEdgeUnderscores, '')
        .toLowerCase();
    final shortBase = normalized.isEmpty
        ? 'server'
        : normalized.substring(
            0,
            normalized.length > 18 ? 18 : normalized.length,
          );
    return '${shortBase}_${_shortHash(identifier)}';
  }

  String _shortHash(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x3fffffff;
    }
    return hash.toRadixString(36).padLeft(6, '0');
  }
}
