import 'dart:convert';
import 'dart:io';

class InstalledDependencyGroundingService {
  const InstalledDependencyGroundingService();

  static const toolName = 'resolve_installed_dependency';

  static const _defaultMaxMatches = 12;
  static const _maxMatchesLimit = 50;
  static const _defaultMaxChars = 12000;
  static const _maxCharsLimit = 60000;
  static const _maxFilesScanned = 1500;
  static const _maxFileBytes = 1024 * 1024;

  Future<String> resolve(Map<String, dynamic> arguments) async {
    final projectPath =
        (arguments['project_path'] as String?)?.trim() ??
        (arguments['path'] as String?)?.trim() ??
        '';
    if (projectPath.isEmpty) {
      return _error(
        code: 'project_path_required',
        message: 'project_path is required',
      );
    }

    final projectRoot = Directory(projectPath).absolute;
    if (!projectRoot.existsSync()) {
      return _error(
        code: 'project_path_not_found',
        message: 'Project path does not exist: ${projectRoot.path}',
        extra: {'project_path': projectRoot.path},
      );
    }

    final packageName =
        _stringArg(arguments, 'package_name') ??
        _stringArg(arguments, 'package') ??
        _stringArg(arguments, 'module');
    final symbol =
        _stringArg(arguments, 'symbol') ??
        _stringArg(arguments, 'query') ??
        _stringArg(arguments, 'api');
    final ecosystem = (_stringArg(arguments, 'ecosystem') ?? 'auto')
        .toLowerCase()
        .replaceAll('-', '_');
    final maxMatches =
        ((arguments['max_results'] as num?)?.toInt() ?? _defaultMaxMatches)
            .clamp(1, _maxMatchesLimit)
            .toInt();
    final maxChars =
        ((arguments['max_chars'] as num?)?.toInt() ?? _defaultMaxChars)
            .clamp(1000, _maxCharsLimit)
            .toInt();

    if ((packageName == null || packageName.isEmpty) &&
        (symbol == null || symbol.isEmpty)) {
      return _error(
        code: 'package_or_symbol_required',
        message: 'package_name or symbol is required',
        extra: {'project_path': projectRoot.path},
      );
    }

    final ecosystems = ecosystem == 'auto'
        ? _detectEcosystems(projectRoot)
        : <String>[ecosystem];
    if (ecosystems.isEmpty) {
      return _error(
        code: 'no_supported_dependency_manifest',
        message:
            'No supported dependency lockfile or installed dependency tree was found.',
        extra: {'project_path': projectRoot.path},
      );
    }

    final attempts = <Map<String, dynamic>>[];
    for (final candidate in ecosystems) {
      final result = switch (candidate) {
        'dart' || 'pub' => _resolveDart(
          projectRoot: projectRoot,
          packageName: packageName,
          symbol: symbol,
          maxMatches: maxMatches,
          maxChars: maxChars,
        ),
        'node' || 'npm' || 'javascript' || 'typescript' => _resolveNode(
          projectRoot: projectRoot,
          packageName: packageName,
          symbol: symbol,
          maxMatches: maxMatches,
          maxChars: maxChars,
        ),
        'python' || 'pip' => _resolvePython(
          projectRoot: projectRoot,
          packageName: packageName,
          symbol: symbol,
          maxMatches: maxMatches,
          maxChars: maxChars,
        ),
        'vendored' || 'vendor' || 'third_party' => _resolveVendored(
          projectRoot: projectRoot,
          packageName: packageName,
          symbol: symbol,
          maxMatches: maxMatches,
          maxChars: maxChars,
        ),
        _ => _UnsupportedEcosystemResult(candidate),
      };
      final payload = result.toJson();
      attempts.add(payload);
      if (result.ok) {
        return jsonEncode(payload);
      }
    }

    return jsonEncode({
      'ok': false,
      'code': 'dependency_not_resolved',
      'project_path': projectRoot.path,
      'package_name': packageName,
      'symbol': symbol,
      'attempted_ecosystems': attempts,
    });
  }

  List<String> _detectEcosystems(Directory projectRoot) {
    final ecosystems = <String>[];
    if (File.fromUri(projectRoot.uri.resolve('pubspec.lock')).existsSync()) {
      ecosystems.add('dart');
    }
    if (File.fromUri(
          projectRoot.uri.resolve('package-lock.json'),
        ).existsSync() ||
        Directory.fromUri(
          projectRoot.uri.resolve('node_modules'),
        ).existsSync()) {
      ecosystems.add('node');
    }
    if (_findPythonLockfile(projectRoot) != null ||
        _findPythonSitePackages(projectRoot).isNotEmpty) {
      ecosystems.add('python');
    }
    if (_vendoredRoots(projectRoot).isNotEmpty) {
      ecosystems.add('vendored');
    }
    return ecosystems;
  }

