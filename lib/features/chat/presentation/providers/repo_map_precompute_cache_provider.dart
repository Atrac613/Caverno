import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/repo_map_lsp_symbol_cache.dart';
import '../../domain/services/repo_map_precompute_cache.dart';

/// Process-wide LL22 repo-map precompute cache. Kept alive for the whole app
/// session so an idle-time precompute warms the first interactive turn instead
/// of paying the full build cost on the morning's first prompt.
final repoMapPrecomputeCacheProvider = Provider<RepoMapPrecomputeCache>(
  (_) => RepoMapPrecomputeCache(),
);

final repoMapLspSymbolCacheProvider = Provider<RepoMapLspSymbolCache>(
  (_) => RepoMapLspSymbolCache(),
);
