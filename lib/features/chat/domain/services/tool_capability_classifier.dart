/// SEC1 (Local Agent Data Perimeter), slice 1: classify what kind of action a
/// tool performs and how risky it is, so later slices can attach capability
/// context to tool calls, approval surfaces, and taint policy (SEC2).
///
/// This is pure classification. It changes no approval or execution behavior on
/// its own, so promoting it cannot weaken any existing default policy
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

/// The classified capability of a single tool, plus derived properties used by
/// approval display and taint policy.
class ToolCapability {
  const ToolCapability({
    required this.toolName,
    required this.capabilityClass,
    required this.riskTier,
  });

  final String toolName;
  final ToolCapabilityClass capabilityClass;
  final ToolRiskTier riskTier;

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
    );
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