  _GroundingResult _resolveDart({
    required Directory projectRoot,
    required String? packageName,
    required String? symbol,
    required int maxMatches,
    required int maxChars,
  }) {
    final lockfile = File.fromUri(projectRoot.uri.resolve('pubspec.lock'));
    if (!lockfile.existsSync()) {
      return _GroundingResult.error(
        ecosystem: 'dart',
        code: 'pubspec_lock_not_found',
        message: 'pubspec.lock was not found.',
        projectPath: projectRoot.path,
      );
    }

    final lockPackages = _parsePubspecLock(lockfile);
    if (!_hasPackageName(packageName) && _hasSymbol(symbol)) {
      final symbolResult = _resolveSymbolFromLockedPackages(
        ecosystem: 'dart',
        projectRoot: projectRoot,
        lockfilePath: lockfile.path,
        lockfileAccuracy: 'pubspec.lock',
        packages: lockPackages,
        symbol: symbol!,
        resolvePackageRoot: (package) =>
            _resolveDartPackageRoot(projectRoot, package),
        sourceExtensions: const {'.dart', '.md', '.yaml', '.yml'},
        maxMatches: maxMatches,
        maxChars: maxChars,
      );
      if (symbolResult != null) {
        return symbolResult;
      }
      return _GroundingResult.error(
        ecosystem: 'dart',
        code: 'symbol_not_found_in_locked_dependencies',
        message:
            'The symbol was not found in any installed package from pubspec.lock.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
      );
    }
    final package = _selectLockedPackage(lockPackages, packageName, symbol);
    if (package == null) {
      return _GroundingResult.error(
        ecosystem: 'dart',
        code: 'locked_package_not_found',
        message: 'No matching package was found in pubspec.lock.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
      );
    }

    final rootPath = _resolveDartPackageRoot(projectRoot, package);
    if (rootPath == null) {
      return _GroundingResult.error(
        ecosystem: 'dart',
        code: 'installed_package_source_not_found',
        message:
            'The package is locked, but its installed source directory was not found offline.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
        package: package.toJson(),
      );
    }

    return _buildPackageResult(
      ecosystem: 'dart',
      projectRoot: projectRoot,
      lockfilePath: lockfile.path,
      lockfileAccuracy: 'pubspec.lock',
      package: package.toJson(),
      packageRoot: Directory(rootPath),
      symbol: symbol,
      sourceExtensions: const {'.dart', '.md', '.yaml', '.yml'},
      maxMatches: maxMatches,
      maxChars: maxChars,
    );
  }

  _GroundingResult _resolveNode({
    required Directory projectRoot,
    required String? packageName,
    required String? symbol,
    required int maxMatches,
    required int maxChars,
  }) {
    final lockfile = File.fromUri(projectRoot.uri.resolve('package-lock.json'));
    if (!lockfile.existsSync()) {
      return _GroundingResult.error(
        ecosystem: 'node',
        code: 'package_lock_not_found',
        message: 'package-lock.json was not found.',
        projectPath: projectRoot.path,
      );
    }
    final lockedPackages = _parsePackageLockPackages(lockfile);
    if (!_hasPackageName(packageName) && _hasSymbol(symbol)) {
      final symbolResult = _resolveSymbolFromLockedPackages(
        ecosystem: 'node',
        projectRoot: projectRoot,
        lockfilePath: lockfile.path,
        lockfileAccuracy: 'package-lock.json',
        packages: lockedPackages,
        symbol: symbol!,
        resolvePackageRoot: (package) =>
            _resolveNodePackageRoot(projectRoot, package.name),
        sourceExtensions: const {
          '.js',
          '.jsx',
          '.ts',
          '.tsx',
          '.mjs',
          '.cjs',
          '.d.ts',
          '.json',
          '.md',
        },
        maxMatches: maxMatches,
        maxChars: maxChars,
      );
      if (symbolResult != null) {
        return symbolResult;
      }
      return _GroundingResult.error(
        ecosystem: 'node',
        code: 'symbol_not_found_in_locked_dependencies',
        message:
            'The symbol was not found in any installed package from package-lock.json.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
      );
    }
    final package = _selectLockedPackage(lockedPackages, packageName, symbol);
    if (package == null) {
      return _GroundingResult.error(
        ecosystem: 'node',
        code: 'locked_package_not_found',
        message: 'No matching package was found in package-lock.json.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
      );
    }
    final rootPath = _resolveNodePackageRoot(projectRoot, package.name);
    if (rootPath == null) {
      return _GroundingResult.error(
        ecosystem: 'node',
        code: 'installed_package_source_not_found',
        message:
            'The package is locked, but node_modules does not contain its installed source.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
        package: package.toJson(),
      );
    }

    return _buildPackageResult(
      ecosystem: 'node',
      projectRoot: projectRoot,
      lockfilePath: lockfile.path,
      lockfileAccuracy: 'package-lock.json',
      package: package.toJson(),
      packageRoot: Directory(rootPath),
      symbol: symbol,
      sourceExtensions: const {
        '.js',
        '.jsx',
        '.ts',
        '.tsx',
        '.mjs',
        '.cjs',
        '.d.ts',
        '.json',
        '.md',
      },
      maxMatches: maxMatches,
      maxChars: maxChars,
    );
  }

