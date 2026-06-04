import 'package:caverno/core/services/browser_tool_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowserToolPolicy', () {
    test('classifies sensitive tools as requiring approval', () {
      const sensitive = [
        'browser_fill',
        'browser_click',
        'browser_submit',
        'browser_eval',
        'browser_save_data',
      ];
      for (final name in sensitive) {
        expect(
          BrowserToolPolicy.requiresUserApproval(name),
          isTrue,
          reason: name,
        );
        expect(
          BrowserToolPolicy.decision(name).requiresUserApproval,
          isTrue,
          reason: name,
        );
        expect(BrowserToolPolicy.decision(name).risk, BrowserToolRisk.sensitive);
      }
    });

    test('auto-runs read/observe tools without approval', () {
      const auto = [
        'browser_open',
        'browser_snapshot',
        'browser_get_content',
        'browser_screenshot',
        'browser_wait',
        'browser_navigate_history',
        'browser_close',
      ];
      for (final name in auto) {
        expect(
          BrowserToolPolicy.requiresUserApproval(name),
          isFalse,
          reason: name,
        );
        expect(BrowserToolPolicy.isBrowserTool(name), isTrue, reason: name);
        expect(BrowserToolPolicy.decision(name).risk, BrowserToolRisk.auto);
      }
    });

    test('isBrowserTool only matches the browser_ prefix', () {
      expect(BrowserToolPolicy.isBrowserTool('computer_click'), isFalse);
      expect(BrowserToolPolicy.isBrowserTool('write_file'), isFalse);
      expect(BrowserToolPolicy.isBrowserTool('browser_open'), isTrue);
    });

    test('allTools is the union of sensitive and auto tools', () {
      expect(
        BrowserToolPolicy.allTools,
        containsAll(BrowserToolPolicy.sensitiveTools),
      );
      // 7 auto tools + 5 sensitive tools.
      expect(BrowserToolPolicy.allTools.length, 12);
      // Every registered tool is recognised by the prefix check.
      for (final name in BrowserToolPolicy.allTools) {
        expect(BrowserToolPolicy.isBrowserTool(name), isTrue, reason: name);
      }
    });

    test('decision exposes non-empty approval copy', () {
      final decision = BrowserToolPolicy.decision('browser_fill');
      expect(decision.title, isNotEmpty);
      expect(decision.approveLabel, isNotEmpty);
      expect(decision.warningMessage, isNotEmpty);
      expect(decision.riskLabel, isNotEmpty);
    });
  });
}
