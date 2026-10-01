import 'dart:io';

/// Runtime dependencies are readable; personal files and inherited credentials
/// are not part of a workspace command's authority.
abstract final class WorkspaceCommandEnvironment {
  static List<String> readRoots() {
    final home = Platform.environment['HOME'];
    final candidates = [
      '/System/Library',
      '/System/Volumes/Preboot/Cryptexes/OS/System/Library',
      '/System/Volumes/Preboot/Cryptexes/OS/usr',
      '/usr/bin',
      '/usr/sbin',
      '/usr/lib',
      '/usr/libexec',
      '/usr/share',
      '/usr/local/bin',
      '/usr/local/opt',
      '/usr/local/Cellar',
      '/usr/local/lib',
      '/usr/local/share',
      '/bin',
      '/sbin',
      '/Library/Developer',
      '/Library/Apple',
      '/private/etc/ssl',
      '/private/etc/zoneinfo',
      '/opt/homebrew/bin',
      '/opt/homebrew/opt',
      '/opt/homebrew/Cellar',
      '/opt/homebrew/lib',
      '/opt/homebrew/share',
      ?activeXcodeBundle(),
      if (home != null) ...[
        '$home/fvm/versions',
        '$home/.pub-cache',
        '$home/.gradle/caches',
        '$home/.npm/_cacache',
      ],
    ];
    final roots = <String>{};
    for (final candidate in candidates) {
      try {
        final canonical = Directory(candidate).resolveSymbolicLinksSync();
        // A redirected dependency directory must never grant the whole host.
        if (canonical != '/' &&
            canonical != home &&
            canonical != '/Users' &&
            canonical != '/private') {
          roots.add(canonical);
        }
      } on FileSystemException {
        // Optional toolchains need not be installed.
      }
    }
    return roots.toList(growable: false);
  }

  /// `/usr/bin/git`, `make` and `clang` are xcrun shims. When Xcode is the
  /// active developer directory they load from its app bundle, so without it
  /// every contained `git` failed and a piped `grep` reported zero matches as
  /// if the file had none (session 75a344ac).
  static String? activeXcodeBundle({String? developerDir}) {
    String? path = developerDir ?? Platform.environment['DEVELOPER_DIR'];
    if (path == null) {
      try {
        path = Link('/var/db/xcode_select_link').resolveSymbolicLinksSync();
      } on FileSystemException {
        return null;
      }
    }
    final end = path.indexOf('.app/');
    if (end < 0 && !path.endsWith('.app')) return null;
    final bundle = end < 0 ? path : path.substring(0, end + 4);
    return bundle.lastIndexOf('/') > 0 ? bundle : null;
  }

  static Map<String, String> isolated({
    required Map<String, String> source,
    required String scratch,
  }) => {
    for (final entry in source.entries)
      if (const {
            'PATH',
            'LANG',
            'TZ',
            'TERM',
            'SYSTEMROOT',
          }.contains(entry.key) ||
          entry.key.startsWith('LC_'))
        entry.key: entry.value,
    'HOME': scratch,
    'TMPDIR': scratch,
    'TMP': scratch,
    'TEMP': scratch,
    'XDG_CONFIG_HOME': '$scratch/config',
    'XDG_CACHE_HOME': '$scratch/cache',
    'XDG_DATA_HOME': '$scratch/data',
    'PYTHONNOUSERSITE': '1',
    'GIT_CONFIG_NOSYSTEM': '1',
    'GIT_CONFIG_GLOBAL': '/dev/null',
  };
}