  _GroundingResult _resolvePython({
    required Directory projectRoot,
    required String? packageName,
    required String? symbol,
    required int maxMatches,
    required int maxChars,
  }) {
    final lockfile = _findPythonLockfile(projectRoot);
    if (lockfile == null) {
      return _GroundingResult.error(
        ecosystem: 'python',
        code: 'python_lockfile_not_found',
        message:
            'No supported Python lockfile was found. Expected requirements*.txt, poetry.lock, or Pipfile.lock.',
        projectPath: projectRoot.path,
      );
    }
    final lockedPackages = _parsePythonLockfile(lockfile);
    if (!_hasPackageName(packageName) && _hasSymbol(symbol)) {
      final symbolResult = _resolveSymbolFromLockedPackages(
        ecosystem: 'python',
        projectRoot: projectRoot,
        lockfilePath: lockfile.path,
        lockfileAccuracy: _basename(lockfile.path),
        packages: lockedPackages,
        symbol: symbol!,
        resolvePackageRoot: (package) =>
            _resolvePythonPackageRoot(projectRoot, package.name),
        sourceExtensions: const {'.py', '.pyi', '.md', '.rst', '.txt'},
        maxMatches: maxMatches,
        maxChars: maxChars,
      );
      if (symbolResult != null) {
        return symbolResult;
      }
      return _GroundingResult.error(
        ecosystem: 'python',
        code: 'symbol_not_found_in_locked_dependencies',
        message:
            'The symbol was not found in any installed package from the Python lockfile.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
      );
    }
    final package = _selectLockedPackage(lockedPackages, packageName, symbol);
    if (package == null) {
      return _GroundingResult.error(
        ecosystem: 'python',
        code: 'locked_package_not_found',
        message: 'No matching package was found in the Python lockfile.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
      );
    }

    final packageRoot = _resolvePythonPackageRoot(projectRoot, package.name);
    if (packageRoot == null) {
      return _GroundingResult.error(
        ecosystem: 'python',
        code: 'installed_package_source_not_found',
        message:
            'The package is locked, but no matching site-packages source was found.',
        projectPath: projectRoot.path,
        lockfilePath: lockfile.path,
        package: package.toJson(),
      );
    }

    return _buildPackageResult(
      ecosystem: 'python',
      projectRoot: projectRoot,
      lockfilePath: lockfile.path,
      lockfileAccuracy: _basename(lockfile.path),
      package: package.toJson(),
      packageRoot: Directory(packageRoot),
      symbol: symbol,
      sourceExtensions: const {'.py', '.pyi', '.md', '.rst', '.txt'},
      maxMatches: maxMatches,
      maxChars: maxChars,
    );
  }

  _GroundingResult _resolveVendored({
    required Directory projectRoot,
    required String? packageName,
    required String? symbol,
    required int maxMatches,
    required int maxChars,
  }) {
    final roots = _vendoredRoots(projectRoot);
    final normalizedPackage = packageName == null
        ? null
        : _normalizePackageName(packageName);
    for (final root in roots) {
      if (normalizedPackage == null) {
        continue;
      }
      final candidate = Directory.fromUri(root.uri.resolve(packageName!));
      if (candidate.existsSync()) {
        return _buildPackageResult(
          ecosystem: 'vendored',
          projectRoot: projectRoot,
          lockfilePath: null,
          lockfileAccuracy: 'vendored_directory',
          package: {'name': packageName, 'version': null, 'source': 'vendored'},
          packageRoot: candidate,
          symbol: symbol,
          sourceExtensions: const {
            '.dart',
            '.js',
            '.ts',
            '.py',
            '.md',
            '.json',
            '.yaml',
            '.yml',
          },
          maxMatches: maxMatches,
          maxChars: maxChars,
        );
      }
      for (final child in root.listSync(followLinks: false)) {
        if (child is Directory &&
            _normalizePackageName(_basename(child.path)) == normalizedPackage) {
          return _buildPackageResult(
            ecosystem: 'vendored',
            projectRoot: projectRoot,
            lockfilePath: null,
            lockfileAccuracy: 'vendored_directory',
            package: {
              'name': _basename(child.path),
              'version': null,
              'source': 'vendored',
            },
            packageRoot: child,
            symbol: symbol,
            sourceExtensions: const {
              '.dart',
              '.js',
              '.ts',
              '.py',
              '.md',
              '.json',
              '.yaml',
              '.yml',
            },
            maxMatches: maxMatches,
            maxChars: maxChars,
          );
        }
      }
    }

    return _GroundingResult.error(
      ecosystem: 'vendored',
      code: 'vendored_package_not_found',
      message: 'No matching vendored dependency directory was found.',
      projectPath: projectRoot.path,
    );
  }

