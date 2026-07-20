/// SEC1 (Local Agent Data Perimeter), slice 1: classify what kind of action a
/// tool performs and how risky it is, so later slices can attach capability
/// context to tool calls, approval surfaces, and taint policy (SEC2).
///
/// This is pure classification. It changes no approval or execution behavior on
/// its own, so extracting it cannot weaken any existing default policy
/// (SEC1 acceptance criterion: "existing approval flows continue to work with no
/// weaker default policy").
library;

/// The primary capability a tool exercises. Mirrors the categories named in the
/// SEC1 scope (file read/write, shell, network, git push, SSH, memory write,
/// clipboard, notifications, Remote Coding) plus a few concrete tool families
/// in the Caverno catalog.
enum ToolCapabilityClass {
  /// Read-only inspection of the local project or host: file/dir reads, search,
  /// and read-only network diagnostics (ping, DNS, traceroute).
  readOnlyInspection,

  /// Writes or deletes files in the workspace (`write_file`, `edit_file`,
  /// `rollback_last_file_change`).
  filesystemWrite,

  /// Runs an arbitrary local shell command or background process.
  shellExecution,

  /// Runs code/tests through a managed runner (`run_tests`,
  /// `run_python_script`).
  codeExecution,

  /// Fetches or sends data over the network (`http_get`, web fetch, web search).
  networkFetch,

  /// Runs a git command that can mutate history or push (`git_execute_command`).
  gitWrite,

  /// Executes a command on a remote host over SSH.
  sshExecution,

  /// Persists to the user's long-term memory store.
  memoryWrite,

  /// Reads or writes the system clipboard.
  clipboard,

  /// Posts a local notification.
  notification,

  /// Drives a paired Remote Coding device.
  remoteCoding,

  /// Controls the built-in browser pane (`browser_*`).
  browserControl,

  /// macOS computer-use control of other applications (`computer_*`).
  computerUse,

  /// Controls a local device (BLE, serial, Wi-Fi configuration).
  deviceControl,

  /// Anything not otherwise classified (treated conservatively as non-mutating).
  other,
}

/// Coarse risk tier for surfacing and (later) policy gating. Intentionally
/// aligned with the existing high-risk approval set (shell, filesystem write,
/// computer-use, SSH) so SEC1 does not silently re-rank current behavior.
enum ToolRiskTier { low, medium, high }

enum ToolCommandEffect {
  inspection,
  dependencyResolution,
  build,
  verification,
  formatting,
  codeGeneration,
  workspaceMutation,
  processLifecycle,
  deploymentOrRelease,
  externalSideEffect,
  unknown,
}

/// The classified capability of a single tool, plus derived properties used by
/// approval display and taint policy.
class ToolCapability {
  const ToolCapability({
    required this.toolName,
    required this.capabilityClass,
    required this.riskTier,
    required this.commandEffect,
  });

  final String toolName;
  final ToolCapabilityClass capabilityClass;
  final ToolRiskTier riskTier;
  final ToolCommandEffect commandEffect;

  /// Whether the action can change state on the local host or a remote target
  /// (filesystem, processes, git history, device, remote machine).
  bool get mutatesState => switch (capabilityClass) {
    ToolCapabilityClass.filesystemWrite ||
    ToolCapabilityClass.shellExecution ||
    ToolCapabilityClass.codeExecution ||
    ToolCapabilityClass.gitWrite ||
    ToolCapabilityClass.sshExecution ||
    ToolCapabilityClass.memoryWrite ||
    ToolCapabilityClass.clipboard ||
    ToolCapabilityClass.remoteCoding ||
    ToolCapabilityClass.computerUse ||
    ToolCapabilityClass.deviceControl => true,
    _ => false,
  };

  /// Whether the action crosses the network boundary (egress or remote control).
  bool get accessesNetwork => switch (capabilityClass) {
    ToolCapabilityClass.networkFetch ||
    ToolCapabilityClass.sshExecution ||
    ToolCapabilityClass.remoteCoding => true,
    _ => false,
  };
}

/// Pure classifier mapping a tool name (and optional arguments) to a
/// [ToolCapability]. Stateless and side-effect free.
class ToolCapabilityClassifier {
  const ToolCapabilityClassifier();

