import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/security/tool_capability_classifier.dart';

void main() {
  const classifier = ToolCapabilityClassifier();

  ToolCapabilityClass classOf(String name) =>
      classifier.classify(name).capabilityClass;
  ToolRiskTier riskOf(String name) => classifier.classify(name).riskTier;

  group('ToolCapabilityClassifier capability classes', () {
    test('classifies filesystem writes', () {
      for (final name in ['write_file', 'edit_file', 'rollback_last_file_change']) {
        expect(classOf(name), ToolCapabilityClass.filesystemWrite, reason: name);
      }
    });

    test('classifies shell and process execution', () {
      expect(classOf('local_execute_command'), ToolCapabilityClass.shellExecution);
      expect(classOf('process_start'), ToolCapabilityClass.shellExecution);
      expect(classOf('process_status'), ToolCapabilityClass.shellExecution);
    });

    test('classifies managed code execution', () {
      expect(classOf('run_tests'), ToolCapabilityClass.codeExecution);
      expect(classOf('run_python_script'), ToolCapabilityClass.codeExecution);
    });

    test('classifies git, ssh, and remote coding', () {
      expect(classOf('git_execute_command'), ToolCapabilityClass.gitWrite);
      expect(classOf('ssh_execute_command'), ToolCapabilityClass.sshExecution);
      expect(
        classOf('remote_coding_apply_patch'),
        ToolCapabilityClass.remoteCoding,
      );
    });

    test('classifies network fetch tools', () {
      for (final name in [
        'http_get',
        'http_head',
        'web_url_read',
        'search_web',
        'searxng_web_search',
      ]) {
        expect(classOf(name), ToolCapabilityClass.networkFetch, reason: name);
      }
    });

    test('classifies device, browser, computer, and memory write families', () {
      expect(classOf('ble_connect'), ToolCapabilityClass.deviceControl);
      expect(classOf('wifi_connect'), ToolCapabilityClass.deviceControl);
      expect(classOf('browser_click'), ToolCapabilityClass.browserControl);
      expect(classOf('computer_left_click'), ToolCapabilityClass.computerUse);
      expect(classOf('remember'), ToolCapabilityClass.memoryWrite);
    });

    test('classifies read-only inspection (files and network diagnostics)', () {
      for (final name in [
        'read_file',
        'list_directory',
        'search_files',
        'ping',
        'dns_lookup',
        'traceroute',
        'http_status',
        'get_wifi_health',
        'search_past_conversations',
      ]) {
        expect(
          classOf(name),
          ToolCapabilityClass.readOnlyInspection,
          reason: name,
        );
      }
    });

    test('falls back to other for unknown tools', () {
      expect(classOf('totally_unknown_tool'), ToolCapabilityClass.other);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(classOf('  WRITE_FILE '), ToolCapabilityClass.filesystemWrite);
    });
  });

  group('ToolCapabilityClassifier risk tiers', () {
    test('high risk matches the dangerous execution surfaces', () {
      for (final name in [
        'local_execute_command',
        'ssh_execute_command',
        'git_execute_command',
        'computer_left_click',
        'remote_coding_apply_patch',
      ]) {
        expect(riskOf(name), ToolRiskTier.high, reason: name);
      }
    });

    test('medium risk for bounded state mutation and network', () {
      for (final name in ['write_file', 'run_tests', 'http_get', 'remember']) {
        expect(riskOf(name), ToolRiskTier.medium, reason: name);
      }
    });

    test('low risk for read-only and inert tools', () {
      for (final name in ['read_file', 'ping', 'get_current_datetime']) {
        expect(riskOf(name), ToolRiskTier.low, reason: name);
      }
    });
  });

  group('ToolCapability derived properties', () {
    test('mutatesState reflects state-changing classes', () {
      expect(classifier.classify('write_file').mutatesState, isTrue);
      expect(classifier.classify('local_execute_command').mutatesState, isTrue);
      expect(classifier.classify('ssh_execute_command').mutatesState, isTrue);
      expect(classifier.classify('read_file').mutatesState, isFalse);
      expect(classifier.classify('http_get').mutatesState, isFalse);
    });

    test('accessesNetwork reflects network-crossing classes', () {
      expect(classifier.classify('http_get').accessesNetwork, isTrue);
      expect(classifier.classify('ssh_execute_command').accessesNetwork, isTrue);
      expect(
        classifier.classify('remote_coding_apply_patch').accessesNetwork,
        isTrue,
      );
      expect(classifier.classify('write_file').accessesNetwork, isFalse);
      expect(classifier.classify('read_file').accessesNetwork, isFalse);
    });
  });
}