  _GroundingResult _buildPackageResult({
    required String ecosystem,
    required Directory projectRoot,
    required String? lockfilePath,
    required String lockfileAccuracy,
    required Map<String, dynamic> package,
    required Directory packageRoot,
    required String? symbol,
    required Set<String> sourceExtensions,
    required int maxMatches,
    required int maxChars,
  }) {
    final docs = _readPackageDocs(packageRoot, maxChars: maxChars ~/ 3);
    final matches = symbol == null || symbol.trim().isEmpty
        ? const <Map<String, dynamic>>[]
        : _searchPackageSources(
            packageRoot: packageRoot,
            symbol: symbol.trim(),
            extensions: sourceExtensions,
            maxMatches: maxMatches,
          );
    final files = _packageFileOverview(
      packageRoot,
      extensions: sourceExtensions,
      maxEntries: 80,
    );

    return _GroundingResult.ok({
      'ok': true,
      'ecosystem': ecosystem,
      'project_path': projectRoot.path,
      'lockfile_path': lockfilePath,
      'lockfile_accuracy': lockfileAccuracy,
      'offline_only': true,
      'package': {...package, 'root_path': packageRoot.absolute.path},
      'documentation': docs,
      'source_files': files,
      'matches': matches,
      'symbol': symbol,
      'symbol_found': symbol == null || symbol.trim().isEmpty
          ? null
          : matches.isNotEmpty,
      'guidance':
          'Use these installed files as the source of truth. Do not assume a newer upstream API than the locked version.',
    });
  }

  List<_LockedPackage> _parsePubspecLock(File lockfile) {
    final packages = <_LockedPackage>[];
    String? currentName;
    final block = <String>[];

    void flush() {
      final packageName = currentName;
      if (packageName == null) return;
      packages.add(_lockedPackageFromPubBlock(packageName, block));
      block.clear();
    }

    var inPackages = false;
    for (final line in lockfile.readAsLinesSync()) {
      if (line.trim() == 'packages:') {
        inPackages = true;
        continue;
      }
      if (inPackages &&
          line.isNotEmpty &&
          !line.startsWith(' ') &&
          line.trim() != 'packages:') {
        flush();
        currentName = null;
        break;
      }
      if (!inPackages) {
        continue;
      }
      final match = RegExp(r'^  ([^\s:#][^:#]*):\s*$').firstMatch(line);
      if (match != null) {
        flush();
        currentName = match.group(1)!.trim();
      } else if (currentName != null) {
        block.add(line);
      }
    }
    flush();
    return packages;
  }

  _LockedPackage _lockedPackageFromPubBlock(
    String packageName,
    List<String> block,
  ) {
    String? dependency;
    String? source;
    String? version;
    String? descriptionName;
    String? descriptionUrl;
    String? descriptionPath;
    String? resolvedRef;

    for (final line in block) {
      final trimmed = line.trim();
      if (trimmed.startsWith('dependency:')) {
        dependency = _stripYamlScalar(trimmed.substring('dependency:'.length));
      } else if (trimmed.startsWith('source:')) {
        source = _stripYamlScalar(trimmed.substring('source:'.length));
      } else if (trimmed.startsWith('version:')) {
        version = _stripYamlScalar(trimmed.substring('version:'.length));
      } else if (trimmed.startsWith('name:')) {
        descriptionName = _stripYamlScalar(trimmed.substring('name:'.length));
      } else if (trimmed.startsWith('url:')) {
        descriptionUrl = _stripYamlScalar(trimmed.substring('url:'.length));
      } else if (trimmed.startsWith('path:')) {
        descriptionPath = _stripYamlScalar(trimmed.substring('path:'.length));
      } else if (trimmed.startsWith('resolved-ref:')) {
        resolvedRef = _stripYamlScalar(
          trimmed.substring('resolved-ref:'.length),
        );
      }
    }

    return _LockedPackage(
      name: descriptionName?.isNotEmpty == true
          ? descriptionName!
          : packageName,
      version: version,
      source: source,
      dependency: dependency,
      url: descriptionUrl,
      path: descriptionPath,
      resolvedRef: resolvedRef,
    );
  }