  ToolCapability classify(
    String toolName, {
    Map<String, dynamic> arguments = const <String, dynamic>{},
  }) {
    final name = toolName.trim().toLowerCase();
    final capabilityClass = _classOf(name);
    return ToolCapability(
      toolName: toolName,
      capabilityClass: capabilityClass,
      riskTier: _riskOf(capabilityClass),
      commandEffect: _effectOf(name, arguments),
    );
  }

  ToolCommandEffect _effectOf(String name, Map<String, dynamic> arguments) {
    if (_readOnlyInspectionTools.contains(name) ||
        name.startsWith('search_') ||
        name.startsWith('get_') ||
        name.startsWith('wifi_get') ||
        name.startsWith('lan_get')) {
      return ToolCommandEffect.inspection;
    }
    if (_filesystemWriteTools.contains(name)) {
      return ToolCommandEffect.workspaceMutation;
    }
    if (_memoryWriteTools.contains(name) || name.contains('clipboard')) {
      return ToolCommandEffect.externalSideEffect;
    }
    if (name == 'run_tests') {
      return ToolCommandEffect.verification;
    }
    if (name == 'run_python_script') {
      return ToolCommandEffect.externalSideEffect;
    }
    if (name.startsWith('process_')) {
      return switch (name) {
        'process_status' ||
        'process_tail' ||
        'process_wait' ||
        'process_list' => ToolCommandEffect.inspection,
        _ => ToolCommandEffect.processLifecycle,
      };
    }
    if (name == 'local_execute_command' || name == 'git_execute_command') {
      final command = (arguments['command'] as String? ?? '').trim();
      return _commandEffect(command, git: name == 'git_execute_command');
    }
    if (name == 'ssh_execute_command' ||
        name.startsWith('remote_coding') ||
        name.startsWith('remote_pair') ||
        name.startsWith('computer_') ||
        name.startsWith('browser_') ||
        name.startsWith('ble_') ||
        name.startsWith('serial_') ||
        _deviceControlTools.contains(name)) {
      return ToolCommandEffect.externalSideEffect;
    }
    return ToolCommandEffect.unknown;
  }

  ToolCommandEffect _commandEffect(String command, {required bool git}) {
    final normalized = command
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return ToolCommandEffect.unknown;
    if (git) {
      final verb = normalized.split(' ').first;
      if (const {
        'status',
        'diff',
        'log',
        'show',
        'branch',
        'tag',
        'remote',
        'rev-parse',
        'ls-files',
      }.contains(verb)) {
        return ToolCommandEffect.inspection;
      }
      if (const {'push', 'fetch', 'pull', 'clone'}.contains(verb)) {
        return ToolCommandEffect.externalSideEffect;
      }
      return ToolCommandEffect.workspaceMutation;
    }
    final commandSegments = _splitShellCommandSegments(normalized);
    if (commandSegments.length > 1) {
      final segmentEffects = commandSegments
          .map(
            (segment) =>
                _isShellStatusReportingSegment(segment) ||
                    _isShellWorkingDirectorySegment(segment)
                ? ToolCommandEffect.inspection
                : _commandEffect(segment, git: false),
          )
          .toSet();
      if (segmentEffects.contains(ToolCommandEffect.verification) &&
          segmentEffects.every(
            (effect) =>
                effect == ToolCommandEffect.verification ||
                effect == ToolCommandEffect.inspection,
          )) {
        return ToolCommandEffect.verification;
      }
      return segmentEffects.length == 1
          ? segmentEffects.single
          : ToolCommandEffect.workspaceMutation;
    }
    if (_containsShellRedirection(normalized) ||
        normalized.contains(r'$(') ||
        normalized.contains('`')) {
      return ToolCommandEffect.workspaceMutation;
    }
    if (RegExp(
          r'(^| )(dart|flutter) (test|analyze)( |$)',
        ).hasMatch(normalized) ||
        RegExp(
          r'(^| )(pytest|cargo test|npm test|pnpm test|yarn test)( |$)',
        ).hasMatch(normalized) ||
        _looksLikeVerifierScriptCommand(normalized)) {
      return ToolCommandEffect.verification;
    }
    if (RegExp(
          r'(^| )(dart|flutter) (pub get|pub upgrade)( |$)',
        ).hasMatch(normalized) ||
        RegExp(
          r'(^| )(npm|pnpm|yarn) (install|add)( |$)',
        ).hasMatch(normalized) ||
        RegExp(r'(^| )(pip|pip3) install( |$)').hasMatch(normalized)) {
      return ToolCommandEffect.dependencyResolution;
    }
    if (RegExp(r'(^| )(dart|flutter) format( |$)').hasMatch(normalized) ||
        RegExp(r'(^| )(prettier|rustfmt|gofmt)( |$)').hasMatch(normalized)) {
      return ToolCommandEffect.formatting;
    }
    if (normalized.contains('build_runner') ||
        normalized.contains('codegen') ||
        normalized.contains('generate')) {
      return ToolCommandEffect.codeGeneration;
    }
    if (_looksLikeDeploymentOrReleaseCommand(normalized)) {
      return ToolCommandEffect.deploymentOrRelease;
    }
    if (_looksLikeRuntimeBehaviorCheck(normalized)) {
      return ToolCommandEffect.verification;
    }
    if (RegExp(
          r'(^| )(dart|flutter|cargo|npm|pnpm|yarn) (run )?build( |$)',
        ).hasMatch(normalized) ||
        RegExp(r'(^| )(make|cmake)( |$)').hasMatch(normalized)) {
      return ToolCommandEffect.build;
    }
    if (RegExp(
      r'(^| )(pwd|ls|find|rg|grep|cat|head|tail|wc|which|git status|git diff|git log)( |$)',
    ).hasMatch(normalized)) {
      return ToolCommandEffect.inspection;
    }
    return ToolCommandEffect.workspaceMutation;
  }

