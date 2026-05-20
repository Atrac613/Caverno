import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../settings/domain/entities/app_settings.dart';

class RoutineComputerUseActionAllowlist {
  RoutineComputerUseActionAllowlist._();

  static const routineOpenSafariUrlToolName = 'routine_open_safari_url';

  static const Set<String> _hardBlockedRiskValues = {
    'secure_field',
    'credential',
    'payment',
    'destructive',
  };

  static Set<String> allowedToolNames(
    Iterable<RoutineComputerUseActionAllowlistEntry> entries,
  ) {
    return entries
        .where(_isUsableEntry)
        .map((entry) => entry.normalizedToolName)
        .where(
          (toolName) =>
              toolName == routineOpenSafariUrlToolName ||
              (MacosComputerUseToolPolicy.isComputerUseTool(toolName) &&
                  MacosComputerUseToolPolicy.requiresUserApproval(toolName)),
        )
        .toSet();
  }

  static RoutineComputerUseActionAllowlistEntry? matchingEntry({
    required ToolCallInfo toolCall,
    required Iterable<RoutineComputerUseActionAllowlistEntry> entries,
  }) {
    if (toolCall.name == routineOpenSafariUrlToolName) {
      return _matchingSafariUrlEntry(toolCall: toolCall, entries: entries);
    }

    if (!MacosComputerUseToolPolicy.isComputerUseTool(toolCall.name) ||
        !MacosComputerUseToolPolicy.requiresUserApproval(toolCall.name)) {
      return null;
    }

    for (final entry in entries) {
      if (_matches(entry: entry, toolCall: toolCall)) {
        return entry;
      }
    }
    return null;
  }

  static RoutineComputerUseActionAllowlistEntry? _matchingSafariUrlEntry({
    required ToolCallInfo toolCall,
    required Iterable<RoutineComputerUseActionAllowlistEntry> entries,
  }) {
    for (final entry in entries) {
      if (_matchesSafariUrl(entry: entry, toolCall: toolCall)) {
        return entry;
      }
    }
    return null;
  }

  static bool _matchesSafariUrl({
    required RoutineComputerUseActionAllowlistEntry entry,
    required ToolCallInfo toolCall,
  }) {
    if (!_isUsableEntry(entry) ||
        entry.normalizedToolName != routineOpenSafariUrlToolName) {
      return false;
    }
    final url = (toolCall.arguments['url'] as String?)?.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    return _equalsIfConfigured(actual: uri.host, expected: entry.urlHost) &&
        _startsWithIfConfigured(actual: url, expected: entry.urlStartsWith);
  }

  static bool _matches({
    required RoutineComputerUseActionAllowlistEntry entry,
    required ToolCallInfo toolCall,
  }) {
    if (!_isUsableEntry(entry) || entry.normalizedToolName != toolCall.name) {
      return false;
    }

    final target = _targetMap(toolCall.arguments);
    final actualRisk = _normalize(
      _metadataValue(target, toolCall.arguments, const ['risk', 'targetRisk']),
    );
    final expectedRisk = _normalize(entry.targetRisk);
    if (_hardBlockedRiskValues.contains(actualRisk) ||
        _hardBlockedRiskValues.contains(expectedRisk)) {
      return false;
    }

    return _containsIfConfigured(
          actual: _metadataValue(target, toolCall.arguments, const [
            'label',
            'targetLabel',
          ]),
          expected: entry.targetLabelContains,
        ) &&
        _equalsIfConfigured(
          actual: _metadataValue(target, toolCall.arguments, const [
            'role',
            'targetRole',
          ]),
          expected: entry.targetRole,
        ) &&
        _equalsIfConfigured(
          actual: _metadataValue(target, toolCall.arguments, const [
            'action',
            'targetAction',
          ]),
          expected: entry.targetAction,
        ) &&
        _equalsIfConfigured(
          actual: _metadataValue(target, toolCall.arguments, const [
            'risk',
            'targetRisk',
          ]),
          expected: entry.targetRisk,
        ) &&
        _containsIfConfigured(
          actual: _metadataValue(target, toolCall.arguments, const [
            'appName',
            'applicationName',
          ]),
          expected: entry.appNameContains,
        ) &&
        _equalsIfConfigured(
          actual: _metadataValue(target, toolCall.arguments, const [
            'appBundleId',
            'bundleId',
          ]),
          expected: entry.appBundleId,
        ) &&
        _containsIfConfigured(
          actual: _metadataValue(target, toolCall.arguments, const [
            'windowTitle',
          ]),
          expected: entry.windowTitleContains,
        ) &&
        _exactTextMatches(toolCall, entry.exactText);
  }

  static bool _isUsableEntry(RoutineComputerUseActionAllowlistEntry entry) {
    return entry.enabled &&
        entry.normalizedToolName.isNotEmpty &&
        entry.hasBoundary;
  }

  static Map<String, dynamic> _targetMap(Map<String, dynamic> arguments) {
    final target = arguments['target'];
    if (target is Map<String, dynamic>) {
      return target;
    }
    if (target is Map) {
      return Map<String, dynamic>.from(target);
    }
    return const <String, dynamic>{};
  }

  static String _metadataValue(
    Map<String, dynamic> target,
    Map<String, dynamic> arguments,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = target[key] ?? arguments[key];
      if (value != null) {
        return value.toString();
      }
    }
    return '';
  }

  static bool _equalsIfConfigured({
    required String actual,
    required String expected,
  }) {
    final normalizedExpected = _normalize(expected);
    if (normalizedExpected.isEmpty) {
      return true;
    }
    return _normalize(actual) == normalizedExpected;
  }

  static bool _containsIfConfigured({
    required String actual,
    required String expected,
  }) {
    final normalizedExpected = _normalize(expected);
    if (normalizedExpected.isEmpty) {
      return true;
    }
    return _normalize(actual).contains(normalizedExpected);
  }

  static bool _startsWithIfConfigured({
    required String actual,
    required String expected,
  }) {
    final normalizedExpected = _normalize(expected);
    if (normalizedExpected.isEmpty) {
      return true;
    }
    return _normalize(actual).startsWith(normalizedExpected);
  }

  static bool _exactTextMatches(ToolCallInfo toolCall, String expected) {
    if (expected.isEmpty) {
      return true;
    }
    return (toolCall.arguments['text'] as String?) == expected;
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