  List<_LockedPackage> _parsePackageLockPackages(File lockfile) {
    final decoded = jsonDecode(lockfile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return const [];
    final packages = decoded['packages'];
    final candidates = <_LockedPackage>[];
    if (packages is Map<String, dynamic>) {
      for (final entry in packages.entries) {
        if (entry.key.isEmpty || !entry.key.startsWith('node_modules/')) {
          continue;
        }
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final name = entry.key.substring('node_modules/'.length);
        candidates.add(
          _LockedPackage(
            name: name,
            version: value['version'] as String?,
            source: 'npm',
            dependency: null,
            url: value['resolved'] as String?,
            path: null,
            resolvedRef: value['integrity'] as String?,
          ),
        );
      }
    }
    final dependencies = decoded['dependencies'];
    if (candidates.isEmpty && dependencies is Map<String, dynamic>) {
      for (final entry in dependencies.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        candidates.add(
          _LockedPackage(
            name: entry.key,
            version: value['version'] as String?,
            source: 'npm',
            dependency: null,
            url: value['resolved'] as String?,
            path: null,
            resolvedRef: value['integrity'] as String?,
          ),
        );
      }
    }
    return candidates;
  }

  _GroundingResult? _resolveSymbolFromLockedPackages({
    required String ecosystem,
    required Directory projectRoot,
    required String lockfilePath,
    required String lockfileAccuracy,
    required List<_LockedPackage> packages,
    required String symbol,
    required String? Function(_LockedPackage package) resolvePackageRoot,
    required Set<String> sourceExtensions,
    required int maxMatches,
    required int maxChars,
  }) {
    for (final package in packages) {
      final rootPath = resolvePackageRoot(package);
      if (rootPath == null) continue;
      final root = Directory(rootPath);
      final matches = _searchPackageSources(
        packageRoot: root,
        symbol: symbol,
        extensions: sourceExtensions,
        maxMatches: maxMatches,
      );
      if (matches.isEmpty) continue;
      return _buildPackageResult(
        ecosystem: ecosystem,
        projectRoot: projectRoot,
        lockfilePath: lockfilePath,
        lockfileAccuracy: lockfileAccuracy,
        package: package.toJson(),
        packageRoot: root,
        symbol: symbol,
        sourceExtensions: sourceExtensions,
        maxMatches: maxMatches,
        maxChars: maxChars,
      );
    }
    return null;
  }

  List<_LockedPackage> _parsePythonLockfile(File lockfile) {
    final basename = _basename(lockfile.path).toLowerCase();
    if (basename == 'pipfile.lock') {
      return _parsePipfileLock(lockfile);
    }
    if (basename == 'poetry.lock') {
      return _parsePoetryLock(lockfile);
    }
    return _parseRequirementsLock(lockfile);
  }

  List<_LockedPackage> _parsePipfileLock(File lockfile) {
    final decoded = jsonDecode(lockfile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return const [];
    final packages = <_LockedPackage>[];
    for (final sectionName in const ['default', 'develop']) {
      final section = decoded[sectionName];
      if (section is! Map<String, dynamic>) continue;
      for (final entry in section.entries) {
        final value = entry.value;
        String? version;
        if (value is Map<String, dynamic>) {
          version = (value['version'] as String?)?.replaceFirst('==', '');
        } else if (value is String) {
          version = value.replaceFirst('==', '');
        }
        packages.add(
          _LockedPackage(
            name: entry.key,
            version: version,
            source: 'pip',
            dependency: sectionName,
            url: null,
            path: null,
            resolvedRef: null,
          ),
        );
      }
    }
    return packages;
  }

  List<_LockedPackage> _parsePoetryLock(File lockfile) {
    final packages = <_LockedPackage>[];
    String? name;
    String? version;
    void flush() {
      final packageName = name;
      if (packageName == null) return;
      packages.add(
        _LockedPackage(
          name: packageName,
          version: version,
          source: 'poetry',
          dependency: null,
          url: null,
          path: null,
          resolvedRef: null,
        ),
      );
    }

    for (final line in lockfile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed == '[[package]]') {
        flush();
        name = null;
        version = null;
      } else if (trimmed.startsWith('name =')) {
        name = _stripTomlScalar(trimmed.substring('name ='.length));
      } else if (trimmed.startsWith('version =')) {
        version = _stripTomlScalar(trimmed.substring('version ='.length));
      }
    }
    flush();
    return packages;
  }

  List<_LockedPackage> _parseRequirementsLock(File lockfile) {
    final packages = <_LockedPackage>[];
    final requirementPattern = RegExp(
      r'^\s*([A-Za-z0-9_.-]+)(?:\[[^\]]+\])?\s*==\s*([^\s;#]+)',
    );
    for (final line in lockfile.readAsLinesSync()) {
      final match = requirementPattern.firstMatch(line);
      if (match == null) continue;
      packages.add(
        _LockedPackage(
          name: match.group(1)!,
          version: match.group(2)!,
          source: 'pip',
          dependency: _basename(lockfile.path),
          url: null,
          path: null,
          resolvedRef: null,
        ),
      );
    }
    return packages;
  }

  _LockedPackage? _selectLockedPackage(
    List<_LockedPackage> packages,
    String? packageName,
    String? symbol,
  ) {
    if (packageName != null && packageName.trim().isNotEmpty) {
      final normalized = _normalizePackageName(packageName);
      for (final package in packages) {
        if (_normalizePackageName(package.name) == normalized) {
          return package;
        }
      }
      return null;
    }

    if (symbol != null && symbol.trim().isNotEmpty) {
      final normalized = _normalizePackageName(symbol);
      for (final package in packages) {
        if (_normalizePackageName(package.name) == normalized) {
          return package;
        }
      }
    }
    return null;
  }

  bool _hasPackageName(String? packageName) {
    return packageName != null && packageName.trim().isNotEmpty;
  }

  bool _hasSymbol(String? symbol) {
    return symbol != null && symbol.trim().isNotEmpty;
  }

  String? _resolveDartPackageRoot(
    Directory projectRoot,
    _LockedPackage package,
  ) {
    final packageConfigRoot = _resolveFromPackageConfig(
      projectRoot,
      package.name,
    );
    if (packageConfigRoot != null) return packageConfigRoot;

    if (package.source == 'path' && package.path != null) {
      final path = _resolveProjectPath(projectRoot, package.path!);
      if (Directory(path).existsSync()) return path;
    }

    if (package.source == 'hosted' && package.version != null) {
      for (final cacheRoot in _pubCacheRoots()) {
        for (final host in const ['pub.dev', 'pub.dartlang.org']) {
          final candidate = Directory.fromUri(
            cacheRoot.uri.resolve(
              'hosted/$host/${package.name}-${package.version}/',
            ),
          );
          if (candidate.existsSync()) return candidate.path;
        }
      }
    }
    return null;
  }

  String? _resolveFromPackageConfig(Directory projectRoot, String packageName) {
    final config = File.fromUri(
      projectRoot.uri.resolve('.dart_tool/package_config.json'),
    );
    if (!config.existsSync()) return null;
    final decoded = jsonDecode(config.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return null;
    final packages = decoded['packages'];
    if (packages is! List<dynamic>) return null;
    for (final entry in packages) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['name'] != packageName) continue;
      final rootUri = entry['rootUri'] as String?;
      if (rootUri == null || rootUri.isEmpty) return null;
      final resolved = Uri.parse(rootUri);
      if (resolved.scheme == 'file') {
        return Directory.fromUri(resolved).absolute.path;
      }
      if (resolved.scheme.isEmpty) {
        return Directory.fromUri(
          config.parent.uri.resolve(rootUri),
        ).absolute.path;
      }
    }
    return null;
  }