  bool _containsShellRedirection(String command) {
    return RegExp(r'(^|\s)\d*(?:>>?|<<-?)\s*\S').hasMatch(command);
  }

  List<String> _splitShellCommandSegments(String command) {
    final segments = <String>[];
    final buffer = StringBuffer();
    String? quote;

    for (var index = 0; index < command.length; index += 1) {
      final character = command[index];
      if (quote != null) {
        if (character == '\\' && quote == '"' && index + 1 < command.length) {
          buffer
            ..write(character)
            ..write(command[index + 1]);
          index += 1;
          continue;
        }
        if (character == quote) {
          quote = null;
        }
        buffer.write(character);
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        buffer.write(character);
        continue;
      }
      final isDoubleOperator =
          index + 1 < command.length &&
          ((character == '&' && command[index + 1] == '&') ||
              (character == '|' && command[index + 1] == '|'));
      if (isDoubleOperator ||
          character == '&' ||
          character == ';' ||
          character == '|') {
        _appendShellCommandSegment(segments, buffer);
        if (isDoubleOperator) {
          index += 1;
        }
        continue;
      }
      buffer.write(character);
    }
    _appendShellCommandSegment(segments, buffer);
    return segments;
  }

  void _appendShellCommandSegment(List<String> segments, StringBuffer buffer) {
    final segment = buffer.toString().trim();
    if (segment.isNotEmpty) {
      segments.add(segment);
    }
    buffer.clear();
  }

  bool _isShellStatusReportingSegment(String command) {
    final normalized = command.trim();
    return RegExp(r'^(echo|printf)( |$)').hasMatch(normalized) &&
        !_containsShellRedirection(normalized) &&
        !normalized.contains(r'$(') &&
        !normalized.contains('`');
  }

  bool _isShellWorkingDirectorySegment(String command) {
    final normalized = command.trim();
    return RegExp(
          r'''^cd(?:\s+--)?\s+(?:'[^']*'|"[^"]*"|[^\s]+)$''',
        ).hasMatch(normalized) &&
        !_containsShellRedirection(normalized) &&
        !normalized.contains(r'$(') &&
        !normalized.contains('`') &&
        !normalized.contains('<(') &&
        !normalized.contains('>(');
  }

  bool _looksLikeRuntimeBehaviorCheck(String command) {
    return RegExp(
      r'(^| )(?:(dart run|python3?|node|bun|deno run|ruby|go run|cargo run)\s+[^ ]+|dart\s+[^ ]+\.dart(?: |$))',
    ).hasMatch(command);
  }

  bool _looksLikeDeploymentOrReleaseCommand(String command) {
    return RegExp(
      r'(^|[ /_.-])(deploy|release|publish)($|[ /_.-])',
    ).hasMatch(command);
  }

  bool _looksLikeVerifierScriptCommand(String command) {
    return RegExp(
      r'(^| )(dart run|python3?|bash|zsh|sh) [^ ]*(^|[/_-])verif(y|ier)[^ ]*( |$)',
    ).hasMatch(command);
  }

