import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// SEC4.4i-a: observe where native-shell commands write outside the project,
/// without changing what they may do.
///
/// SEC4.4g asks a person to approve every shell command because Caverno
/// cannot prove its writes stay inside the project. The plan to answer that
/// with an OS sandbox (`docs/sec4_4i_os_write_containment_plan.md`) needs one
/// fact first: which directories outside the project real commands write to.
/// This gathers it. The command runs under a seatbelt profile that *allows*
/// every write and asks the kernel to report the ones outside the project,
/// tagged so one command's reports can be read back afterwards.
///
/// Opt-in through [environmentKey], because even an allow-everything profile
/// is a sandbox and sandboxes do not nest: a command that applies its own
/// (SwiftPM manifests, Chromium, agent CLIs) fails under it with
/// `sandbox_apply: Operation not permitted`, and a failed command cannot be
/// safely re-run. [reachesNestedSandbox] exempts the toolchains known to do
/// that; the flag bounds the damage of the ones it misses.
abstract final class ShellWriteObservation {
  static const environmentKey = 'CAVERNO_SHELL_WRITE_OBSERVATION';
  static const payloadKey = 'write_observation';
  static const _sandboxExec = '/usr/bin/sandbox-exec';
  static const _logBinary = '/usr/bin/log';
  static const _maxPaths = 50;
  static final Random _random = Random.secure();

  /// Commands that apply a sandbox of their own, directly or through the
  /// toolchain they drive. Matching only removes observation, never an
  /// approval, so a miss costs a broken observed command, not safety.
  static final RegExp _nestedSandboxCommand = RegExp(
    r'(^|[\s;&|(/])(xcodebuild|xcrun|swift|swiftc|pod|sandbox-exec|codex|'
    r'claude|open|osascript|playwright|puppeteer|chrome|chromium|'
    r'google-chrome)(\s|$)'
    r'|\bflutter\s+(build|run|drive)\b'
    r'|release_ios_macos\.sh|publish_macos_sparkle_release\.sh',
  );

  // Tags are interpolated into a log predicate, so only this shape passes.
  static final RegExp _tagPattern = RegExp(r'^cv-\d+-[0-9a-f]+$');

  static final RegExp _report = RegExp(
    r'^Sandbox: [^\n]*?\(\d+\) allow file-write-[\w-]+ ([^\n]+)',
  );

  static bool enabled({Map<String, String>? environment}) {
    final value = (environment ?? Platform.environment)[environmentKey]
        ?.trim()
        .toLowerCase();
    return value == '1' || value == 'true' || value == 'yes' || value == 'on';
  }

  static bool reachesNestedSandbox(String command) =>
      _nestedSandboxCommand.hasMatch(command);

  /// A fresh tag: `cv-<epoch seconds>-<random>`. The epoch lets [collect]
  /// bound its log query without the caller carrying a start time.
  static String newTag({DateTime? now}) {
    final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'cv-$seconds-$suffix';
  }

  /// The seatbelt profile: every write allowed, those outside [root] and
  /// `/dev` reported with [tag].
  static String profile({required String root, required String tag}) {
    String literal(String value) =>
        '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    return '(version 1)(allow default)'
        '(allow file-write* (require-all '
        '(require-not (subpath ${literal(root)})) '
        '(require-not (subpath "/dev"))) '
        '(with report) (with message ${literal(tag)}))';
  }