  List<Directory> _pubCacheRoots() {
    final roots = <Directory>[];
    final pubCache = Platform.environment['PUB_CACHE']?.trim();
    if (pubCache != null && pubCache.isNotEmpty) {
      roots.add(Directory(pubCache).absolute);
    }
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      roots.add(Directory.fromUri(Directory(home).uri.resolve('.pub-cache/')));
    }
    return roots;
  }

  String? _resolveNodePackageRoot(Directory projectRoot, String packageName) {
    final candidate = Directory.fromUri(
      projectRoot.uri.resolve('node_modules/$packageName/'),
    );
    if (candidate.existsSync()) return candidate.path;
    return null;
  }

  File? _findPythonLockfile(Directory projectRoot) {
    for (final name in const ['Pipfile.lock', 'poetry.lock']) {
      final file = File.fromUri(projectRoot.uri.resolve(name));
      if (file.existsSync()) return file;
    }
    final requirements =
        projectRoot.listSync(followLinks: false).whereType<File>().where((
          file,
        ) {
          final name = _basename(file.path).toLowerCase();
          return name == 'requirements.txt' ||
              (name.startsWith('requirements') && name.endsWith('.txt'));
        }).toList()..sort((a, b) => a.path.compareTo(b.path));
    return requirements.isEmpty ? null : requirements.first;
  }

  List<Directory> _findPythonSitePackages(Directory projectRoot) {
    final roots = <Directory>[];
    final virtualEnv = Platform.environment['VIRTUAL_ENV']?.trim();
    if (virtualEnv != null && virtualEnv.isNotEmpty) {
      roots.addAll(_sitePackagesUnder(Directory(virtualEnv)));
    }
    for (final name in const ['.venv', 'venv']) {
      final venv = Directory.fromUri(projectRoot.uri.resolve('$name/'));
      if (venv.existsSync()) {
        roots.addAll(_sitePackagesUnder(venv));
      }
    }
    return roots;
  }

  List<Directory> _sitePackagesUnder(Directory venv) {
    final roots = <Directory>[];
    for (final prefix in const ['lib', 'Lib']) {
      final lib = Directory.fromUri(venv.uri.resolve('$prefix/'));
      if (!lib.existsSync()) continue;
      for (final entity in lib.listSync(followLinks: false)) {
        if (entity is Directory) {
          final sitePackages = Directory.fromUri(
            entity.uri.resolve('site-packages/'),
          );
          if (sitePackages.existsSync()) roots.add(sitePackages);
        }
      }
      final direct = Directory.fromUri(lib.uri.resolve('site-packages/'));
      if (direct.existsSync()) roots.add(direct);
    }
    return roots;
  }

  String? _resolvePythonPackageRoot(Directory projectRoot, String packageName) {
    final normalized = _normalizePackageName(packageName);
    for (final sitePackages in _findPythonSitePackages(projectRoot)) {
      final topLevelNames = _pythonTopLevelNames(sitePackages, normalized);
      for (final topLevel in topLevelNames) {
        final packageDir = Directory.fromUri(
          sitePackages.uri.resolve('$topLevel/'),
        );
        if (packageDir.existsSync()) return packageDir.path;
        final moduleFile = File.fromUri(
          sitePackages.uri.resolve('$topLevel.py'),
        );
        if (moduleFile.existsSync()) return moduleFile.parent.path;
      }
      for (final entity in sitePackages.listSync(followLinks: false)) {
        if (entity is Directory &&
            _normalizePackageName(_basename(entity.path)) == normalized) {
          return entity.path;
        }
      }
    }
    return null;
  }

  List<String> _pythonTopLevelNames(
    Directory sitePackages,
    String packageName,
  ) {
    for (final entity in sitePackages.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = _basename(entity.path);
      if (!name.endsWith('.dist-info')) continue;
      final distName = name.substring(0, name.length - '.dist-info'.length);
      final normalizedDistName = _normalizePackageName(
        distName.replaceFirst(RegExp(r'-[^-]+$'), ''),
      );
      if (normalizedDistName != packageName) continue;
      final topLevel = File.fromUri(entity.uri.resolve('top_level.txt'));
      if (topLevel.existsSync()) {
        final names = topLevel
            .readAsLinesSync()
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        if (names.isNotEmpty) return names;
      }
    }
    return [packageName.replaceAll('-', '_')];
  }

  List<Directory> _vendoredRoots(Directory projectRoot) {
    final roots = <Directory>[];
    for (final name in const [
      'vendor',
      'vendors',
      'third_party',
      'third-party',
    ]) {
      final directory = Directory.fromUri(projectRoot.uri.resolve('$name/'));
      if (directory.existsSync()) roots.add(directory);
    }
    return roots;
  }

  Map<String, dynamic>? _readPackageDocs(
    Directory packageRoot, {
    required int maxChars,
  }) {
    for (final relativePath in const [
      'README.md',
      'readme.md',
      'README.rst',
      'pubspec.yaml',
      'package.json',
      'METADATA',
    ]) {
      final file = File.fromUri(packageRoot.uri.resolve(relativePath));
      if (!file.existsSync()) continue;
      final content = _readTextFileExcerpt(file, maxChars: maxChars);
      if (content == null) continue;
      return {
        'path': file.absolute.path,
        'excerpt': content.excerpt,
        'truncated': content.truncated,
      };
    }

    for (final entity in packageRoot.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      if (!_basename(entity.path).endsWith('.dist-info')) continue;
      final metadata = File.fromUri(entity.uri.resolve('METADATA'));
      if (!metadata.existsSync()) continue;
      final content = _readTextFileExcerpt(metadata, maxChars: maxChars);
      if (content == null) continue;
      return {
        'path': metadata.absolute.path,
        'excerpt': content.excerpt,
        'truncated': content.truncated,
      };
    }
    return null;
  }

  List<Map<String, dynamic>> _searchPackageSources({
    required Directory packageRoot,
    required String symbol,
    required Set<String> extensions,
    required int maxMatches,
  }) {
    final matches = <Map<String, dynamic>>[];
    final pattern = RegExp(RegExp.escape(symbol));
    var filesScanned = 0;
    for (final file in _walkFiles(packageRoot, extensions: extensions)) {
      filesScanned++;
      if (filesScanned > _maxFilesScanned || matches.length >= maxMatches) {
        break;
      }
      if (file.lengthSync() > _maxFileBytes) continue;
      final lines = _readTextLines(file);
      if (lines == null) continue;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!pattern.hasMatch(line)) continue;
        matches.add({
          'path': file.absolute.path,
          'relative_path': _relativePath(file.path, packageRoot.path),
          'line': i + 1,
          'text': _clipLine(line),
        });
        if (matches.length >= maxMatches) break;
      }
    }
    return matches;
  }

  List<Map<String, dynamic>> _packageFileOverview(
    Directory packageRoot, {
    required Set<String> extensions,
    required int maxEntries,
  }) {
    final files = <Map<String, dynamic>>[];
    for (final file in _walkFiles(packageRoot, extensions: extensions)) {
      files.add({
        'path': file.absolute.path,
        'relative_path': _relativePath(file.path, packageRoot.path),
        'bytes': file.lengthSync(),
      });
      if (files.length >= maxEntries) break;
    }
    return files;
  }

  Iterable<File> _walkFiles(
    Directory root, {
    required Set<String> extensions,
  }) sync* {
    final entities = root.listSync(recursive: true, followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entities) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      final relative = _relativePath(
        entity.path,
        root.path,
      ).replaceAll('\\', '/');
      if (relative.startsWith('.git/') ||
          relative.startsWith('build/') ||
          relative.startsWith('node_modules/') ||
          lower.contains('/.git/')) {
        continue;
      }
      if (extensions.any(lower.endsWith)) {
        yield entity;
      }
    }
  }

  _TextExcerpt? _readTextFileExcerpt(File file, {required int maxChars}) {
    if (!file.existsSync() || file.lengthSync() > _maxFileBytes) return null;
    final text = _readText(file);
    if (text == null) return null;
    if (text.length <= maxChars) {
      return _TextExcerpt(text, truncated: false);
    }
    return _TextExcerpt(text.substring(0, maxChars), truncated: true);
  }

  List<String>? _readTextLines(File file) {
    final text = _readText(file);
    return text?.split('\n');
  }

  String? _readText(File file) {
    try {
      final bytes = file.readAsBytesSync();
      if (bytes.contains(0)) return null;
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return null;
    }
  }

  String? _stringArg(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  String _resolveProjectPath(Directory projectRoot, String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'file') {
      return Directory.fromUri(uri).absolute.path;
    }
    if (_isAbsolutePath(path)) return Directory(path).absolute.path;
    return Directory.fromUri(projectRoot.uri.resolve(path)).absolute.path;
  }

  bool _isAbsolutePath(String path) {
    if (path.startsWith('/')) return true;
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  String _stripYamlScalar(String value) => _stripQuoted(value.trim());

  String _stripTomlScalar(String value) => _stripQuoted(value.trim());

  String _stripQuoted(String value) {
    if (value.length >= 2) {
      final first = value.codeUnitAt(0);
      final last = value.codeUnitAt(value.length - 1);
      if ((first == 34 && last == 34) || (first == 39 && last == 39)) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }

  String _normalizePackageName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[-_.]+'), '-');
  }

  String _relativePath(String path, String root) {
    final normalizedRoot = Directory(root).absolute.path;
    final normalizedPath = File(path).absolute.path;
    if (normalizedPath == normalizedRoot) return '.';
    final prefix = normalizedRoot.endsWith(Platform.pathSeparator)
        ? normalizedRoot
        : '$normalizedRoot${Platform.pathSeparator}';
    if (normalizedPath.startsWith(prefix)) {
      return normalizedPath.substring(prefix.length);
    }
    return normalizedPath;
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  String _clipLine(String line) {
    final trimmed = line.trimRight();
    return trimmed.length <= 500 ? trimmed : '${trimmed.substring(0, 500)}...';
  }

  String _error({
    required String code,
    required String message,
    Map<String, dynamic> extra = const {},
  }) {
    return jsonEncode({'ok': false, 'code': code, 'error': message, ...extra});
  }
}

class _LockedPackage {
  const _LockedPackage({
    required this.name,
    required this.version,
    required this.source,
    required this.dependency,
    required this.url,
    required this.path,
    required this.resolvedRef,
  });

  final String name;
  final String? version;
  final String? source;
  final String? dependency;
  final String? url;
  final String? path;
  final String? resolvedRef;

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'source': source,
    'dependency': dependency,
    if (url != null) 'url': url,
    if (path != null) 'path': path,
    if (resolvedRef != null) 'resolved_ref': resolvedRef,
  };
}