  ToolCapabilityClass _classOf(String name) {
    if (_filesystemWriteTools.contains(name)) {
      return ToolCapabilityClass.filesystemWrite;
    }
    if (name == 'local_execute_command' || name.startsWith('process_')) {
      // process_* covers start/status/tail/wait/cancel/list; only start/cancel
      // mutate, but the family is shell-adjacent and grouped here for slice 1.
      return ToolCapabilityClass.shellExecution;
    }
    if (name == 'run_tests' || name == 'run_python_script') {
      return ToolCapabilityClass.codeExecution;
    }
    if (name == 'git_execute_command') {
      return ToolCapabilityClass.gitWrite;
    }
    if (name == 'ssh_execute_command') {
      return ToolCapabilityClass.sshExecution;
    }
    if (_networkFetchTools.contains(name)) {
      return ToolCapabilityClass.networkFetch;
    }
    if (_memoryWriteTools.contains(name)) {
      return ToolCapabilityClass.memoryWrite;
    }
    if (name.contains('clipboard')) {
      return ToolCapabilityClass.clipboard;
    }
    if (name.contains('notification') || name == 'send_notification') {
      return ToolCapabilityClass.notification;
    }
    if (name.startsWith('remote_coding') || name.startsWith('remote_pair')) {
      return ToolCapabilityClass.remoteCoding;
    }
    if (name.startsWith('browser_')) {
      return ToolCapabilityClass.browserControl;
    }
    if (name.startsWith('computer_')) {
      return ToolCapabilityClass.computerUse;
    }
    if (name.startsWith('ble_') ||
        name.startsWith('serial_') ||
        _deviceControlTools.contains(name)) {
      return ToolCapabilityClass.deviceControl;
    }
    if (_readOnlyInspectionTools.contains(name) ||
        name.startsWith('search_') ||
        name.startsWith('get_') ||
        name.startsWith('wifi_get') ||
        name.startsWith('lan_get')) {
      return ToolCapabilityClass.readOnlyInspection;
    }
    return ToolCapabilityClass.other;
  }

  ToolRiskTier _riskOf(ToolCapabilityClass capabilityClass) {
    return switch (capabilityClass) {
      // High-risk: matches the existing approval-gated set plus remote/network
      // execution surfaces.
      ToolCapabilityClass.shellExecution ||
      ToolCapabilityClass.sshExecution ||
      ToolCapabilityClass.gitWrite ||
      ToolCapabilityClass.remoteCoding ||
      ToolCapabilityClass.computerUse => ToolRiskTier.high,
      // Medium-risk: mutates local state or crosses the network, but bounded.
      ToolCapabilityClass.filesystemWrite ||
      ToolCapabilityClass.codeExecution ||
      ToolCapabilityClass.networkFetch ||
      ToolCapabilityClass.memoryWrite ||
      ToolCapabilityClass.clipboard ||
      ToolCapabilityClass.deviceControl ||
      ToolCapabilityClass.browserControl => ToolRiskTier.medium,
      // Low-risk: read-only or inert.
      ToolCapabilityClass.notification ||
      ToolCapabilityClass.readOnlyInspection ||
      ToolCapabilityClass.other => ToolRiskTier.low,
    };
  }

  static const Set<String> _filesystemWriteTools = {
    'write_file',
    'edit_file',
    'delete_file',
    'rollback_last_file_change',
  };

  static const Set<String> _networkFetchTools = {
    'http_get',
    'http_head',
    'web_url_read',
    'web_fetch',
    'search_web',
    'searxng_web_search',
  };

  static const Set<String> _memoryWriteTools = {
    'remember',
    'save_memory',
    'write_memory',
    'update_memory',
  };

  static const Set<String> _deviceControlTools = {
    'wifi_connect',
    'wifi_disconnect',
  };

  static const Set<String> _readOnlyInspectionTools = {
    'read_file',
    'list_directory',
    'inspect_file',
    'find_files',
    'search_files',
    'http_status',
    'ping',
    'ping6',
    'arp',
    'ndp',
    'route_lookup',
    'interface_info',
    'whois_lookup',
    'dns_lookup',
    'dns_query',
    'port_check',
    'ssl_certificate',
    'traceroute',
    'path_mtu',
    'mdns_browse',
    'wifi_scan',
    'lan_scan',
    'get_current_datetime',
    'recall_memory',
    'search_past_conversations',
  };
}
