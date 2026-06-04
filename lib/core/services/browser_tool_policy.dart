/// Risk classification and approval copy for the built-in browser tools.
///
/// This mirrors the role of `MacosComputerUseToolPolicy` but is intentionally
/// lighter: browser actions only need a binary "auto vs. requires approval"
/// decision plus human-readable copy for the approval sheet. Read/observe
/// actions (navigate, snapshot, scrape, screenshot) run automatically; actions
/// that mutate page/site state or expose credentials require explicit approval.
enum BrowserToolRisk { auto, sensitive }

class BrowserToolPolicyDecision {
  const BrowserToolPolicyDecision({
    required this.toolName,
    required this.risk,
    required this.title,
    required this.riskLabel,
    required this.approveLabel,
    required this.warningMessage,
  });

  final String toolName;
  final BrowserToolRisk risk;
  final String title;
  final String riskLabel;
  final String approveLabel;
  final String warningMessage;

  bool get requiresUserApproval => risk == BrowserToolRisk.sensitive;

  Map<String, dynamic> toJson() => {
    'toolName': toolName,
    'risk': risk.name,
    'requiresUserApproval': requiresUserApproval,
  };
}

class BrowserToolPolicy {
  BrowserToolPolicy._();

  static const String prefix = 'browser_';

  /// Tools that mutate page/site state or expose credentials, and therefore
  /// require explicit user approval before running.
  static const Set<String> sensitiveTools = {
    'browser_fill',
    'browser_click',
    'browser_submit',
    'browser_eval',
    'browser_save_data',
  };

  /// All browser tool names exposed to the model. Kept here so the tool
  /// registry and the reserved-name guard share a single source of truth.
  static const Set<String> allTools = {
    'browser_open',
    'browser_snapshot',
    'browser_get_content',
    'browser_screenshot',
    'browser_wait',
    'browser_navigate_history',
    'browser_close',
    ...sensitiveTools,
  };

  static bool isBrowserTool(String name) => name.startsWith(prefix);

  static bool requiresUserApproval(String name) =>
      sensitiveTools.contains(name);

  static BrowserToolPolicyDecision decision(String name) {
    final sensitive = requiresUserApproval(name);
    return BrowserToolPolicyDecision(
      toolName: name,
      risk: sensitive ? BrowserToolRisk.sensitive : BrowserToolRisk.auto,
      title: _title(name),
      riskLabel: sensitive ? 'Sensitive browser action' : 'Browser action',
      approveLabel: _approveLabel(name),
      warningMessage: _warning(name),
    );
  }

  static String _title(String name) => switch (name) {
    'browser_fill' => 'Fill a form field',
    'browser_click' => 'Click a page element',
    'browser_submit' => 'Submit a form',
    'browser_eval' => 'Run JavaScript in the page',
    'browser_save_data' => 'Save data to a file',
    _ => 'Browser action',
  };

  static String _approveLabel(String name) => switch (name) {
    'browser_submit' => 'Submit',
    'browser_save_data' => 'Save',
    'browser_eval' => 'Run script',
    _ => 'Approve',
  };

  static String _warning(String name) => switch (name) {
    'browser_fill' =>
      'The agent wants to type into a form field in the built-in browser.',
    'browser_click' =>
      'The agent wants to click an element, which may change page state or navigate.',
    'browser_submit' =>
      'The agent wants to submit a form (for example, a login).',
    'browser_eval' =>
      'The agent wants to run arbitrary JavaScript in the current page.',
    'browser_save_data' =>
      'The agent wants to write extracted data to a file on this device.',
    _ => 'The agent wants to perform a browser action.',
  };
}