class _GroundingResult {
  const _GroundingResult._(this.ok, this.payload);

  factory _GroundingResult.ok(Map<String, dynamic> payload) {
    return _GroundingResult._(true, payload);
  }

  factory _GroundingResult.error({
    required String ecosystem,
    required String code,
    required String message,
    required String projectPath,
    String? lockfilePath,
    Map<String, dynamic>? package,
  }) {
    final payload = <String, dynamic>{
      'ok': false,
      'ecosystem': ecosystem,
      'code': code,
      'error': message,
      'project_path': projectPath,
    };
    if (lockfilePath != null) {
      payload['lockfile_path'] = lockfilePath;
    }
    if (package != null) {
      payload['package'] = package;
    }
    return _GroundingResult._(false, payload);
  }

  final bool ok;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => payload;
}

class _UnsupportedEcosystemResult extends _GroundingResult {
  _UnsupportedEcosystemResult(String ecosystem)
    : super._(false, {
        'ok': false,
        'ecosystem': ecosystem,
        'code': 'unsupported_ecosystem',
        'error':
            'Unsupported ecosystem. Use auto, dart, node, python, or vendored.',
      });
}

class _TextExcerpt {
  const _TextExcerpt(this.excerpt, {required this.truncated});

  final String excerpt;
  final bool truncated;
}
