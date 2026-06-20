/// SEC1 (Local Agent Data Perimeter), slice 2: classify where a piece of
/// evidence came from and how far it should be trusted, so later slices can
/// keep untrusted content from being treated as a user command (acceptance
/// criterion 2) and surface provenance on tool calls (criterion 1).
///
/// Pure classification, additive: it changes no execution or approval behavior
/// on its own. Provenance is the *immediate* producing tool; chained taint
/// across tool calls is SEC2.
library;

/// Where a piece of content originated.
enum DataSourceClass {
  /// Typed directly by the user in this conversation.
  userInstruction,

  /// Files inside the user's own coding project (read_file, list_directory).
  projectSource,

  /// Installed dependency source resolved from the project's lockfile.
  dependencySource,

  /// Model- or rule-generated text such as extracted memory and summaries.
  generatedSummary,

  /// Content fetched from the network (web pages, search results, browser DOM,
  /// and remote-server-controlled fields such as WHOIS / certificate subjects).
  remoteWeb,

  /// A resource or tool result served by an MCP server (third-party provenance).
  mcpResource,

  /// A document explicitly marked untrusted by the caller.
  untrustedDocument,

  /// Local host/network diagnostics (ping, DNS, interface info): local facts,
  /// not a document carrying instructions.
  localDiagnostic,

  /// Unknown provenance; defaults to a local (project) trust level.
  other,
}

/// How far content may be trusted to *instruct* the agent, distinct from how
/// useful it is as information.
enum TrustLevel {
  /// The user's own direct instruction.
  userTrusted,

  /// Local, user-controlled data (project files, deps, local diagnostics, the
  /// user's own generated memory). Informative; not an authority equal to the
  /// user's direct command.
  projectTrusted,

  /// Third-party / remote content that can be attacker-influenced. Informative
  /// only — it must never be promoted to a user command with tool authority.
  untrusted,
}

/// Pure classifier for content provenance and trust. Stateless and
/// side-effect free.
class DataSourceClassifier {
  const DataSourceClassifier();

  /// Classify the immediate provenance of a tool result by the tool that
  /// produced it. [isMcpTool] is set by the caller for MCP-served tools, whose
  /// names are arbitrary and cannot be recognized from the name alone.
  DataSourceClass classifyToolResultSource(
    String toolName, {
    bool isMcpTool = false,
  }) {
    if (isMcpTool) {
      return DataSourceClass.mcpResource;
    }
    final name = toolName.trim().toLowerCase();
    if (_projectSourceTools.contains(name)) {
      return DataSourceClass.projectSource;
    }
    if (name == 'resolve_installed_dependency') {
      return DataSourceClass.dependencySource;
    }
    if (_generatedSummaryTools.contains(name)) {
      return DataSourceClass.generatedSummary;
    }
    if (_remoteWebTools.contains(name) ||
        name.startsWith('search_') &&
            name != 'search_files' &&
            name != 'search_past_conversations' ||
        name.startsWith('browser_get') ||
        name.startsWith('browser_snapshot') ||
        name.startsWith('browser_screenshot')) {
      return DataSourceClass.remoteWeb;
    }
    if (_localDiagnosticTools.contains(name) ||
        name.startsWith('wifi_') ||
        name.startsWith('lan_') ||
        name.startsWith('get_')) {
      return DataSourceClass.localDiagnostic;
    }
    return DataSourceClass.other;
  }

  /// Map a [DataSourceClass] to the level at which its content may instruct the
  /// agent. Unknown/local provenance defaults to [TrustLevel.projectTrusted];
  /// only remote, MCP, and explicitly-untrusted content is [TrustLevel.untrusted].
  TrustLevel trustLevelOf(DataSourceClass source) {
    return switch (source) {
      DataSourceClass.userInstruction => TrustLevel.userTrusted,
      DataSourceClass.projectSource ||
      DataSourceClass.dependencySource ||
      DataSourceClass.generatedSummary ||
      DataSourceClass.localDiagnostic ||
      DataSourceClass.other => TrustLevel.projectTrusted,
      DataSourceClass.remoteWeb ||
      DataSourceClass.mcpResource ||
      DataSourceClass.untrustedDocument => TrustLevel.untrusted,
    };
  }

  /// Whether [text] contains a credential-like secret that should not be echoed,
  /// logged, or persisted. Conservative, prefix/format-anchored to avoid
  /// flagging ordinary prose.
  bool looksLikeCredential(String text) {
    if (text.isEmpty) {
      return false;
    }
    return _credentialPatterns.any((pattern) => pattern.hasMatch(text));
  }

  /// Whether [text] looks like it is trying to *instruct* the agent rather than
  /// merely inform it (a prompt-injection signal). Used by later slices to keep
  /// untrusted content from being promoted to a user command.
  bool containsInjectionAttempt(String text) {
    if (text.isEmpty) {
      return false;
    }
    if (text.contains('<tool_call>') ||
        text.contains('<tool_use>') ||
        text.contains('<system>')) {
      return true;
    }
    final normalized = text.toLowerCase();
    return _injectionPhrases.any(normalized.contains);
  }

  static const Set<String> _projectSourceTools = {
    'read_file',
    'list_directory',
    'inspect_file',
    'find_files',
    'search_files',
    'search_past_conversations',
  };

  static const Set<String> _generatedSummaryTools = {
    'recall_memory',
  };

  static const Set<String> _remoteWebTools = {
    'http_get',
    'http_head',
    'web_url_read',
    'web_fetch',
    'search_web',
    'searxng_web_search',
    'search_news',
    'search_images',
    'search_videos',
    'whois_lookup',
    'ssl_certificate',
  };

  static const Set<String> _localDiagnosticTools = {
    'ping',
    'ping6',
    'arp',
    'ndp',
    'route_lookup',
    'interface_info',
    'dns_lookup',
    'dns_query',
    'port_check',
    'traceroute',
    'path_mtu',
    'mdns_browse',
    'http_status',
    'get_current_datetime',
  };

  static final List<RegExp> _credentialPatterns = [
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
    RegExp(r'\bsk-[A-Za-z0-9]{20,}'),
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
    RegExp(r'\bghp_[A-Za-z0-9]{36}\b'),
    RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}'),
    RegExp(r'\bey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'),
    RegExp(
      r'(?:password|passwd|secret|api[_-]?key|token)\s*[:=]\s*\S{6,}',
      caseSensitive: false,
    ),
  ];

  static const List<String> _injectionPhrases = [
    'ignore previous instructions',
    'ignore all previous',
    'ignore the above',
    'disregard previous',
    'disregard the above',
    'you are now',
    'new instructions:',
    'system prompt:',
    'override your',
  ];
}