  /// Wraps a shell invocation for observation, or returns null when it
  /// should run as before: observation off, not macOS, no project root, or a
  /// command that applies its own sandbox.
  static ({String executable, List<String> args, String tag})? wrap({
    required String command,
    required String shellExecutable,
    required List<String> shellArgs,
    required String? root,
    Map<String, String>? environment,
  }) {
    if (!Platform.isMacOS || !enabled(environment: environment)) return null;
    final trimmedRoot = root?.trim() ?? '';
    if (trimmedRoot.isEmpty || reachesNestedSandbox(command)) return null;
    if (!File(_sandboxExec).existsSync()) return null;
    final String canonicalRoot;
    try {
      // Seatbelt matches resolved paths: /tmp is /private/tmp to it.
      canonicalRoot = Directory(trimmedRoot).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
    final tag = newTag();
    final canary = canaryPath(tag);
    // Without a canary outside the root, silence could not be told apart from
    // reporting that never arrives, so such a command is not observed.
    if (canary == null || p.isWithin(canonicalRoot, canary)) return null;
    return (
      executable: _sandboxExec,
      args: [
        '-p',
        profile(root: canonicalRoot, tag: tag),
        // Touch the canary, then become the real shell: exec keeps the
        // command's process, exit code and stdio exactly as unwrapped. The
        // subshell keeps a failed canary write from stopping the command.
        '/bin/sh',
        '-c',
        r'( : > "$0" ) 2>/dev/null; exec "$@"',
        canary,
        shellExecutable,
        ...shellArgs,
      ],
      tag: tag,
    );
  }

  /// A file outside any project that every observed command writes once, so
  /// [collect] can tell "reports arrived and named no other path" from
  /// "reports never arrived". Derived from [tag], so the collector needs no
  /// state beyond it. Null when the temp directory cannot be resolved.
  static String? canaryPath(String tag) {
    if (!_tagPattern.hasMatch(tag)) return null;
    try {
      final temp = Directory.systemTemp.resolveSymbolicLinksSync();
      return p.join(temp, 'caverno-write-observation-$tag');
    } on FileSystemException {
      return null;
    }
  }

  /// The tag a tool-result payload carries, or null.
  static String? tagFromPayload(String payload) {
    if (!payload.contains(payloadKey)) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final tag = decoded[payloadKey];
      return tag is String && _tagPattern.hasMatch(tag) ? tag : null;
    } on FormatException {
      return null;
    }
  }

  /// Paths reported for [tag], in first-seen order, deduplicated and capped.
  ///
  /// [ndjson] is `log show --style ndjson` output. The kernel can drop
  /// reports under load, so the result is a lower bound, never proof that a
  /// command wrote nowhere else.
  static ({List<String> paths, bool truncated}) parseReports(
    String ndjson,
    String tag,
  ) {
    final paths = <String>{};
    var truncated = false;
    for (final line in const LineSplitter().convert(ndjson)) {
      if (!line.contains(tag)) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      final message = decoded['eventMessage'];
      if (message is! String || !message.endsWith('\n$tag')) continue;
      final match = _report.firstMatch(message);
      if (match == null) continue;
      if (paths.length >= _maxPaths) {
        truncated = true;
        break;
      }
      paths.add(match.group(1)!);
    }
    return (paths: paths.toList(growable: false), truncated: truncated);
  }

  /// Reads the kernel reports for [tag] back from the unified log.
  ///
  /// `reportingConfirmed` is false when the canary write was not reported:
  /// the command's own writes cannot have been either, so an empty `paths`
  /// then means "unknown", not "wrote nothing outside the project". macOS
  /// 26.7.1 delivered no reports at all, which is how this was found.
  static Future<
    ({List<String> paths, bool truncated, bool reportingConfirmed})?
  >
  collect(String tag) async {
    if (!_tagPattern.hasMatch(tag) || !File(_logBinary).existsSync()) {
      return null;
    }
    final seconds = int.parse(tag.split('-')[1]);
    // One second of slack for clock rounding at the tag's creation.
    final start = DateTime.fromMillisecondsSinceEpoch((seconds - 1) * 1000);
    String two(int value) => value.toString().padLeft(2, '0');
    final startText =
        '${start.year}-${two(start.month)}-${two(start.day)} '
        '${two(start.hour)}:${two(start.minute)}:${two(start.second)}';
    try {
      final result = await Process.run(_logBinary, [
        'show',
        '--start',
        startText,
        '--style',
        'ndjson',
        '--predicate',
        'sender == "Sandbox" AND eventMessage CONTAINS "$tag"',
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode != 0) return null;
      final parsed = parseReports(result.stdout as String, tag);
      final canary = canaryPath(tag);
      if (canary != null) {
        try {
          File(canary).deleteSync();
        } on FileSystemException {
          // Already gone, or never written.
        }
      }
      return (
        paths: [
          for (final path in parsed.paths)
            if (path != canary) path,
        ],
        truncated: parsed.truncated,
        reportingConfirmed: canary != null && parsed.paths.contains(canary),
      );
    } on Object {
      return null;
    }
  }
}
