import '../entities/live_llm_diagnostic.dart';

/// Reports remote tool exposure from an already acquired catalog snapshot.
abstract final class LiveLlmRemoteMcpExposureProbe {
  static const probeId = 'remote_mcp_exposure';

  static LiveLlmDiagnosticProbeResult score(
    LiveLlmDiagnosticToolCatalog catalog,
  ) {
    if (catalog.remoteServerCount == 0) {
      return const LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'No trusted remote MCP servers are enabled.',
      );
    }
    if (catalog.remoteToolCount == 0) {
      return LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.warning,
        summary: 'Remote MCP servers are enabled, but no remote tools loaded.',
        details: catalog.mcpConnectionSummary,
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: LiveLlmDiagnosticStatus.passed,
      summary:
          'Remote MCP tools are visible to the Caverno harness '
          '(${catalog.remoteToolCount}).',
      details: [
        catalog.mcpConnectionSummary,
        'Remote tools: ${catalog.remoteToolNames.take(12).join(", ")}',
      ].where((line) => line.trim().isNotEmpty).join('\n'),
    );
  }
}
