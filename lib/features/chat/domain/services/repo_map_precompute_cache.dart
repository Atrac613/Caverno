import 'repo_map_service.dart';

/// Result of a precompute attempt, so an idle-maintenance stage (LL22) can
/// report whether it did real work.
enum RepoMapPrecomputeResult {
  /// A fresh map was built and stored.
  computed,

  /// The stored map was already valid for the current project signature.
  alreadyWarm,

  /// There was nothing to build (no project root or no ranked files).
  noProject,
}

/// LL22 repo-map precompute cache: stores a built repo map per coding-project
/// root, keyed by a cheap input fingerprint ([RepoMapService.computeSignatureForProject]).
///
/// The live prompt path calls [getOrBuild], which returns a cached map when the
/// signature is unchanged and otherwise rebuilds it (so the cache also helps
/// outside the idle window). An idle-time stage calls [precompute] to warm the
/// cache so the first interactive turn is a hit.
///
/// The cache is in-memory and process-scoped: the idle scheduler runs in the
/// same process that serves the morning's first turn, and the server-side KV
/// cache it pairs with (LL6) is likewise non-persistent, so there is no value
/// in persisting it across restarts.
class RepoMapPrecomputeCache {
  RepoMapPrecomputeCache();

  final Map<String, _RepoMapCacheEntry> _entries = {};

  /// Returns the cached repo map when the project's signature is unchanged;
  /// otherwise rebuilds, stores, and returns it. Returns null when the project
  /// has no buildable map.
  String? getOrBuild({
    required String? rootPath,
    int? usableContextTokens,
    int maxFiles = RepoMapService.defaultMaxFiles,
    int maxSymbols = RepoMapService.defaultMaxSymbols,
    Iterable<RepoMapSymbolEntry> lspSymbolEntries = const [],
  }) {
    return _resolve(
      rootPath: rootPath,
      usableContextTokens: usableContextTokens,
      maxFiles: maxFiles,
      maxSymbols: maxSymbols,
      lspSymbolEntries: lspSymbolEntries,
    ).map;
  }

  /// Idle-time precompute (LL22): builds and stores the map so the first
  /// interactive turn is a cache hit. Reports whether a fresh map was computed,
  /// the cache was already warm, or there was nothing to build.
  RepoMapPrecomputeResult precompute({
    required String? rootPath,
    int? usableContextTokens,
    int maxFiles = RepoMapService.defaultMaxFiles,
    int maxSymbols = RepoMapService.defaultMaxSymbols,
    Iterable<RepoMapSymbolEntry> lspSymbolEntries = const [],
  }) {
    return _resolve(
      rootPath: rootPath,
      usableContextTokens: usableContextTokens,
      maxFiles: maxFiles,
      maxSymbols: maxSymbols,
      lspSymbolEntries: lspSymbolEntries,
    ).result;
  }

  /// Drops any cached map for [rootPath]. Use when an input that the signature
  /// cannot observe changes (e.g. an explicit user refresh).
  void invalidate(String? rootPath) {
    final key = rootPath?.trim();
    if (key == null || key.isEmpty) return;
    _entries.remove(key);
  }

  /// Drops the entire cache (e.g. on model/endpoint change handled by callers).
  void clear() => _entries.clear();

  ({String? map, RepoMapPrecomputeResult result}) _resolve({
    required String? rootPath,
    required int? usableContextTokens,
    required int maxFiles,
    required int maxSymbols,
    required Iterable<RepoMapSymbolEntry> lspSymbolEntries,
  }) {
    final key = rootPath?.trim();
    if (key == null || key.isEmpty) {
      return (map: null, result: RepoMapPrecomputeResult.noProject);
    }

    final signature = RepoMapService.computeSignatureForProject(
      rootPath: key,
      usableContextTokens: usableContextTokens,
      maxFiles: maxFiles,
      maxSymbols: maxSymbols,
      lspSymbolEntries: lspSymbolEntries,
    );
    if (signature == null) {
      _entries.remove(key);
      return (map: null, result: RepoMapPrecomputeResult.noProject);
    }

    final cached = _entries[key];
    if (cached != null && cached.signature == signature) {
      return (map: cached.map, result: RepoMapPrecomputeResult.alreadyWarm);
    }

    final map = RepoMapService.buildForProject(
      rootPath: key,
      usableContextTokens: usableContextTokens,
      maxFiles: maxFiles,
      maxSymbols: maxSymbols,
      lspSymbolEntries: lspSymbolEntries,
    );
    if (map == null) {
      _entries.remove(key);
      return (map: null, result: RepoMapPrecomputeResult.noProject);
    }

    _entries[key] = _RepoMapCacheEntry(signature: signature, map: map);
    return (map: map, result: RepoMapPrecomputeResult.computed);
  }
}

class _RepoMapCacheEntry {
  const _RepoMapCacheEntry({required this.signature, required this.map});

  final String signature;
  final String map;
}
