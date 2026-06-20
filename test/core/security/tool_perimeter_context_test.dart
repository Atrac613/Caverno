import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/security/data_source_classifier.dart';
import 'package:caverno/core/security/tool_capability_classifier.dart';
import 'package:caverno/core/security/tool_perimeter_context.dart';

void main() {
  const classifier = ToolPerimeterClassifier();

  group('ToolPerimeterClassifier', () {
    test('combines capability and provenance for a shell tool', () {
      final context = classifier.classify('local_execute_command');
      expect(
        context.capability.capabilityClass,
        ToolCapabilityClass.shellExecution,
      );
      expect(context.capability.riskTier, ToolRiskTier.high);
      // A local shell command's own output is local, not untrusted content.
      expect(context.resultTrust, TrustLevel.projectTrusted);
      expect(context.producesUntrustedContent, isFalse);
    });

    test('flags a network read as low-risk-to-run but untrusted output', () {
      final context = classifier.classify('http_get');
      expect(context.capability.capabilityClass, ToolCapabilityClass.networkFetch);
      expect(context.resultSource, DataSourceClass.remoteWeb);
      expect(context.resultTrust, TrustLevel.untrusted);
      expect(context.producesUntrustedContent, isTrue);
    });

    test('marks MCP tool output as untrusted regardless of capability', () {
      final context = classifier.classify('third_party_tool', isMcpTool: true);
      expect(context.resultSource, DataSourceClass.mcpResource);
      expect(context.producesUntrustedContent, isTrue);
    });

    test('treats a project read as trusted, non-mutating', () {
      final context = classifier.classify('read_file');
      expect(context.resultTrust, TrustLevel.projectTrusted);
      expect(context.capability.mutatesState, isFalse);
      expect(context.producesUntrustedContent, isFalse);
    });
  });

  group('ToolPerimeterContext.summary', () {
    test('describes a high-risk mutating shell action', () {
      final summary = classifier.classify('local_execute_command').summary;
      expect(summary, contains('shell execution'));
      expect(summary, contains('high risk'));
      expect(summary, contains('mutates host'));
    });

    test('notes untrusted output for a network fetch', () {
      final summary = classifier.classify('http_get').summary;
      expect(summary, contains('network fetch'));
      expect(summary, contains('output: untrusted'));
      expect(summary, contains('remote web'));
    });

    test('stays concise for a read-only inspection', () {
      final summary = classifier.classify('read_file').summary;
      expect(summary, contains('read-only inspection'));
      expect(summary, contains('low risk'));
      expect(summary, isNot(contains('mutates host')));
      expect(summary, isNot(contains('untrusted')));
    });
  });
}
