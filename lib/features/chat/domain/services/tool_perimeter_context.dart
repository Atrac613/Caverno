import 'data_source_classifier.dart';
import 'tool_capability_classifier.dart';

/// SEC1 (Local Agent Data Perimeter), slice 3: one descriptor that unifies a
/// tool call's capability ([ToolCapabilityClassifier]) and the provenance/trust
/// of the content it produces ([DataSourceClassifier]), plus a short
/// human-readable [summary] for the approval surface (acceptance criterion 1).
///
/// Pure and additive: it computes context only. It does not gate, cache, or
/// re-rank any approval, so it cannot weaken an existing default (criterion 3).
class ToolPerimeterContext {
  const ToolPerimeterContext({
    required this.capability,
    required this.resultSource,
    required this.resultTrust,
  });

  /// What kind of action the tool performs and how risky it is.
  final ToolCapability capability;

  /// Provenance of the content this tool produces (e.g. remote web vs local
  /// project file). Distinct from the action's risk: a read-only `http_get` is
  /// low-risk to run but yields `untrusted` remote content.
  final DataSourceClass resultSource;

  /// How far the produced content may be trusted to instruct the agent.
  final TrustLevel resultTrust;

  /// Whether this tool yields content that must not be promoted to a user
  /// command (remote web, MCP, or explicitly-untrusted document).
  bool get producesUntrustedContent => resultTrust == TrustLevel.untrusted;

  /// A compact one-line summary for approval display and the audit trail, e.g.
  /// "shell execution · high risk · mutates host" or
  /// "network fetch · medium risk · output: untrusted (remote web)".
  String get summary {
    final parts = <String>[
      _capabilityLabel(capability.capabilityClass),
      '${_riskLabel(capability.riskTier)} risk',
    ];
    if (capability.mutatesState) {
      parts.add('mutates host');
    }
    if (capability.accessesNetwork) {
      parts.add('network');
    }
    if (producesUntrustedContent) {
      parts.add('output: untrusted (${_sourceLabel(resultSource)})');
    }
    return parts.join(' · ');
  }

  static String _capabilityLabel(ToolCapabilityClass value) {
    return switch (value) {
      ToolCapabilityClass.readOnlyInspection => 'read-only inspection',
      ToolCapabilityClass.filesystemWrite => 'filesystem write',
      ToolCapabilityClass.shellExecution => 'shell execution',
      ToolCapabilityClass.codeExecution => 'code execution',
      ToolCapabilityClass.networkFetch => 'network fetch',
      ToolCapabilityClass.gitWrite => 'git command',
      ToolCapabilityClass.sshExecution => 'SSH execution',
      ToolCapabilityClass.memoryWrite => 'memory write',
      ToolCapabilityClass.clipboard => 'clipboard access',
      ToolCapabilityClass.notification => 'notification',
      ToolCapabilityClass.remoteCoding => 'remote coding',
      ToolCapabilityClass.browserControl => 'browser control',
      ToolCapabilityClass.computerUse => 'computer-use control',
      ToolCapabilityClass.deviceControl => 'device control',
      ToolCapabilityClass.other => 'other',
    };
  }

  static String _riskLabel(ToolRiskTier value) {
    return switch (value) {
      ToolRiskTier.low => 'low',
      ToolRiskTier.medium => 'medium',
      ToolRiskTier.high => 'high',
    };
  }

  static String _sourceLabel(DataSourceClass value) {
    return switch (value) {
      DataSourceClass.userInstruction => 'user instruction',
      DataSourceClass.projectSource => 'project source',
      DataSourceClass.dependencySource => 'dependency source',
      DataSourceClass.generatedSummary => 'generated summary',
      DataSourceClass.remoteWeb => 'remote web',
      DataSourceClass.mcpResource => 'MCP resource',
      DataSourceClass.untrustedDocument => 'untrusted document',
      DataSourceClass.localDiagnostic => 'local diagnostic',
      DataSourceClass.other => 'unknown',
    };
  }
}

/// Pure aggregator that builds a [ToolPerimeterContext] from a tool name by
/// composing the capability and data-source classifiers.
class ToolPerimeterClassifier {
  const ToolPerimeterClassifier({
    ToolCapabilityClassifier capability = const ToolCapabilityClassifier(),
    DataSourceClassifier dataSource = const DataSourceClassifier(),
  }) : _capability = capability,
       _dataSource = dataSource;

  final ToolCapabilityClassifier _capability;
  final DataSourceClassifier _dataSource;

  ToolPerimeterContext classify(
    String toolName, {
    Map<String, dynamic> arguments = const <String, dynamic>{},
    bool isMcpTool = false,
  }) {
    final source = _dataSource.classifyToolResultSource(
      toolName,
      isMcpTool: isMcpTool,
    );
    return ToolPerimeterContext(
      capability: _capability.classify(toolName, arguments: arguments),
      resultSource: source,
      resultTrust: _dataSource.trustLevelOf(source),
    );
  }
}
