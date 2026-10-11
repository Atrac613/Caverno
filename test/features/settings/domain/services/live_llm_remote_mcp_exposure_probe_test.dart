import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_remote_mcp_exposure_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final toolCount in [0, 3]) {
    test('no trusted servers skip regardless of tool count: $toolCount', () {
      final result = LiveLlmRemoteMcpExposureProbe.score(
        LiveLlmDiagnosticToolCatalog(
          remoteToolCount: toolCount,
          mcpConnectionSummary: 'ignored summary',
        ),
      );
      expect(result.id, 'remote_mcp_exposure');
      expect(result.status, LiveLlmDiagnosticStatus.skipped);
      expect(result.summary, 'No trusted remote MCP servers are enabled.');
      expect(result.details, isEmpty);
      expect(result.toolCalls, isEmpty);
      expect(result.usage.totalTokens, 0);
    });
  }

  for (final summary in ['', 'connection failed', '  \n  ']) {
    test(
      'enabled server without tools warns and retains summary: $summary',
      () {
        final result = LiveLlmRemoteMcpExposureProbe.score(
          LiveLlmDiagnosticToolCatalog(
            remoteServerCount: 2,
            mcpConnectionSummary: summary,
          ),
        );
        expect(result.status, LiveLlmDiagnosticStatus.warning);
        expect(
          result.summary,
          'Remote MCP servers are enabled, but no remote tools loaded.',
        );
        expect(result.details, summary);
      },
    );
  }

  for (final summary in ['', '  \n  ', 'fixture: connected, 3 tool(s)']) {
    test(
      'visible tools pass and filter only empty summary lines: $summary',
      () {
        final result = LiveLlmRemoteMcpExposureProbe.score(
          LiveLlmDiagnosticToolCatalog(
            remoteServerCount: 1,
            remoteToolCount: 3,
            remoteToolNames: ['first', 'second'],
            mcpConnectionSummary: summary,
          ),
        );
        expect(result.status, LiveLlmDiagnosticStatus.passed);
        expect(
          result.summary,
          'Remote MCP tools are visible to the Caverno harness (3).',
        );
        expect(
          result.details,
          '${summary.trim().isEmpty ? "" : "$summary\n"}'
          'Remote tools: first, second',
        );
        expect(result.toolCalls, isEmpty);
        expect(result.modelContent, isEmpty);
        expect(result.usage.totalTokens, 0);
      },
    );
  }

  for (final length in [0, 12, 15]) {
    test('tool-name preview keeps the first twelve: length=$length', () {
      final names = List.generate(length, (index) => 'tool_$index');
      final result = LiveLlmRemoteMcpExposureProbe.score(
        LiveLlmDiagnosticToolCatalog(
          remoteServerCount: 1,
          remoteToolCount: 17,
          remoteToolNames: names,
        ),
      );
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(
        result.summary,
        'Remote MCP tools are visible to the Caverno harness (17).',
      );
      expect(result.details, 'Remote tools: ${names.take(12).join(", ")}');
      expect(names.length, length);
    });
  }

  test('nonempty connection details retain whitespace and newlines', () {
    final result = LiveLlmRemoteMcpExposureProbe.score(
      const LiveLlmDiagnosticToolCatalog(
        remoteServerCount: 1,
        remoteToolCount: 1,
        remoteToolNames: ['read'],
        mcpConnectionSummary: '  connected\nwarning  ',
      ),
    );
    expect(result.details, '  connected\nwarning  \nRemote tools: read');
  });
}
